# OpenTag3D data structures, per the published specs.
#
#   1.003  https://opentag3d.info/spec.json - the released version, and the one the Polar
#          lookup service serves. Core 0x00-0x6F, Extended 0x70-0xBA.
#   2.000  Released on or before 2026-09-03. One flat block, most fields relocated, four new
#          fields, and NTAG213 dropped (216 bytes cannot fit 144 bytes of user memory).
#   2.001  https://opentag3d.info/spec.json - current. Identical to 2.000 but for mfi_value,
#          which stops being divided by 10 and is read as plain g/min. Same 40 fields, same
#          addresses, same 216 bytes - the stored byte does not change, only what it means.
#
# 1.003 and the 2.x layouts share only tag_version, material and material_mod addresses, so
# they are separate tables rather than one table with edits. A payload always carries its own
# version at 0x00, which is what selects the table when decoding.
#
# All integers unsigned big-endian; strings UTF-8 unless the field says ASCII.

# Oldest first: Get-OpenTag3DPayloadVersion walks these in order when a payload declares a
# version with no exact table.
$script:OpenTag3DSpecVersions       = @('1.003','2.000','2.001')

# What a new tag is built as when nothing says otherwise. 2.001 since 1.8.0: it is the
# published spec. 1.003 and 2.000 stay fully supported - reading picks the table from the
# payload, so tags already written are unaffected.
$script:OpenTag3DDefaultSpecVersion = '2.001'

# Fields the editor shows but never lets you change. The serial identifies the spool and is
# what the lookup keys on; the tag version describes the format, not the filament.
$script:OpenTag3DReadOnly = @('tag_version','serial')

# Unit strings are built from char codes rather than written literally: Windows PowerShell 5.1
# reads BOM-less .ps1 files using the ANSI codepage, which turns a literal UTF-8 degree sign
# into 'A-circumflex degree'. Escapes keep this file pure ASCII and render correctly anywhere.
$script:Deg  = "$([char]0x00B0)C"        # degrees Celsius
$script:Um   = "$([char]0x00B5)m"        # micrometres
$script:Cm3  = "g/cm$([char]0x00B3)"     # grams per cubic centimetre
$script:Mm3s = "mm$([char]0x00B3)/s"     # cubic millimetres per second

# --- 1.003 -------------------------------------------------------------------------------
$script:OpenTag3DFieldsV1 = @(
    # --- Core: 0x00 - 0x6F ---
    @{ Id='tag_version';         Name='Tag Version';          Start=0x00; Length=2; Type='version' }
    @{ Id='material';            Name='Material';             Start=0x02; Length=5; Type='utf8' }
    @{ Id='material_mod';        Name='Material Modifiers';   Start=0x07; Length=5; Type='utf8' }
    @{ Id='manufacturer';        Name='Manufacturer';         Start=0x1B; Length=16; Type='utf8' }
    @{ Id='color_name';          Name='Color Name';           Start=0x2B; Length=32; Type='utf8' }
    @{ Id='color_1';             Name='Color 1';              Start=0x4B; Length=4; Type='rgba' }
    @{ Id='color_2';             Name='Color 2';              Start=0x50; Length=4; Type='rgba' }
    @{ Id='color_3';             Name='Color 3';              Start=0x54; Length=4; Type='rgba' }
    @{ Id='color_4';             Name='Color 4';              Start=0x58; Length=4; Type='rgba' }
    @{ Id='diameter';            Name='Target Diameter';      Start=0x5C; Length=2; Type='int'; Scale=0.001; Unit='mm' }
    @{ Id='weight';              Name='Target Weight';        Start=0x5E; Length=2; Type='int'; Unit='g' }
    @{ Id='print_temp';          Name='Print Temperature';    Start=0x60; Length=1; Type='int'; Scale=5; Unit=$script:Deg }
    @{ Id='bed_temp';            Name='Bed Temperature';      Start=0x61; Length=1; Type='int'; Scale=5; Unit=$script:Deg }
    @{ Id='density';             Name='Density';              Start=0x62; Length=2; Type='int'; Scale=0.001; Unit=$script:Cm3 }
    @{ Id='td';                  Name='Transmission Distance'; Start=0x64; Length=2; Type='int'; Scale=0.1; Unit='mm' }

    # --- Extended: 0x70 - 0xBA ---
    @{ Id='data_url';            Name='Online Data URL';      Start=0x70; Length=32; Type='ascii'; Ext=$true }
    @{ Id='serial';              Name='Serial / Batch ID';    Start=0x90; Length=16; Type='utf8'; Ext=$true }
    @{ Id='mfg_date';            Name='Manufacture Date';     Start=0xA0; Length=4; Type='date'; Ext=$true }
    @{ Id='mfg_time';            Name='Manufacture Time';     Start=0xA4; Length=3; Type='time'; Ext=$true }
    @{ Id='spool_core_diameter'; Name='Spool Core Diameter';  Start=0xA7; Length=1; Type='int'; Unit='mm'; Ext=$true }
    @{ Id='mfi_temp';            Name='MFI Temp';             Start=0xA8; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Ext=$true }
    @{ Id='mfi_load';            Name='MFI Load';             Start=0xA9; Length=1; Type='int'; Scale=10; Unit='g'; Ext=$true }
    @{ Id='mfi_value';           Name='MFI Value';            Start=0xAA; Length=1; Type='int'; Scale=10; Unit='g/10min'; Ext=$true }
    @{ Id='tolerance';           Name='Measured Tolerance';   Start=0xAB; Length=1; Type='int'; Unit=$script:Um; Ext=$true }
    @{ Id='empty_spool_weight';  Name='Empty Spool Weight';   Start=0xAC; Length=2; Type='int'; Unit='g'; Ext=$true }
    @{ Id='measured_weight';     Name='Measured Weight';      Start=0xAE; Length=2; Type='int'; Unit='g'; Ext=$true }
    @{ Id='measured_length';     Name='Measured Length';      Start=0xB0; Length=2; Type='int'; Unit='m'; Ext=$true }
    @{ Id='max_dry_temp';        Name='Max Dry Temp';         Start=0xB2; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Ext=$true }
    @{ Id='dry_time';            Name='Dry Time';             Start=0xB3; Length=1; Type='int'; Unit='hr'; Ext=$true }
    @{ Id='min_print_temp';      Name='Min Print Temp';       Start=0xB4; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Ext=$true }
    @{ Id='max_print_temp';      Name='Max Print Temp';       Start=0xB5; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Ext=$true }
    @{ Id='min_bed_temp';        Name='Min Bed Temp';         Start=0xB6; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Ext=$true }
    @{ Id='max_bed_temp';        Name='Max Bed Temp';         Start=0xB7; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Ext=$true }
    @{ Id='min_vso';             Name='Min Volumetric Speed'; Start=0xB8; Length=1; Type='int'; Unit=$script:Mm3s; Ext=$true }
    @{ Id='max_vso';             Name='Max Volumetric Speed'; Start=0xB9; Length=1; Type='int'; Unit=$script:Mm3s; Ext=$true }
    @{ Id='target_vso';          Name='Target Volumetric Speed'; Start=0xBA; Length=1; Type='int'; Unit=$script:Mm3s; Ext=$true }
)

# --- 2.000 (alpha) -----------------------------------------------------------------------
#
# Verified 2026-09-03 against both sources, which agree with each other:
#   * https://opentag3d.info/spec.json - all 40 fields match on address, length, type,
#     scaling and required flag.
#   * https://pfil.us/opentag3d.php?id=50017-FYG5 - the 40 addresses it reports for a real
#     spool are identical, and every value it shows re-encodes to the same bytes from this
#     table (barcode 749565056953 -> 00AE858F17B9, tolerance 0.02mm -> 02, mfi_load 2160g
#     -> D8, and so on).
#
# The spec declares the block 0x00-0xDF, but nothing is defined past data_url's last byte at
# 0xD7, so a payload is 216 bytes. Undocumented gaps: 0x82-0x83, 0x8B, 0xAB-0xB7, 0xD8-0xDF.
#
# One block, 0x00-0xDF. Group is the spec's own "usage" attribute, which replaces the
# Core/Extended split as the way the editor groups fields.
$script:OpenTag3DFieldsV2 = @(
    @{ Id='tag_version';         Name='Tag Version';          Start=0x00; Length=2; Type='version'; Group='Operational'; Required=$true }
    @{ Id='material';            Name='Material';             Start=0x02; Length=5; Type='utf8'; Group='Display'; Required=$true }
    @{ Id='material_mod';        Name='Material Modifiers';   Start=0x07; Length=5; Type='utf8'; Group='Display' }
    @{ Id='manufacturer';        Name='Manufacturer';         Start=0x0C; Length=16; Type='utf8'; Group='Display'; Required=$true }
    @{ Id='color_name';          Name='Color Name';           Start=0x1C; Length=32; Type='utf8'; Group='Display' }
    @{ Id='color_1';             Name='Color 1';              Start=0x3C; Length=4; Type='rgba'; Group='Display'; Required=$true }
    @{ Id='color_2';             Name='Color 2';              Start=0x40; Length=4; Type='rgba'; Group='Display' }
    @{ Id='color_3';             Name='Color 3';              Start=0x44; Length=4; Type='rgba'; Group='Display' }
    @{ Id='color_4';             Name='Color 4';              Start=0x48; Length=4; Type='rgba'; Group='Display' }
    @{ Id='serial';              Name='Serial / Batch ID';    Start=0x4C; Length=32; Type='utf8'; Group='Inventory' }
    @{ Id='sku';                 Name='SKU';                  Start=0x6C; Length=16; Type='utf8'; Group='Inventory'; Added='2.000' }
    @{ Id='barcode';             Name='Barcode';              Start=0x7C; Length=6; Type='int'; Group='Inventory'; Added='2.000' }
    @{ Id='mfg_date';            Name='Manufacture Date';     Start=0x84; Length=4; Type='date'; Group='Inventory' }
    @{ Id='mfg_time';            Name='Manufacture Time';     Start=0x88; Length=3; Type='time'; Group='Inventory' }
    @{ Id='diameter';            Name='Filament Diameter';    Start=0x8C; Length=2; Type='int'; Scale=0.001; Unit='mm'; Group='Operational'; Required=$true }
    @{ Id='tolerance';           Name='Measured Tolerance';   Start=0x8E; Length=1; Type='int'; Scale=0.01; Unit='mm'; Group='Operational' }
    @{ Id='nozzle_diameter';     Name='Min Nozzle Diameter';  Start=0x8F; Length=1; Type='int'; Scale=0.1; Unit='mm'; Group='Operational'; Added='2.000' }
    @{ Id='print_temp';          Name='Print Temperature';    Start=0x90; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational'; Required=$true }
    @{ Id='min_print_temp';      Name='Min Print Temp';       Start=0x91; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational' }
    @{ Id='max_print_temp';      Name='Max Print Temp';       Start=0x92; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational' }
    @{ Id='chamber_temp';        Name='Chamber Temperature';  Start=0x93; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational'; Required=$true; Added='2.000' }
    @{ Id='bed_temp';            Name='Bed Temperature';      Start=0x94; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational'; Required=$true }
    @{ Id='min_bed_temp';        Name='Min Bed Temp';         Start=0x95; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational' }
    @{ Id='max_bed_temp';        Name='Max Bed Temp';         Start=0x96; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational' }
    @{ Id='target_vso';          Name='Target Volumetric Speed'; Start=0x97; Length=1; Type='int'; Unit=$script:Mm3s; Group='Operational' }
    @{ Id='min_vso';             Name='Min Volumetric Speed'; Start=0x98; Length=1; Type='int'; Unit=$script:Mm3s; Group='Operational' }
    @{ Id='max_vso';             Name='Max Volumetric Speed'; Start=0x99; Length=1; Type='int'; Unit=$script:Mm3s; Group='Operational' }
    @{ Id='max_dry_temp';        Name='Max Dry Temp';         Start=0x9A; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational' }
    @{ Id='dry_time';            Name='Dry Time';             Start=0x9B; Length=1; Type='int'; Unit='hr'; Group='Operational' }
    @{ Id='density';             Name='Density';              Start=0x9C; Length=2; Type='int'; Scale=0.001; Unit=$script:Cm3; Group='Operational'; Required=$true }
    @{ Id='weight';              Name='Target Weight';        Start=0x9E; Length=2; Type='int'; Unit='g'; Group='Operational'; Required=$true }
    @{ Id='empty_spool_weight';  Name='Empty Spool Weight';   Start=0xA0; Length=2; Type='int'; Unit='g'; Group='Operational' }
    @{ Id='measured_length';     Name='Measured Length';      Start=0xA2; Length=2; Type='int'; Unit='m'; Group='Operational' }
    @{ Id='measured_weight';     Name='Measured Weight';      Start=0xA4; Length=2; Type='int'; Unit='g'; Group='Operational' }
    @{ Id='spool_core_diameter'; Name='Spool Core Diameter';  Start=0xA6; Length=1; Type='int'; Unit='mm'; Group='Operational' }
    @{ Id='td';                  Name='Transmission Distance'; Start=0xA7; Length=1; Type='int'; Scale=0.1; Unit='mm'; Group='Operational' }
    @{ Id='mfi_temp';            Name='MFI Temp';             Start=0xA8; Length=1; Type='int'; Scale=5; Unit=$script:Deg; Group='Operational' }
    @{ Id='mfi_load';            Name='MFI Load';             Start=0xA9; Length=1; Type='int'; Scale=10; Unit='g'; Group='Operational' }
    @{ Id='mfi_value';           Name='MFI Value';            Start=0xAA; Length=1; Type='int'; Scale=10; Unit='g/10min'; Group='Operational' }
    @{ Id='data_url';            Name='Online Data URL';      Start=0xB8; Length=32; Type='ascii'; Group='Operational' }
)

# --- 2.001 -------------------------------------------------------------------------------
# One correction to 2.000, verified against opentag3d.info/spec.json on 2026-09-11:
# mfi_value loses its scaling of 10 and its unit becomes g/min rather than g/10min. The byte
# is unchanged - 2.000 read a raw 63 as "630 g/10min" and 2.001 reads it as "63 g/min", which
# is the same rate written sensibly. Everything else - all 40 ids, addresses, lengths, types,
# scalings and required flags - is identical, so the table is derived from 2.000 rather than
# copied. Unchanged fields are shared by reference; nothing mutates a field definition.
$script:OpenTag3DFieldsV2001 = @(
    foreach ($f in $script:OpenTag3DFieldsV2) {
        if ($f.Id -ne 'mfi_value') { $f; continue }
        $c = @{}
        foreach ($k in $f.Keys) { $c[$k] = $f[$k] }
        $c.Remove('Scale')
        $c.Unit = 'g/min'
        $c
    }
)

$script:OpenTag3DSpecs = [ordered]@{
    '1.003' = @{
        Version    = '1.003'
        Raw        = 1003
        Major      = 1
        Alpha      = $false
        Fields     = $script:OpenTag3DFieldsV1
        HasModes   = $true          # Core / Extended
        CoreSize   = 0x70           # 112
        FullSize   = 0xBB           # 187
        GroupOrder = @('Core','Extended')
        Source     = 'https://opentag3d.info/spec.json'
    }
    '2.000' = @{
        Version    = '2.000'
        Raw        = 2000
        Major      = 2
        Alpha      = $false
        Fields     = $script:OpenTag3DFieldsV2
        HasModes   = $false         # one flat block, no Core/Extended split
        # The spec declares the block as 0x00-0xDF (224), but nothing is defined past
        # data_url's last byte at 0xD7. 216 is therefore the payload every field fits in,
        # and it is also what pfil.us emits.
        CoreSize   = 0xD8           # 216
        FullSize   = 0xD8           # 216
        GroupOrder = @('Display','Inventory','Operational')
        Source     = 'opentag3d.info/spec.json, as published up to 2026-09-04'
    }
    '2.001' = @{
        Version    = '2.001'
        Raw        = 2001
        Major      = 2
        Alpha      = $false
        Fields     = $script:OpenTag3DFieldsV2001
        HasModes   = $false
        CoreSize   = 0xD8           # 216
        FullSize   = 0xD8           # 216
        GroupOrder = @('Display','Inventory','Operational')
        Source     = 'https://opentag3d.info/spec.json'
    }
}

function Get-OpenTag3DSpec {
    <#
    .SYNOPSIS
        The layout description for one spec version.
    .PARAMETER SpecVersion
        '1.003' or '2.000'. Defaults to 2.000.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$SpecVersion)

    if (-not $SpecVersion) { $SpecVersion = $script:OpenTag3DDefaultSpecVersion }
    if (-not $script:OpenTag3DSpecs.Contains($SpecVersion)) {
        throw "Unknown OpenTag3D spec version '$SpecVersion'. Known: $($script:OpenTag3DSpecVersions -join ', ')."
    }
    return $script:OpenTag3DSpecs[$SpecVersion]
}

function Get-OpenTag3DFieldTable {
    <#
    .SYNOPSIS
        The field table for one spec version, in address order.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$SpecVersion)

    (Get-OpenTag3DSpec -SpecVersion $SpecVersion).Fields
}

function Get-OpenTag3DFieldSection {
    <#
    .SYNOPSIS
        The group heading a field belongs under, for the version it came from.
    .DESCRIPTION
        1.003 splits Core from Extended, which is an address range and matters when
        truncating for an NTAG213. 2.000 has no such split, so it groups by the spec's own
        'usage' attribute instead.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Field)

    if ($Field.Group) { return $Field.Group }
    if ($Field.Ext)   { return 'Extended' }
    return 'Core'
}

function Get-OpenTag3DPayloadVersion {
    <#
    .SYNOPSIS
        The spec version a payload declares at 0x00, as a version string.
    .DESCRIPTION
        tag_version sits at 0x00 in every version of the spec, which is what makes a payload
        self-describing. Returns $null if the payload is too short or the version is not one
        this module has a table for.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]]$Payload)

    if ($Payload.Length -lt 2) { return $null }
    $raw   = ([int]$Payload[0] -shl 8) -bor $Payload[1]
    $major = [math]::Floor($raw / 1000)

    # An exact table always wins.
    foreach ($v in $script:OpenTag3DSpecVersions) {
        if ($script:OpenTag3DSpecs[$v].Raw -eq $raw) { return $v }
    }

    # Otherwise the closest table below it in the same major - a 2.002 tag is read with the
    # 2.001 table, not the 2.000 one, since minor releases are corrections on what came
    # before. ConvertFrom-OpenTag3DPayload warns when it does this.
    $sameMajor = @($script:OpenTag3DSpecVersions | Where-Object { $script:OpenTag3DSpecs[$_].Major -eq $major })
    if (-not $sameMajor) { return $null }

    $below = @($sameMajor | Where-Object { $script:OpenTag3DSpecs[$_].Raw -le $raw })
    if ($below) { return $below[-1] }

    # Older than every table in its major: the earliest is the best guess.
    return $sameMajor[0]
}

function Get-OpenTag3DNdefPayload {
    <#
    .SYNOPSIS
        Extracts the application/opentag3d payload from tag user memory.
    .PARAMETER UserMemory
        Bytes starting at page 4 (the NDEF TLV), or a full 180/540/924-byte tag image.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]]$UserMemory)

    # Accept a full dump as well as a user-memory slice.
    if ($UserMemory.Length -in 180,540,924) {
        $UserMemory = $UserMemory[16..($UserMemory.Length - 21)]
    }

    if ($UserMemory.Length -lt 4) { throw "Not enough data to contain an NDEF message." }
    if ($UserMemory[0] -ne 0x03) {
        throw ("No NDEF TLV at page 4 (found 0x{0:X2}). The tag may be unformatted, or hold raw data rather than NDEF." -f $UserMemory[0])
    }

    # TLV length: one byte, or 0xFF followed by two bytes.
    if ($UserMemory[1] -eq 0xFF) {
        $msgLen = ([int]$UserMemory[2] -shl 8) -bor $UserMemory[3]
        $i = 4
    }
    else {
        $msgLen = $UserMemory[1]
        $i = 2
    }
    if ($i + $msgLen -gt $UserMemory.Length) { throw "NDEF message length ($msgLen) runs past the end of user memory." }

    # NDEF record: flags, type length, payload length, type, payload.
    $flags   = $UserMemory[$i]
    $tnf     = $flags -band 0x07
    $short   = ($flags -band 0x10) -ne 0
    $typeLen = $UserMemory[$i + 1]
    $j = $i + 2

    if ($short) { $payLen = $UserMemory[$j]; $j += 1 }
    else {
        $payLen = ([int]$UserMemory[$j] -shl 24) -bor ([int]$UserMemory[$j+1] -shl 16) -bor ([int]$UserMemory[$j+2] -shl 8) -bor $UserMemory[$j+3]
        $j += 4
    }
    if (($flags -band 0x08) -ne 0) { $j += 1 }   # ID length present

    $type = [Text.Encoding]::ASCII.GetString($UserMemory[$j..($j + $typeLen - 1)])
    $j += $typeLen

    if ($tnf -ne 0x02 -or $type -ne 'application/opentag3d') {
        throw "Tag holds an NDEF record of type '$type', not application/opentag3d."
    }
    if ($j + $payLen -gt $UserMemory.Length) { throw "Record payload runs past the end of user memory." }

    return ,[byte[]]$UserMemory[$j..($j + $payLen - 1)]
}

function ConvertFrom-OpenTag3DPayload {
    <#
    .SYNOPSIS
        Decodes an OpenTag3D payload into an object.
    .DESCRIPTION
        A payload carries its own version at 0x00, so the field table is chosen from the data
        rather than from the caller. -SpecVersion overrides that for a payload whose version
        bytes are missing or wrong.
    .PARAMETER SpecVersion
        Force a layout instead of trusting the payload's own version bytes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [byte[]]$Payload,
        [Parameter()] [string]$SpecVersion
    )

    $declared = if ($Payload.Length -ge 2) { ([int]$Payload[0] -shl 8) -bor $Payload[1] } else { 0 }

    if (-not $SpecVersion) {
        $SpecVersion = Get-OpenTag3DPayloadVersion -Payload $Payload
        if (-not $SpecVersion) {
            throw ("Payload declares OpenTag3D version {0}.{1:D3}; this module has field tables for {2} only." -f
                    [math]::Floor($declared / 1000), ($declared % 1000), ($script:OpenTag3DSpecVersions -join ' and '))
        }
    }
    $spec = Get-OpenTag3DSpec -SpecVersion $SpecVersion

    # Spec reader guidance: a newer minor version of a layout we know is parsed anyway.
    if ($declared -gt $spec.Raw -and [math]::Floor($declared / 1000) -eq $spec.Major) {
        Write-Warning ("Payload is OpenTag3D {0}.{1:D3}, newer than the {2} this module targets. Parsing anyway." -f
                        [math]::Floor($declared / 1000), ($declared % 1000), $spec.Version)
    }

    $get = {
        param($start, $len)
        if ($start + $len -gt $Payload.Length) { return $null }
        return $Payload[$start..($start + $len - 1)]
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $obj  = [ordered]@{}

    foreach ($f in $spec.Fields) {
        $bytes = & $get $f.Start $f.Length
        if ($null -eq $bytes) { continue }

        $value   = $null
        $display = $null

        switch ($f.Type) {
            'version' {
                $raw = ([int]$bytes[0] -shl 8) -bor $bytes[1]
                $value = '{0}.{1:D3}' -f [math]::Floor($raw / 1000), ($raw % 1000)
                $display = $value
            }
            { $_ -in 'utf8','ascii' } {
                $enc = if ($f.Type -eq 'ascii') { [Text.Encoding]::ASCII } else { [Text.Encoding]::UTF8 }
                $s = $enc.GetString($bytes)
                $nul = $s.IndexOf([char]0)
                if ($nul -ge 0) { $s = $s.Substring(0, $nul) }
                $value = $s.Trim()
                if ([string]::IsNullOrEmpty($value)) { $value = $null }
                $display = $value
            }
            'rgba' {
                if (($bytes | Where-Object { $_ -ne 0 }).Count -eq 0) { $value = $null }   # transparent = unused
                else {
                    $value = '#{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]
                    if ($bytes[3] -ne 255) { $value = "$value (alpha $($bytes[3]))" }
                }
                $display = $value
            }
            'date' {
                $y = ([int]$bytes[0] -shl 8) -bor $bytes[1]
                if ($y -ge 1990 -and $y -le 2200 -and $bytes[2] -ge 1 -and $bytes[2] -le 12 -and $bytes[3] -ge 1 -and $bytes[3] -le 31) {
                    $value   = '{0:D4}-{1:D2}-{2:D2}' -f $y, $bytes[2], $bytes[3]
                    $display = $value
                }
            }
            'time' {
                if ($bytes[0] -le 23 -and $bytes[1] -le 59 -and $bytes[2] -le 59) {
                    $value   = '{0:D2}:{1:D2}:{2:D2}' -f $bytes[0], $bytes[1], $bytes[2]
                    $display = "$value UTC"
                }
            }
            'int' {
                # 64-bit: 2.000's barcode is 6 bytes, which overflows Int32.
                $raw = [long]0
                foreach ($b in $bytes) { $raw = ($raw -shl 8) -bor $b }
                $value = if ($f.Scale) { [math]::Round($raw * $f.Scale, 3) } else { $raw }
                $display = if ($f.Unit) { "$value $($f.Unit)" } else { "$value" }
            }
        }

        $obj[$f.Id] = $value
        if ($null -ne $value) {
            $rows.Add([pscustomobject]@{
                Name    = $f.Name
                Id      = $f.Id
                Value   = $display
                Section = Get-OpenTag3DFieldSection -Field $f
            })
        }
    }

    $result = [pscustomobject]$obj
    $result | Add-Member -NotePropertyName Fields      -NotePropertyValue $rows.ToArray()
    $result | Add-Member -NotePropertyName PayloadSize -NotePropertyValue $Payload.Length
    $result | Add-Member -NotePropertyName SpecVersion -NotePropertyValue $spec.Version
    return $result
}

function ConvertTo-OpenTag3DPayload {
    <#
    .SYNOPSIS
        Writes edited field values back into an OpenTag3D payload.
    .DESCRIPTION
        Starts from the original payload and overwrites only the fields supplied, so reserved
        bytes and anything this parser does not model are preserved untouched.

        Values are given as a hashtable keyed by field id, in the same display form the parser
        produces: '1.75 mm', '215 C', '#14ADDB', '2026-04-03', '10:19:33'.

        The layout comes from the base payload's own version bytes unless -SpecVersion says
        otherwise - encoding 2.000 values into a 1.003 base would write them at the wrong
        addresses, so the two must agree.
    .PARAMETER TruncateTo
        Optional payload length. Use 112 (0x70) to cut a 1.003 Extended payload down to Core.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [byte[]]$BasePayload,
        [Parameter(Mandatory)] [hashtable]$Values,
        [Parameter()] [string]$SpecVersion,
        [int]$TruncateTo
    )

    if (-not $SpecVersion) {
        $SpecVersion = Get-OpenTag3DPayloadVersion -Payload $BasePayload
        if (-not $SpecVersion) { $SpecVersion = $script:OpenTag3DDefaultSpecVersion }
    }
    $spec = Get-OpenTag3DSpec -SpecVersion $SpecVersion

    $out = [byte[]]::new($BasePayload.Length)
    [Array]::Copy($BasePayload, $out, $BasePayload.Length)

    foreach ($f in $spec.Fields) {
        if (-not $Values.ContainsKey($f.Id)) { continue }
        if ($f.Start + $f.Length -gt $out.Length) { continue }

        $v = "$($Values[$f.Id])".Trim()
        $bytes = [byte[]]::new($f.Length)   # zero filled; strings are null padded

        switch ($f.Type) {
            'version' {
                # Accept '1.003' or a bare 1003
                $n = if ($v -match '^(\d+)\.(\d+)$') { [int]$Matches[1] * 1000 + [int]$Matches[2] }
                     elseif ($v -match '^\d+$') { [int]$v } else { $null }
                if ($null -eq $n) { throw "Field '$($f.Name)': '$v' is not a version." }
                $bytes[0] = [byte](([int]$n -shr 8) -band 0xFF)
                $bytes[1] = [byte]($n -band 0xFF)
            }
            { $_ -in 'utf8','ascii' } {
                $enc = if ($f.Type -eq 'ascii') { [Text.Encoding]::ASCII } else { [Text.Encoding]::UTF8 }
                $raw = $enc.GetBytes($v)
                if ($raw.Length -gt $f.Length) {
                    Write-Warning "Field '$($f.Name)' truncated to $($f.Length) bytes."
                    $raw = $raw[0..($f.Length - 1)]
                }
                [Array]::Copy($raw, $bytes, $raw.Length)
            }
            'rgba' {
                if ([string]::IsNullOrWhiteSpace($v)) { }   # leave transparent black
                else {
                    $m = [regex]::Match($v, '#?([0-9A-Fa-f]{6})(?:\s*\(alpha\s*(\d+)\))?')
                    if (-not $m.Success) { throw "Field '$($f.Name)': '$v' is not a #RRGGBB colour." }
                    $hex = $m.Groups[1].Value
                    $bytes[0] = [Convert]::ToByte($hex.Substring(0,2),16)
                    $bytes[1] = [Convert]::ToByte($hex.Substring(2,2),16)
                    $bytes[2] = [Convert]::ToByte($hex.Substring(4,2),16)
                    $bytes[3] = if ($m.Groups[2].Success) { [byte][int]$m.Groups[2].Value } else { 255 }
                }
            }
            'date' {
                if ($v -match '^(\d{4})-(\d{2})-(\d{2})$') {
                    $y = [int]$Matches[1]
                    $bytes[0] = [byte](([int]$y -shr 8) -band 0xFF)
                    $bytes[1] = [byte]($y -band 0xFF)
                    $bytes[2] = [byte][int]$Matches[2]
                    $bytes[3] = [byte][int]$Matches[3]
                }
                elseif ($v) { throw "Field '$($f.Name)': expected YYYY-MM-DD, got '$v'." }
            }
            'time' {
                if ($v -match '^(\d{1,2}):(\d{2}):(\d{2})') {
                    $bytes[0] = [byte][int]$Matches[1]
                    $bytes[1] = [byte][int]$Matches[2]
                    $bytes[2] = [byte][int]$Matches[3]
                }
                elseif ($v) { throw "Field '$($f.Name)': expected HH:MM:SS, got '$v'." }
            }
            'int' {
                # Take the leading number only: units may contain digits (e.g. 'g/10min').
                # 64-bit throughout - 2.000's 6-byte barcode does not fit an Int32.
                $m = [regex]::Match($v, '^\s*(-?\d+(?:\.\d+)?)')
                $n = if ($m.Success) { [double]$m.Groups[1].Value } else { 0 }
                if ($f.Scale) { $n = $n / $f.Scale }
                $n = [long][math]::Round($n)
                $max = [long]([math]::Pow(256, $f.Length) - 1)
                if ($n -lt 0 -or $n -gt $max) {
                    throw "Field '$($f.Name)': $v is out of range for $($f.Length) byte(s)."
                }
                for ($i = $f.Length - 1; $i -ge 0; $i--) {
                    $bytes[$i] = [byte]($n -band 0xFF)
                    $n = $n -shr 8
                }
            }
        }
        [Array]::Copy($bytes, 0, $out, $f.Start, $f.Length)
    }

    if ($TruncateTo -and $TruncateTo -lt $out.Length) { $out = $out[0..($TruncateTo - 1)] }
    return ,[byte[]]$out
}

function Get-OpenTag3DMissingRequiredField {
    <#
    .SYNOPSIS
        Names of required fields a value table leaves empty.
    .DESCRIPTION
        1.003 has no notion of required fields; 2.000 marks ten. Callers warn rather than
        refuse - an incomplete tag is still a tag, and the spec is alpha.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Values,
        [Parameter()] [string]$SpecVersion
    )

    foreach ($f in (Get-OpenTag3DFieldTable -SpecVersion $SpecVersion)) {
        if (-not $f.Required) { continue }
        if ($f.Id -eq 'tag_version') { continue }        # the module always stamps this
        $v = if ($Values.ContainsKey($f.Id)) { "$($Values[$f.Id])".Trim() } else { '' }
        if (-not $v) { $f.Name }
    }
}

# Unit changes between versions. Two so far: 'tolerance' is micrometres in 1.003 and
# hundredths of a millimetre in 2.x, and 'mfi_value' is g/10min in 2.000 and g/min in 2.001.
# Anything else that differs is refused rather than guessed at.
$script:OpenTag3DUnitFactor = @{
    "$($script:Um)|mm" = 0.001
    "mm|$($script:Um)" = 1000
    # 2.000 -> 2.001 relabelled mfi_value: 630 g/10min and 63 g/min are the same rate, and
    # encode to the same byte, so this keeps the value rather than changing it.
    'g/10min|g/min'    = 0.1
    'g/min|g/10min'    = 10
}

function Convert-OpenTag3DPayload {
    <#
    .SYNOPSIS
        Re-encodes a payload from one spec version into another.
    .DESCRIPTION
        Matches fields by id, not address - the two layouts share almost no addresses. Values
        carry across in their real-world units, so a field whose unit changed between versions
        is converted rather than copied.

        Fields the target version does not have, and values that no longer fit the target's
        field width, are dropped with a warning. Nothing is guessed: a unit change this
        function does not know about is reported and the field left empty.
    .PARAMETER ToSpecVersion
        The version to produce.
    .PARAMETER FromSpecVersion
        Override the version detected from the payload's own bytes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [byte[]]$Payload,
        [Parameter(Mandatory)] [string]$ToSpecVersion,
        [Parameter()] [string]$FromSpecVersion
    )

    if (-not $FromSpecVersion) {
        $FromSpecVersion = Get-OpenTag3DPayloadVersion -Payload $Payload
        if (-not $FromSpecVersion) { throw "Cannot tell which OpenTag3D version this payload uses." }
    }

    $from = Get-OpenTag3DSpec -SpecVersion $FromSpecVersion
    $to   = Get-OpenTag3DSpec -SpecVersion $ToSpecVersion

    if ($from.Version -eq $to.Version) { return ,[byte[]]$Payload }

    $decoded = ConvertFrom-OpenTag3DPayload -Payload $Payload -SpecVersion $from.Version
    $toById  = @{}
    foreach ($f in $to.Fields) { $toById[$f.Id] = $f }

    $values  = @{}
    $dropped = [System.Collections.Generic.List[string]]::new()

    foreach ($src in $from.Fields) {
        if ($src.Id -eq 'tag_version') { continue }       # stamped by the blank payload

        $value = $decoded.($src.Id)
        if ($null -eq $value -or "$value" -eq '') { continue }

        $dst = $toById[$src.Id]
        if (-not $dst) { $dropped.Add("$($src.Name) (not in $($to.Version))"); continue }

        if ($src.Type -ne 'int') { $values[$src.Id] = "$value"; continue }

        # Numeric: carry the real-world value across, converting the unit if it changed.
        $n = [double]$value
        $su = if ($src.Unit) { "$($src.Unit)" } else { '' }
        $du = if ($dst.Unit) { "$($dst.Unit)" } else { '' }
        if ($su -ne $du) {
            $factor = $script:OpenTag3DUnitFactor["$su|$du"]
            if (-not $factor) {
                $dropped.Add("$($src.Name) (unit $su -> $du not convertible)")
                continue
            }
            $n = $n * $factor
        }

        # Does it still fit? 1.003's td is two bytes, 2.000's is one.
        $rawTarget = if ($dst.Scale) { [math]::Round($n / $dst.Scale) } else { [math]::Round($n) }
        $max       = [math]::Pow(256, $dst.Length) - 1
        if ($rawTarget -lt 0 -or $rawTarget -gt $max) {
            $dropped.Add("$($src.Name) ($value $su exceeds the $($dst.Length)-byte field in $($to.Version))")
            continue
        }

        $values[$src.Id] = "$n"
    }

    if ($dropped.Count) {
        Write-Warning ("Converting $($from.Version) -> $($to.Version) dropped: " + ($dropped -join '; '))
    }

    $base = [byte[]]::new($to.FullSize)
    $base[0] = [byte](([int]$to.Raw -shr 8) -band 0xFF)
    $base[1] = [byte]($to.Raw -band 0xFF)

    return ,[byte[]](ConvertTo-OpenTag3DPayload -BasePayload $base -Values $values -SpecVersion $to.Version)
}
