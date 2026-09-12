# Saved vendor profiles: named sets of field values for filament you tag repeatedly.
#
# Stored as one JSON file per profile, so they can be edited by hand, copied between
# machines and kept in version control.

# Names come from the browser, so they are validated rather than trusted: no separators,
# no dots leading anywhere, nothing that could escape the profile directory.
$script:OpenTag3DProfileNamePattern = '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$'

function Get-OpenTag3DProfileDir {
    <#
    .SYNOPSIS
        Folder holding saved vendor profiles, created on first use.
    .DESCRIPTION
        Windows: %APPDATA%\OpenTag3D\Profiles. Linux and macOS: $XDG_CONFIG_HOME/opentag3d/
        profiles, defaulting to ~/.config when that is not set.
    #>
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        $root = $env:APPDATA
        if ([string]::IsNullOrWhiteSpace($root)) { $root = [Environment]::GetFolderPath('ApplicationData') }
        $dir = Join-Path (Join-Path $root 'OpenTag3D') 'Profiles'
    }
    else {
        $root = $env:XDG_CONFIG_HOME
        if ([string]::IsNullOrWhiteSpace($root)) { $root = Join-Path $HOME '.config' }
        $dir = Join-Path (Join-Path $root 'opentag3d') 'profiles'
    }

    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
        Write-Verbose "Created profile directory $dir"
    }
    return $dir
}

function Test-OpenTag3DProfileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Name)

    if ($Name -notmatch $script:OpenTag3DProfileNamePattern) {
        throw "Profile name '$Name' is not usable. Use letters, digits, spaces, dots, dashes or underscores, up to 64 characters."
    }
    return $Name
}

function Get-OpenTag3DProfileList {
    <#
    .SYNOPSIS
        Names of every saved profile, alphabetically.
    #>
    [CmdletBinding()]
    param()

    Get-ChildItem -LiteralPath (Get-OpenTag3DProfileDir) -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) }
}

function Get-OpenTag3DProfile {
    <#
    .SYNOPSIS
        Reads one saved profile.
    .DESCRIPTION
        Returns the tag type, mode and a value table keyed by spec field id. Keys that are
        not spec fields are dropped, so an edited or older file cannot inject anything the
        encoder does not understand.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Name)

    $null = Test-OpenTag3DProfileName -Name $Name
    $path = Join-Path (Get-OpenTag3DProfileDir) "$Name.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "No profile named '$Name'." }

    try { $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Profile '$Name' is not readable JSON: $($_.Exception.Message)" }

    # Accept ids from any version: a 1.003 profile loaded into a 2.000 form should keep the
    # fields the two share, and the encoder ignores anything the target layout lacks.
    $known  = @($script:OpenTag3DSpecVersions | ForEach-Object {
                    (Get-OpenTag3DFieldTable -SpecVersion $_) | ForEach-Object { $_.Id } } | Sort-Object -Unique)
    $values = @{}
    if ($json.values) {
        foreach ($p in $json.values.PSObject.Properties) {
            if ($p.Name -in $known) { $values[$p.Name] = "$($p.Value)" }
        }
    }

    [pscustomobject]@{
        Name        = $Name
        TagType     = if ($json.tagType -in 'NTAG213','NTAG215','NTAG216') { "$($json.tagType)" } else { 'NTAG215' }
        Mode        = if ($json.mode -in 'Core','Extended') { "$($json.mode)" } else { 'Extended' }
        # Profiles written before this field existed are 1.003 by construction - their values
        # were entered under 1.003 semantics (tolerance in micrometres, and so on), so this
        # must not follow the module default.
        SpecVersion = if ("$($json.specVersion)" -in $script:OpenTag3DSpecVersions) { "$($json.specVersion)" }
                      else { '1.003' }
        Values      = $values
        Path        = $path
    }
}

function Save-OpenTag3DProfile {
    <#
    .SYNOPSIS
        Writes a profile, replacing any file of the same name.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Values,
        [Parameter()] [ValidateSet('NTAG213','NTAG215','NTAG216')] [string]$TagType = 'NTAG215',
        [Parameter()] [ValidateSet('Core','Extended')] [string]$Mode = 'Extended',
        [Parameter()] [string]$SpecVersion
    )

    $spec = Get-OpenTag3DSpec -SpecVersion $SpecVersion

    $null = Test-OpenTag3DProfileName -Name $Name
    $path = Join-Path (Get-OpenTag3DProfileDir) "$Name.json"

    # Store spec fields only, and only ones with something in them: a profile is a set of
    # defaults to start from, not a full payload.
    $keep = [ordered]@{}
    foreach ($f in $spec.Fields) {
        if ($f.Id -in $script:OpenTag3DGenericReadOnly) { continue }
        if (-not $Values.ContainsKey($f.Id)) { continue }
        $v = "$($Values[$f.Id])".Trim()
        if ($v) { $keep[$f.Id] = $v }
    }

    $doc = [ordered]@{
        name        = $Name
        tagType     = $TagType
        mode        = $Mode
        specVersion = $spec.Version
        savedUtc    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        values      = $keep
    }

    if ($PSCmdlet.ShouldProcess($path, 'Save profile')) {
        $json = $doc | ConvertTo-Json -Depth 4
        # UTF8 without a BOM: this is data, read by ConvertFrom-Json and by people.
        [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
        Write-Verbose "Saved profile to $path"
    }
    return $path
}

function Remove-OpenTag3DProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string]$Name)

    $null = Test-OpenTag3DProfileName -Name $Name
    $path = Join-Path (Get-OpenTag3DProfileDir) "$Name.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "No profile named '$Name'." }
    if ($PSCmdlet.ShouldProcess($path, 'Delete profile')) {
        Remove-Item -LiteralPath $path -Force
    }
}
