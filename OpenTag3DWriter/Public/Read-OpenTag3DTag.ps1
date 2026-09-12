function Read-OpenTag3DTag {
<#
.SYNOPSIS
    Reads an OpenTag3D tag, or a saved tag image, and decodes the spool data.

.DESCRIPTION
    Reads the application/opentag3d NDEF record and decodes it per the OpenTag3D spec
    (https://opentag3d.info/spec.html): core fields at 0x00-0x6F and, where present,
    extended fields at 0x70-0xBA.

    Reads through PC/SC: winscard on Windows, pcsc-lite on Linux and macOS. Reading a .bin
    image with -Path needs no reader at all.

.PARAMETER Path
    Decode a saved tag image instead of reading a physical tag.

.PARAMETER ReaderName
    Substring of the PC/SC reader name. Defaults to the first reader matching 'ACR122'.

.PARAMETER Raw
    Also return the decoded payload bytes on a PayloadBytes property.

.EXAMPLE
    Read-OpenTag3DTag

    Reads the tag on the reader and returns the decoded fields.

.EXAMPLE
    Read-OpenTag3DTag | Format-List material, color_name, serial, print_temp

    Picks individual fields off the returned object.

.EXAMPLE
    Read-OpenTag3DTag -Path .\50017-FYG5-NTAG215-Extended-Ndef.bin | Select-Object -ExpandProperty Fields | Format-Table

    Decodes a saved image and shows every populated field as a table. Works on Linux too.
#>
    [CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'Tag')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Path')]
        [Alias('FullName','PSPath')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ParameterSetName = 'Tag')]
        [string]$ReaderName,

        [switch]$Raw
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $file = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Image not found: $file" }
            $bytes = [IO.File]::ReadAllBytes($file)
            Write-Verbose "Decoding $($bytes.Length)-byte image $file"
            $payload = Get-OpenTag3DNdefPayload -UserMemory $bytes
        }
        else {
            $session = Connect-PcscCard -ReaderName $ReaderName
            try {
                Write-Verbose "Reader: $($session.Reader)"
                $actual = Get-NtagType -Session $session
                Write-Verbose "Detected $($actual.TagType) via $($actual.Method)"

                # Read the TLV header first so we only pull as much as the message needs.
                $head = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xB0,0x00,0x04,0x10)) -ReceiveLength 32
                if (-not $head.Success) { throw "Could not read page 4 (SW=$($head.SW))." }
                if ($head.Data[0] -ne 0x03) {
                    throw ("No NDEF TLV at page 4 (found 0x{0:X2}). This tag is not NDEF formatted." -f $head.Data[0])
                }
                $need = if ($head.Data[1] -eq 0xFF) { 4 + (([int]$head.Data[2] -shl 8) -bor $head.Data[3]) }
                        else { 2 + $head.Data[1] }
                $need = [Math]::Min($need + 1, $actual.UserSize)     # +1 for the terminator TLV
                Write-Verbose "NDEF message needs $need bytes of user memory"

                $mem = [byte[]]::new($need)
                for ($off = 0; $off -lt $need; $off += 16) {
                    $page  = 4 + ($off / 4)
                    $count = [Math]::Min(16, $need - $off)
                    $r = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xB0,0x00,[byte]$page,0x10)) -ReceiveLength 32
                    if (-not $r.Success) { throw "Read failed at page $page (SW=$($r.SW))." }
                    [Array]::Copy($r.Data, 0, $mem, $off, $count)
                }
                $payload = Get-OpenTag3DNdefPayload -UserMemory $mem
            }
            finally { Disconnect-PcscCard -Session $session }
        }

        $result = ConvertFrom-OpenTag3DPayload -Payload $payload
        if ($Raw) { $result | Add-Member -NotePropertyName PayloadBytes -NotePropertyValue $payload }
        $result
    }
}
