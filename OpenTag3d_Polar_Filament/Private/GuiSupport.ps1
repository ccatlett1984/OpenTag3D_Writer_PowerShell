# Support for Show-OpenTag3DGui: response writing, request dispatch, and the page itself.

function Write-HttpResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)] [string]$ContentType,
        [Parameter(Mandatory)] [string]$Body
    )
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        $Context.Response.ContentType     = $ContentType
        $Context.Response.ContentLength64 = $bytes.Length
        $Context.Response.Headers.Add('Cache-Control','no-store')
        $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Context.Response.OutputStream.Close()
    }
    catch {
        # Client went away, or the listener already answered (e.g. 411 on a bodyless POST).
        # Normal for a web server; never worth taking the UI down for.
        Write-Verbose "Could not send response: $($_.Exception.Message)"
    }
}

function Invoke-OpenTag3DGuiAction {
    <#
    .SYNOPSIS
        Runs one export or write on behalf of the UI and returns a result object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('export','write','read','load','apply','profile')] [string]$Action,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Body,
        [Parameter(Mandatory)] [bool]$CanWrite
    )

    if ([string]::IsNullOrWhiteSpace($Body)) { return @{ ok = $false; message = 'Empty request.' } }
    try { $r = $Body | ConvertFrom-Json }
    catch { return @{ ok = $false; message = 'Malformed request.' } }

    # --- load: fetch, read or build a payload and return it as editable fields ---
    if ($Action -eq 'load') {
        try {
            $mode = if ("$($r.mode)" -in 'Core','Extended') { "$($r.mode)" }
                    elseif ($r.tagType -eq 'NTAG213') { 'Core' }
                    else { 'Extended' }

            $wanted = if ("$($r.specVersion)" -in $script:OpenTag3DSpecVersions) { "$($r.specVersion)" }
                      else { $script:OpenTag3DDefaultSpecVersion }

            # A hand-built tag has no lookup behind it, so its serial is the vendor's own
            # batch id and stays editable. A Polar payload keeps the serial locked: it is
            # the key the data came from.
            $generic   = $false
            $converted = $null

            if ($r.source -eq 'tag') {
                if (-not $CanWrite) { return @{ ok = $false; message = 'No PC/SC reader available.' } }
                $p = @{}
                if ($r.readerName) { $p.ReaderName = $r.readerName }
                $tag = Read-OpenTag3DTag @p -Raw
                $payload = $tag.PayloadBytes
            }
            elseif ($r.source -eq 'new') {
                $generic = $true
                $payload = New-OpenTag3DBlankPayload -Mode $mode -SpecVersion $wanted
            }
            elseif ($r.source -eq 'profile') {
                $generic = $true
                if ([string]::IsNullOrWhiteSpace($r.profileName)) { return @{ ok = $false; message = 'Choose a profile to load.' } }
                $prof    = Get-OpenTag3DProfile -Name $r.profileName
                if (-not ("$($r.mode)" -in 'Core','Extended')) { $mode = $prof.Mode }
                # A profile is a set of values, not a layout: it loads into whichever version
                # is selected, and the encoder ignores ids that version does not have.
                $payload = New-OpenTag3DGenericPayload -Values $prof.Values -Mode $mode -SpecVersion $wanted
            }
            else {
                if ([string]::IsNullOrWhiteSpace($r.serial)) { return @{ ok = $false; message = 'Enter a spool serial.' } }
                # -PassThru keeps this off the disk entirely.
                $img = Export-OpenTag3DPayload -TagType $r.tagType -Serial $r.serial -Mode $mode -Format Ndef -PassThru -InformationAction SilentlyContinue -WarningAction SilentlyContinue
                $payload = Get-OpenTag3DNdefPayload -UserMemory $img

                # The service picks the version; convert only if the page asked for the other.
                $served = Get-OpenTag3DPayloadVersion -Payload $payload
                if ($served -and $served -ne $wanted) {
                    $payload  = Convert-OpenTag3DPayload -Payload $payload -ToSpecVersion $wanted -FromSpecVersion $served -WarningVariable convWarn -WarningAction SilentlyContinue
                    $converted = "Converted from OpenTag3D $served to $wanted." +
                                 $(if ($convWarn) { ' ' + (($convWarn | ForEach-Object { "$_" }) -join ' ') } else { '' })
                }
            }

            $editable = @(Get-OpenTag3DEditableField -Payload $payload -AllowSerial:$generic -BlankUnset:$generic)
            $actual   = Get-OpenTag3DPayloadVersion -Payload $payload

            $byId = @{}
            foreach ($e in $editable) { $byId[$e.id] = $e.value }
            $title = (@($byId['material'], $byId['material_mod'], $byId['color_name']) |
                        Where-Object { $_ }) -join " $([char]0x00B7) "
            if (-not $title) {
                $title = if ($r.source -eq 'profile') { "Profile $([char]0x00B7) $($r.profileName)" }
                         elseif ($generic) { 'New tag (generic vendor)' }
                         else { 'Tag data' }
            }

            return @{
                ok          = $true
                fields      = @($editable)
                payloadHex  = ([BitConverter]::ToString($payload) -replace '-')
                generic     = $generic
                mode        = $mode
                specVersion = $actual
                hasModes    = (Get-OpenTag3DSpec -SpecVersion $actual).HasModes
                note        = $converted
                title       = $title
            }
        }
        catch { return @{ ok = $false; message = $_.Exception.Message } }
    }

    # --- profile: list, save and delete saved vendor profiles ---
    if ($Action -eq 'profile') {
        try {
            switch ("$($r.op)") {
                'list' { return @{ ok = $true; profiles = @(Get-OpenTag3DProfileList) } }
                'save' {
                    $values = @{}
                    if ($r.values) {
                        foreach ($kv in $r.values.PSObject.Properties) { $values[$kv.Name] = $kv.Value }
                    }
                    if ($values.Count -eq 0) { return @{ ok = $false; message = 'Nothing to save.' } }
                    $mode = if ("$($r.mode)" -in 'Core','Extended') { "$($r.mode)" } else { 'Extended' }
                    $type = if ("$($r.tagType)" -in 'NTAG213','NTAG215','NTAG216') { "$($r.tagType)" } else { 'NTAG215' }
                    $sv   = if ("$($r.specVersion)" -in $script:OpenTag3DSpecVersions) { "$($r.specVersion)" } else { $script:OpenTag3DDefaultSpecVersion }
                    $path = Save-OpenTag3DProfile -Name "$($r.name)" -Values $values -TagType $type -Mode $mode -SpecVersion $sv
                    return @{ ok = $true; message = "Saved profile to $path"; profiles = @(Get-OpenTag3DProfileList); name = "$($r.name)" }
                }
                'delete' {
                    Remove-OpenTag3DProfile -Name "$($r.name)"
                    return @{ ok = $true; message = "Deleted profile '$($r.name)'."; profiles = @(Get-OpenTag3DProfileList) }
                }
                default { return @{ ok = $false; message = "Unknown profile operation '$($r.op)'." } }
            }
        }
        catch { return @{ ok = $false; message = $_.Exception.Message } }
    }

    # --- apply: encode edited values and either save or write ---
    if ($Action -eq 'apply') {
        try {
            if ([string]::IsNullOrWhiteSpace($r.payloadHex)) { return @{ ok = $false; message = 'Nothing loaded to save.' } }
            $hex  = $r.payloadHex
            $base = [byte[]]::new($hex.Length / 2)
            for ($i = 0; $i -lt $base.Length; $i++) { $base[$i] = [Convert]::ToByte($hex.Substring($i*2,2),16) }

            # Read-only fields are enforced here, not just disabled in the browser: a hand-made
            # request must not be able to rewrite the serial on a payload that came from a
            # lookup. A hand-built tag owns its serial, so only the tag version is fixed.
            $readOnly = if ($r.generic) { $script:OpenTag3DGenericReadOnly } else { $script:OpenTag3DReadOnly }
            $values = @{}
            foreach ($kv in $r.values.PSObject.Properties) {
                if ($kv.Name -in $readOnly) { continue }
                $values[$kv.Name] = $kv.Value
            }

            # Encode once, untruncated: the truncation preview, the payload written and the
            # file name all come from this.
            $full = ConvertTo-OpenTag3DPayload -BasePayload $base -Values $values -WarningAction SilentlyContinue

            # The base payload carries its own version, so the encoder above used the right
            # table. Everything from here on has to agree with it.
            $version = Get-OpenTag3DPayloadVersion -Payload $base
            $spec    = Get-OpenTag3DSpec -SpecVersion $version

            if ($r.tagType -eq 'NTAG213' -and $spec.Major -ge 2) {
                return @{ ok = $false; message = "OpenTag3D $version cannot be written to an NTAG213: the payload is $($full.Length) bytes against 144 bytes of user memory. Choose NTAG215 or NTAG216, or switch the spec version to 1.003." }
            }

            # NTAG213 holds 1.003 Core only; cut the payload at 0x70. Anything populated above
            # that address is lost, so say what will go and require an explicit confirmation.
            $truncate = if ($spec.HasModes -and $r.tagType -eq 'NTAG213' -and $full.Length -gt 112) { 112 } else { 0 }
            if ($truncate) {
                $all      = @(ConvertFrom-OpenTag3DPayload -Payload $full | Select-Object -ExpandProperty Fields)
                $dropping = @($all | Where-Object { $_.Section -eq 'Extended' })
                $keeping  = @($all | Where-Object { $_.Section -ne 'Extended' })
                if ($dropping.Count -and -not $r.confirmTruncate) {
                    return @{
                        ok      = $false
                        confirm = 'truncate'
                        message = "NTAG213 stores OpenTag3D Core only. These $($keeping.Count) field(s) are all that will be kept:"
                        keeping = @($keeping | ForEach-Object { @{ name = $_.Name; value = "$($_.Value)" } })
                        dropped = $dropping.Count
                    }
                }
            }
            $payload = if ($truncate) { [byte[]]$full[0..($truncate - 1)] } else { $full }

            $record = New-OpenTag3DNdefRecord -Payload $payload
            $image  = New-OpenTag3DImage -Data $record -TagType $r.tagType -Format Ndef

            # 2.x marks ten fields required. An incomplete tag is still a tag, so this is
            # said rather than enforced.
            $missing = @(Get-OpenTag3DMissingRequiredField -Values $values -SpecVersion $version)
            $warn    = if ($missing.Count) { " Required by $($version) but left empty: $($missing -join ', ')." } else { '' }

            if ($r.target -eq 'tag') {
                if (-not $CanWrite) { return @{ ok = $false; message = 'No PC/SC reader available.' } }
                $p = @{ Bytes = $image }
                if ($r.readerName) { $p.ReaderName = $r.readerName }
                $text = (Write-OpenTag3DTag @p 6>&1 3>&1 | Out-String).Trim()
                $msg = if ($text) { $text } else { 'Written.' }
                return @{ ok = $true; message = $msg + $warn }
            }

            $dir = if ($r.outputDir) { $r.outputDir } else { Get-OpenTag3DDefaultOutputDir }
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                return @{ ok = $false; message = "Output directory not found: $dir" }
            }
            # Name from the untruncated payload: an NTAG213 cut at 0x70 has no serial field.
            $decoded = ConvertFrom-OpenTag3DPayload -Payload $full
            $parts = if ($decoded.serial) { @($decoded.serial) }
                     else { @($decoded.manufacturer, $decoded.material, $decoded.color_name) }
            $name = (@($parts | Where-Object { $_ }) -join '-')
            $name = ($name -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
            if (-not $name) { $name = 'opentag3d' }
            # Name the version outright rather than only when it is not the default: with two
            # formats in routine use, an unlabelled file is ambiguous a month later.
            $label = if ($r.generic) { 'Generic' } else { 'Edited' }
            $label = "$label-$version"
            $path = Join-Path $dir "$name-$($r.tagType)-$label-Ndef.bin"
            [IO.File]::WriteAllBytes($path, $image)
            return @{ ok = $true; message = "Wrote $($image.Length) bytes to $path" + $warn }
        }
        catch { return @{ ok = $false; message = $_.Exception.Message } }
    }

    if ($Action -eq 'read') {
        if (-not $CanWrite) { return @{ ok = $false; message = 'No PC/SC reader available.' } }
        try {
            $p = @{}
            if ($r.readerName) { $p.ReaderName = $r.readerName }
            $tag  = Read-OpenTag3DTag @p
            # Group headings are version-specific - Core/Extended for 1.003, Display /
            # Inventory / Operational for 2.x - so the page is told them rather than
            # assuming a set and silently dropping every row that does not match.
            $spec = Get-OpenTag3DSpec -SpecVersion $tag.SpecVersion
            return @{
                ok          = $true
                fields      = @($tag.Fields | ForEach-Object { @{ name = $_.Name; value = "$($_.Value)"; section = $_.Section } })
                groups      = @($spec.GroupOrder)
                specVersion = $tag.SpecVersion
                color       = "$($tag.color_1)"
                title       = (@($tag.material, $tag.material_mod, $tag.color_name) | Where-Object { $_ }) -join " $([char]0x00B7) "
            }
        }
        catch { return @{ ok = $false; message = $_.Exception.Message } }
    }

    if ([string]::IsNullOrWhiteSpace($r.serial)) {
        return @{ ok = $false; message = 'Enter a spool serial.' }
    }
    if ($Action -eq 'write' -and -not $CanWrite) {
        return @{ ok = $false; message = 'No PC/SC reader available.' }
    }

    $p = @{
        TagType = $r.tagType
        Serial  = $r.serial
        Format  = $r.format
    }
    if ($r.mode) { $p.Mode = $r.mode }   # blank means "let the cmdlet default per tag type"

    if ($Action -eq 'write') {
        $p.WriteToTag = $true
        if ($r.readerName) { $p.ReaderName = $r.readerName }
    }
    elseif ($r.outputDir) {
        $p.OutputDir = $r.outputDir
    }

    try {
        # Write-Host output from the cmdlets goes to the information stream; capture it for the page.
        $text = (Export-OpenTag3DPayload @p 6>&1 3>&1 | Out-String).Trim()
        return @{ ok = $true; message = if ($text) { $text } else { 'Done.' } }
    }
    catch {
        return @{ ok = $false; message = $_.Exception.Message }
    }
}

function Get-OpenTag3DGuiHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [bool]$CanWrite,
        [Parameter(Mandatory)] [string]$DefaultDir,
        [string]$PcscError
    )

    $page = @'
<!doctype html>
<meta charset="utf-8">
<title>OpenTag3D - Polar Filament</title>
<style>
  :root {
    color-scheme: light dark;
    --edge:#8883; --accent:#c2410c;
    --bg:#ffffff; --fg:#141414; --field:#ffffff; --field-fg:#141414;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#1b1b1d; --fg:#ececec; --field:#2a2a2e; --field-fg:#ececec; }
  }
  body { font:15px/1.5 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
         max-width:33rem; margin:3rem auto; padding:0 1.25rem;
         background:var(--bg); color:var(--fg); }
  h1 { font-size:1.3rem; margin:0 0 .25rem; letter-spacing:-.01em; }
  p.sub { margin:0 0 1.75rem; opacity:.65; font-size:.9rem; }
  fieldset { border:1px solid var(--edge); border-radius:8px; padding:1rem 1.1rem 1.2rem; margin:0 0 1.1rem; }
  legend { padding:0 .4rem; font-size:.8rem; text-transform:uppercase; letter-spacing:.07em; opacity:.6; }
  label { display:block; margin:.7rem 0 .2rem; font-size:.85rem; opacity:.8; }
  input,select { width:100%; box-sizing:border-box; padding:.5rem .6rem; font:inherit;
                 border:1px solid var(--edge); border-radius:6px;
                 background:var(--field); color:var(--field-fg); }
  /* Native option popups paint their own background, so set both explicitly or dark mode
     ends up white-on-white. */
  option { background:var(--field); color:var(--field-fg); }
  input::placeholder { color:var(--fg); opacity:.45; }
  input:focus,select:focus { outline:2px solid var(--accent); outline-offset:1px; }
  /* Wraps rather than squeezing: the edit screen's row carries four controls since the
     spec version selector arrived, and four across truncates their labels. */
  .row { display:flex; gap:.75rem; flex-wrap:wrap; }
  .row > div { flex:1 1 9rem; min-width:0; }
  .actions { display:flex; gap:.6rem; margin-top:1.4rem; align-items:center; }
  button { padding:.55rem 1.1rem; font:inherit; border-radius:6px; border:1px solid var(--edge);
           background:var(--field); color:var(--field-fg); cursor:pointer; }
  button.primary { background:var(--accent); border-color:var(--accent); color:#fff; }
  button:disabled { opacity:.4; cursor:not-allowed; }
  #out { margin-top:1.3rem; padding:.8rem .9rem; border-radius:6px; border:1px solid var(--edge);
         background:var(--field); color:var(--field-fg);
         white-space:pre-wrap; font:13px ui-monospace,SFMono-Regular,Consolas,monospace; display:none; }
  #out.ok  { border-color:#16a34a88; }
  #out.err { border-color:#dc262688; }
  .note { font-size:.82rem; opacity:.7; margin:.6rem 0 0; }
  #stop { margin-left:auto; opacity:.55; font-size:.85rem; }
  #tag { margin-top:1.3rem; display:none; }
  #tag h2 { font-size:1rem; margin:0 0 .2rem; display:flex; align-items:center; gap:.5rem; }
  #tag .swatch { width:1rem; height:1rem; border-radius:3px; border:1px solid var(--edge); display:inline-block; }
  #tag .ver { font-size:.72rem; font-weight:400; opacity:.55; letter-spacing:.04em;
              text-transform:uppercase; margin-left:auto; }
  #tag table { width:100%; border-collapse:collapse; font-size:.86rem; }
  #tag th { text-align:left; font-weight:600; opacity:.55; font-size:.72rem; text-transform:uppercase;
            letter-spacing:.06em; padding:.9rem 0 .3rem; border-bottom:1px solid var(--edge); }
  #tag td { padding:.3rem .5rem .3rem 0; border-bottom:1px solid var(--edge); vertical-align:top; }
  #tag td.k { opacity:.7; width:45%; }
  .tabs { display:flex; gap:.4rem; margin:0 0 1.2rem; border-bottom:1px solid var(--edge); }
  .tab { border:none; border-bottom:2px solid transparent; border-radius:0; background:none;
         padding:.5rem .8rem; opacity:.6; font-size:.9rem; }
  .tab.active { opacity:1; border-bottom-color:var(--accent); font-weight:600; }
  .fgroup { margin:1.1rem 0 .2rem; font-size:.72rem; text-transform:uppercase; letter-spacing:.06em;
            opacity:.55; border-bottom:1px solid var(--edge); padding-bottom:.3rem; }
  .frow { display:flex; align-items:center; gap:.6rem; margin:.35rem 0; }
  .frow label { flex:0 0 45%; margin:0; font-size:.84rem; opacity:.85; }
  .frow input { flex:1; padding:.35rem .5rem; }
  .frow input[readonly] { opacity:.55; cursor:not-allowed; }
  /* Colour rows: hex text stays authoritative, the picker and the clear button drive it. */
  .frow input[type=color] { flex:0 0 2.1rem; width:2.1rem; height:1.9rem; padding:1px;
                            cursor:pointer; background:var(--field); }
  .frow input[type=color]::-webkit-color-swatch-wrapper { padding:1px; }
  .frow input[type=color]::-webkit-color-swatch { border:none; border-radius:3px; }
  .frow .clr { flex:0 0 auto; padding:.15rem .45rem; font-size:.85rem; line-height:1.2;
               opacity:.6; }
  .frow .clr:hover { opacity:1; }
  .frow .unset { opacity:.35; }
  .prow { display:flex; gap:.5rem; align-items:flex-end; }
  .prow > div { flex:1; }
  .prow button { flex:0 0 auto; }
  #editOut { margin-top:1.2rem; padding:.8rem .9rem; border-radius:6px; border:1px solid var(--edge);
             background:var(--field); color:var(--field-fg); white-space:pre-wrap;
             font:13px ui-monospace,SFMono-Regular,Consolas,monospace; display:none; }
  #editOut.ok { border-color:#16a34a88; } #editOut.err { border-color:#dc262688; }
  #confirm { margin-top:1.2rem; padding:.9rem 1rem; border-radius:6px; border:1px solid #d9770688;
             background:var(--field); color:var(--field-fg); display:none; }
  #confirm h3 { margin:0 0 .4rem; font-size:.92rem; }
  #confirm ul { margin:.5rem 0 .9rem; padding-left:1.1rem; font:13px ui-monospace,SFMono-Regular,Consolas,monospace; }
  #confirm li { margin:.12rem 0; }
  #confirm .actions { margin-top:.8rem; }
</style>

<h1>OpenTag3D &mdash; Polar Filament</h1>
<p class="sub">Look up a spool or build a tag by hand, then save an image or write a tag.</p>

<nav class="tabs">
  <button class="tab active" data-screen="main">Fetch &amp; write</button>
  <button class="tab" data-screen="edit">View &amp; edit</button>
</nav>

<section id="screen-edit" hidden>
  <fieldset>
    <legend>Load data</legend>
    <label for="eSerial">Spool serial</label>
    <input id="eSerial" placeholder="50017-FYG5" autocomplete="off">
    <div class="row">
      <div>
        <label for="eTagType">Tag type</label>
        <select id="eTagType">
          <option>NTAG213</option>
          <option selected>NTAG215</option>
          <option>NTAG216</option>
        </select>
      </div>
      <div>
        <label for="eSpec">Spec version</label>
        <select id="eSpec">
          <option value="2.001" selected>2.001</option>
          <option value="2.000">2.000</option>
          <option value="1.003">1.003</option>
        </select>
      </div>
      <div>
        <label for="eMode">Mode</label>
        <select id="eMode">
          <option value="">Default for tag type</option>
          <option value="Core">Core</option>
          <option value="Extended">Extended</option>
        </select>
      </div>
      <div>
        <label for="eReader">Reader (blank = first ACR122)</label>
        <input id="eReader" placeholder="ACR122" autocomplete="off">
      </div>
    </div>
    <div class="actions">
      <button class="primary" id="loadSerial">Load from serial</button>
      <button id="loadTag">Load from tag</button>
      <button id="loadNew">New tag</button>
    </div>
    <p class="note" id="editNote"></p>
  </fieldset>

  <fieldset>
    <legend>Vendor profiles</legend>
    <div class="prow">
      <div>
        <label for="eProfile">Saved profile</label>
        <select id="eProfile"><option value="">No profiles saved</option></select>
      </div>
      <button id="profileLoad" type="button">Load</button>
      <button id="profileDelete" type="button">Delete</button>
    </div>
    <div class="prow" style="margin-top:.6rem">
      <div>
        <label for="eProfileName">Save current values as</label>
        <input id="eProfileName" placeholder="acme-pla-matte" autocomplete="off">
      </div>
      <button id="profileSave" type="button">Save profile</button>
    </div>
    <p class="note">A profile stores the field values only &mdash; load one, then adjust the
      batch details before writing.</p>
  </fieldset>

  <form id="editForm" hidden autocomplete="off">
    <fieldset>
      <legend id="editLegend">Tag data</legend>
      <div id="editFields"></div>
      <label for="eOutputDir">Output folder (blank = __DEFAULTDIR__)</label>
      <input id="eOutputDir" placeholder="__DEFAULTDIR__" autocomplete="off">
      <div class="actions">
        <button class="primary" id="applySave" type="button">Save image</button>
        <button id="applyWrite" type="button">Write to tag</button>
        <button id="revert" type="button">Revert</button>
      </div>
    </fieldset>
  </form>
  <div id="confirm">
    <h3 id="confirmTitle"></h3>
    <div id="confirmBody"></div>
    <div class="actions">
      <button class="primary" id="confirmGo" type="button">Continue anyway</button>
      <button id="confirmCancel" type="button">Cancel</button>
    </div>
  </div>
  <div id="editOut"></div>
</section>

<section id="screen-main">

<fieldset>
  <legend>Spool</legend>
  <label for="serial">Serial</label>
  <input id="serial" placeholder="50017-FYG5" autofocus autocomplete="off">
  <div class="row">
    <div>
      <label for="tagType">Tag type</label>
      <select id="tagType">
        <option>NTAG213</option>
        <option selected>NTAG215</option>
        <option>NTAG216</option>
      </select>
    </div>
    <div>
      <label for="mode">Mode</label>
      <select id="mode">
        <option value="">Default for tag type</option>
        <option value="Core">Core</option>
        <option value="Extended">Extended</option>
      </select>
    </div>
    <div>
      <label for="format">Format</label>
      <select id="format">
        <option value="Ndef" selected>NDEF</option>
        <option value="Raw">Raw</option>
      </select>
    </div>
  </div>
  <label for="spec">Spec version</label>
  <select id="spec">
    <option value="" selected>As served by the lookup</option>
    <option value="1.003">1.003</option>
    <option value="2.000">2.000</option>
    <option value="2.001">2.001</option>
  </select>
  <p class="note" id="specNote"></p>
</fieldset>

<fieldset>
  <legend>Destination</legend>
  <label for="outputDir">Output folder (blank = __DEFAULTDIR__)</label>
  <input id="outputDir" placeholder="__DEFAULTDIR__" autocomplete="off">
  <label for="readerName">Reader name, for writing (blank = first ACR122)</label>
  <input id="readerName" placeholder="ACR122" autocomplete="off">
  <div class="actions">
    <button class="primary" id="save">Save image</button>
    <button id="write">Write tag</button>
    <button id="read">Read tag</button>
    <button id="stop">Stop server</button>
  </div>
  <p class="note" id="writeNote"></p>
</fieldset>

<div id="out"></div>
<div id="tag"></div>
</section>

<script>
  const CAN_WRITE = __CANWRITE__;
  const $ = id => document.getElementById(id);
  const out = $('out');

  if (!CAN_WRITE) {
    $('write').disabled = true;
    $('read').disabled  = true;
    $('writeNote').textContent = 'Tag reading and writing unavailable: __PCSCERROR__ Saving an image still works.';
  }

  function payload() {
    return {
      serial:     $('serial').value.trim(),
      tagType:    $('tagType').value,
      mode:       $('mode').value,
      format:     $('format').value,
      outputDir:  $('outputDir').value.trim(),
      readerName: $('readerName').value.trim(),
      specVersion: $('spec').value
    };
  }

  function show(ok, msg) {
    out.style.display = 'block';
    out.className = ok ? 'ok' : 'err';
    out.textContent = msg;
  }

  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g,
    c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

  function renderTag(data) {
    const t = $('tag');
    const fields = data.fields || [];

    // Headings come from the server, because they depend on the tag's spec version. Any
    // section not in that list is still shown, appended in the order it first appears -
    // a row must never be dropped just because the page did not expect its heading.
    const order = (data.groups || []).slice();
    for (const f of fields) if (!order.includes(f.section)) order.push(f.section);

    let html = '<h2>';
    if (data.color) html += '<span class="swatch" style="background:' + esc(data.color.split(' ')[0]) + '"></span>';
    html += esc(data.title || 'Tag contents');
    if (data.specVersion) html += ' <span class="ver">OpenTag3D ' + esc(data.specVersion) + '</span>';
    html += '</h2><table>';

    for (const sec of order) {
      const rows = fields.filter(f => f.section === sec);
      if (!rows.length) continue;
      html += '<tr><th colspan="2">' + esc(sec) + '</th></tr>';
      for (const f of rows) {
        html += '<tr><td class="k">' + esc(f.name) + '</td><td>' + esc(f.value) + '</td></tr>';
      }
    }
    html += '</table><p class="note">' + fields.length + ' field(s) read.</p>';
    t.innerHTML = html;
    t.style.display = 'block';
  }

  async function run(action, btn) {
    const buttons = [$('save'), $('write'), $('read')];
    buttons.forEach(b => b.disabled = true);
    show(true, 'Working...');
    try {
      const res = await fetch('/api/' + action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload())
      });
      const data = await res.json();
      if (action === 'read' && data.ok) {
        out.style.display = 'none';
        renderTag(data);
      } else {
        $('tag').style.display = 'none';
        show(data.ok, data.message);
      }
    } catch (e) {
      show(false, 'Request failed: ' + e.message);
    } finally {
      buttons.forEach(b => b.disabled = false);
      if (!CAN_WRITE) { $('write').disabled = true; $('read').disabled = true; }
    }
  }

  // Heartbeat: the server stops when this stops arriving, so closing the tab shuts it down.
  const beat = () => fetch('/api/ping', {
    method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
  }).catch(() => {});
  beat();
  setInterval(beat, 3000);

  // Fires on close AND on reload; the server waits a moment for a reloaded page to resume
  // the heartbeat before acting on it.
  addEventListener('pagehide', () => {
    navigator.sendBeacon('/api/bye', new Blob(['{}'], { type:'application/json' }));
  });

  $('save').onclick  = () => run('export');
  $('write').onclick = () => run('write');
  $('read').onclick  = () => run('read');
  $('serial').addEventListener('keydown', e => { if (e.key === 'Enter') run('export'); });

  // ---- spec version ----
  // OpenTag3D 2.x dropped NTAG213 (216 bytes of payload against 144 bytes of user memory),
  // so the chip is taken out of the list rather than left there to fail on write. It comes
  // back when 1.003 is selected. Mode is a 1.003 concept too - 2.x is one flat block.
  function applySpec(specSel, typeSel, modeSel, note) {
    const v = specSel.value;
    const v2 = v.charAt(0) === '2';

    const had = typeSel.value;
    if (v2) {
      const opt = [...typeSel.options].find(o => (o.value || o.textContent) === 'NTAG213');
      if (opt) opt.remove();
      if (had === 'NTAG213') typeSel.value = 'NTAG215';
    } else if (![...typeSel.options].some(o => (o.value || o.textContent) === 'NTAG213')) {
      const opt = document.createElement('option');
      opt.textContent = 'NTAG213';
      typeSel.insertBefore(opt, typeSel.firstChild);
    }

    if (modeSel) {
      modeSel.disabled = v2;
      modeSel.title = v2 ? 'OpenTag3D 2.x is one flat block - Core and Extended are 1.003 only'
                         : '';
    }
    if (note) {
      note.textContent = v2
        ? 'OpenTag3D ' + v + ': one 216-byte block, four extra fields (SKU, barcode, nozzle, chamber temp), NTAG215 or NTAG216 only.'
        : (v === '1.003' ? 'OpenTag3D 1.003: Core 112 bytes, Extended 187. Fits any NTAG21x.'
                         : 'Whatever the lookup service returns is written unchanged.');
    }
  }

  const eSpecSync = () => applySpec($('eSpec'), $('eTagType'), $('eMode'), null);
  const mSpecSync = () => applySpec($('spec'), $('tagType'), $('mode'), $('specNote'));
  $('eSpec').onchange = eSpecSync;
  $('spec').onchange  = mSpecSync;
  eSpecSync(); mSpecSync();

  // ---- tabs ----
  document.querySelectorAll('.tab').forEach(t => {
    t.onclick = () => {
      document.querySelectorAll('.tab').forEach(x => x.classList.toggle('active', x === t));
      $('screen-main').hidden = t.dataset.screen !== 'main';
      $('screen-edit').hidden = t.dataset.screen !== 'edit';
    };
  });

  // ---- edit screen ----
  let loaded = null;   // { fields, payloadHex }

  if (!CAN_WRITE) {
    $('loadTag').disabled = true;
    $('applyWrite').disabled = true;
    $('editNote').textContent = 'Tag access unavailable: __PCSCERROR__ Loading from a serial still works.';
  }

  function eshow(ok, msg) {
    const o = $('editOut');
    o.style.display = 'block';
    o.className = ok ? 'ok' : 'err';
    o.textContent = msg;
  }

  // A colour field is '#RRGGBB', optionally with ' (alpha N)'. The text box stays the
  // value of record - it is what gets collected and posted - and the picker writes into
  // it. An empty box means the colour is unused, which the spec stores as transparent
  // black, so the picker starts neutral and only fills the box once you choose something.
  function colourRow(row, inp, readonly) {
    const pick = document.createElement('input');
    pick.type = 'color';
    pick.tabIndex = readonly ? -1 : 0;
    pick.disabled = !!readonly;
    pick.title = 'Pick a colour';

    const clear = document.createElement('button');
    clear.type = 'button';
    clear.className = 'clr';
    clear.textContent = 'clear';
    clear.title = 'Leave this colour unused';
    clear.disabled = !!readonly;

    const hexOf = v => {
      const m = /#?([0-9A-Fa-f]{6})/.exec(v || '');
      return m ? '#' + m[1].toUpperCase() : null;
    };
    const alphaOf = v => {
      const m = /\(alpha\s*(\d+)\)/i.exec(v || '');
      return m ? ' (alpha ' + m[1] + ')' : '';
    };
    const sync = () => {
      const hex = hexOf(inp.value);
      pick.value = hex || '#000000';
      pick.classList.toggle('unset', !hex);
    };

    pick.addEventListener('input', () => {
      inp.value = pick.value.toUpperCase() + alphaOf(inp.value);
      pick.classList.remove('unset');
    });
    inp.addEventListener('input', sync);
    clear.addEventListener('click', () => { inp.value = ''; sync(); });

    sync();
    row.appendChild(pick);
    row.appendChild(clear);
  }

  function renderEditor(data) {
    loaded = data;
    // The payload decides the version, not the dropdown: loading a tag or a lookup can hand
    // back the other one, and the form must follow the bytes it is editing.
    if (data.specVersion && $('eSpec').value !== data.specVersion) {
      $('eSpec').value = data.specVersion;
      eSpecSync();
    }
    $('editLegend').textContent = (data.title || 'Tag data') +
                                  (data.specVersion ? '  \u00b7  OpenTag3D ' + data.specVersion : '');
    const host = $('editFields');
    host.innerHTML = '';
    let section = null;
    for (const f of data.fields) {
      if (f.section !== section) {
        section = f.section;
        const h = document.createElement('div');
        h.className = 'fgroup';
        h.textContent = section;
        host.appendChild(h);
      }
      const row = document.createElement('div');
      row.className = 'frow';
      const lab = document.createElement('label');
      lab.textContent = f.name + (f.unit ? ' (' + f.unit + ')' : '');
      lab.htmlFor = 'f_' + f.id;
      const inp = document.createElement('input');
      inp.id = 'f_' + f.id;
      inp.dataset.fid = f.id;
      inp.value = f.value;
      if (f.readonly) { inp.readOnly = true; inp.tabIndex = -1; }
      row.appendChild(lab);
      row.appendChild(inp);
      if (f.type === 'rgba') colourRow(row, inp, f.readonly);
      host.appendChild(row);
    }
    $('editForm').hidden = false;
    $('confirm').style.display = 'none';
    eshow(true, (data.note ? data.note + ' ' : '') + 'Loaded. Edit any field, then save or write.');
  }

  function collect() {
    const values = {};
    document.querySelectorAll('#editFields input[data-fid]').forEach(i => { values[i.dataset.fid] = i.value; });
    return values;
  }

  async function post(url, body) {
    const res = await fetch(url, {
      method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)
    });
    return res.json();
  }

  async function load(source) {
    const btns = [$('loadSerial'), $('loadTag'), $('loadNew'), $('profileLoad')];
    btns.forEach(b => b.disabled = true);
    eshow(true, 'Loading...');
    try {
      const data = await post('/api/load', {
        source, serial: $('eSerial').value.trim(),
        tagType: $('eTagType').value, mode: $('eMode').value,
        specVersion: $('eSpec').value,
        readerName: $('eReader').value.trim(),
        profileName: $('eProfile').value
      });
      if (data.ok) renderEditor(data); else { $('editForm').hidden = true; eshow(false, data.message); }
    } catch (e) { eshow(false, 'Request failed: ' + e.message); }
    finally {
      btns.forEach(b => b.disabled = false);
      if (!CAN_WRITE) $('loadTag').disabled = true;
    }
  }

  // ---- vendor profiles ----
  function fillProfiles(names, select) {
    const sel = $('eProfile');
    const keep = select || sel.value;
    sel.innerHTML = '';
    if (!names || !names.length) {
      sel.innerHTML = '<option value="">No profiles saved</option>';
      return;
    }
    for (const n of names) {
      const o = document.createElement('option');
      o.value = n; o.textContent = n;
      sel.appendChild(o);
    }
    if (keep && names.includes(keep)) sel.value = keep;
  }

  async function profile(op, extra) {
    const btns = [$('profileLoad'), $('profileSave'), $('profileDelete')];
    btns.forEach(b => b.disabled = true);
    try {
      const data = await post('/api/profile', Object.assign({ op }, extra || {}));
      if (data.profiles) fillProfiles(data.profiles, data.name);
      if (op !== 'list') eshow(data.ok, data.message);
      return data;
    } catch (e) {
      if (op !== 'list') eshow(false, 'Request failed: ' + e.message);
    } finally {
      btns.forEach(b => b.disabled = false);
    }
  }

  function askConfirm(data, onYes) {
    $('confirmTitle').textContent = data.message;
    $('confirmBody').innerHTML =
      '<ul>' + (data.keeping || []).map(f =>
        '<li>' + f.name + (f.value ? ': ' + f.value : '') + '</li>').join('') + '</ul>' +
      '<div style="font-size:.85rem;opacity:.75">' + (data.dropped || 0) +
      ' extended field(s) will be discarded. To keep everything, choose NTAG215 or NTAG216.</div>';
    $('confirm').style.display = 'block';
    $('editOut').style.display = 'none';
    $('confirmGo').onclick = () => { $('confirm').style.display = 'none'; onYes(); };
    $('confirmCancel').onclick = () => {
      $('confirm').style.display = 'none';
      eshow(true, 'Cancelled. Nothing was saved or written.');
    };
  }

  async function apply(target, confirmTruncate) {
    if (!loaded) return;
    const btns = [$('applySave'), $('applyWrite'), $('revert')];
    btns.forEach(b => b.disabled = true);
    $('confirm').style.display = 'none';
    eshow(true, target === 'tag' ? 'Writing...' : 'Saving...');
    try {
      const data = await post('/api/apply', {
        target, tagType: $('eTagType').value, payloadHex: loaded.payloadHex,
        values: collect(), outputDir: $('eOutputDir').value.trim(),
        readerName: $('eReader').value.trim(),
        generic: !!loaded.generic,
        confirmTruncate: !!confirmTruncate
      });
      if (data.confirm === 'truncate') {
        askConfirm(data, () => apply(target, true));
      } else {
        eshow(data.ok, data.message);
      }
    } catch (e) { eshow(false, 'Request failed: ' + e.message); }
    finally {
      btns.forEach(b => b.disabled = false);
      if (!CAN_WRITE) $('applyWrite').disabled = true;
    }
  }

  $('loadSerial').onclick = () => load('serial');
  $('loadTag').onclick    = () => load('tag');
  $('loadNew').onclick    = () => load('new');

  $('profileLoad').onclick = () => {
    if (!$('eProfile').value) { eshow(false, 'No profile selected.'); return; }
    load('profile');
  };
  $('profileSave').onclick = () => {
    const name = $('eProfileName').value.trim();
    if (!name)   { eshow(false, 'Name the profile first.'); return; }
    if (!loaded) { eshow(false, 'Load or start a tag before saving a profile.'); return; }
    profile('save', {
      name, values: collect(),
      tagType: $('eTagType').value, mode: $('eMode').value || loaded.mode,
      specVersion: loaded.specVersion || $('eSpec').value
    });
  };
  $('profileDelete').onclick = () => {
    const name = $('eProfile').value;
    if (!name) { eshow(false, 'No profile selected.'); return; }
    profile('delete', { name });
  };
  profile('list');
  $('applySave').onclick  = () => apply('file', false);
  $('applyWrite').onclick = () => apply('tag', false);
  $('revert').onclick     = () => { if (loaded) renderEditor(loaded); };
  $('eSerial').addEventListener('keydown', e => { if (e.key === 'Enter') load('serial'); });

  $('stop').onclick = async () => {
    await fetch('/api/stop', { method:'POST', headers:{'Content-Type':'application/json'}, body:'{}' }).catch(() => {});
    document.body.innerHTML = '<h1>Stopped</h1><p class="sub">You can close this tab.</p>';
  };
</script>
'@

    $reason = if ($PcscError) { $PcscError } else { 'No PC/SC reader detected.' }
    $page.Replace('__CANWRITE__', $CanWrite.ToString().ToLowerInvariant()).
          Replace('__DEFAULTDIR__', [Net.WebUtility]::HtmlEncode($DefaultDir)).
          Replace('__PCSCERROR__', [Net.WebUtility]::HtmlEncode($reason))
}
