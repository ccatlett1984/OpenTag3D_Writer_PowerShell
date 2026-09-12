function Write-OpenTag3DTag {
<#
.SYNOPSIS
    Writes an NTAG21x memory image to a tag using an ACR122U (or any PC/SC reader).

.DESCRIPTION
    Takes a 180-byte (NTAG213), 540-byte (NTAG215) or 924-byte (NTAG216) image produced by
    Export-OpenTag3DPayload
    and writes its user memory to a physical tag, four bytes at a time, using the PC/SC
    UPDATE BINARY APDU (FF D6 00 <page> 04 <data>).

    Before writing, the chip on the reader is identified with GET_VERSION and checked against
    the image, so a mismatched image is rejected before any bytes are committed.

    Only user memory (page 4 onward) is written. Pages 0-2 hold the factory UID, which is
    read-only and is neither checked nor written - any blank tag of the right type will do. Page 3 is the one-time-programmable capability container and is written only
    when -FormatCC is specified and the tag's CC is still blank. The dynamic lock and
    configuration pages at the end of memory are never written.

.PARAMETER Path
    Path to the .bin image.

.PARAMETER Bytes
    A 540- or 924-byte image already in memory, instead of a file on disk.

.PARAMETER ReaderName
    Substring of the PC/SC reader name. Defaults to the first reader matching 'ACR122'.

.PARAMETER Force
    Write even when the spool already holds a different OpenTag3D spec version. Without it a
    mismatch is refused and nothing is written, tag and image versions both named.

.PARAMETER SkipBlankPages
    Do not write pages whose image bytes are all zero. Faster on blank tags, but leaves stale
    data behind when rewriting a tag that already holds a longer payload.

.EXAMPLE
    Write-OpenTag3DTag -Path .\50017-FYG5-NTAG215-Extended-Ndef.bin

    Writes the image to whichever tag is on the first ACR122 reader. The chip type is confirmed
    against the image first, so a 215 image on a 213 aborts before anything is committed.

.EXAMPLE
    Write-OpenTag3DTag -Path .\tag.bin -WhatIf

    Connects, reads the UID and identifies the chip, then reports what would be written without
    committing anything - including the one-time-programmable capability container on page 3.

.EXAMPLE
    Get-ChildItem D:\tags\*.bin | ForEach-Object {
        Read-Host "Place tag for $($_.Name), then press Enter"
        $_ | Write-OpenTag3DTag
    }

    Walks a folder of images, pausing for a tag swap between each. -Path binds from the
    FullName property, so FileInfo objects pipe straight in.

.EXAMPLE
    Write-OpenTag3DTag -Path .\tag.bin -ReaderName 'ACR122U PICC' -SkipBlankPages -Verbose

    Targets a specific reader by name substring and skips all-zero pages, which is noticeably
    faster on a factory-blank tag. Verification still covers every page, so a tag holding
    stale data from a longer payload fails rather than being left half-updated.
#>
    [CmdletBinding(PositionalBinding = $false, SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Path')]
        [Alias('FullName','PSPath')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Bytes')]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes,

        [Parameter()]
        [string]$ReaderName,

        [switch]$SkipBlankPages,

        [switch]$Force
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $file = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Image not found: $file" }
            $image = [IO.File]::ReadAllBytes($file)
        }
        else {
            $image = $Bytes
        }
        $spec = switch ($image.Length) {
            180 { @{ TagType = 'NTAG213'; UserPages = 36  } }
            540 { @{ TagType = 'NTAG215'; UserPages = 126 } }
            924 { @{ TagType = 'NTAG216'; UserPages = 222 } }
            default { throw "Image is $($image.Length) bytes; expected 180 (NTAG213), 540 (NTAG215) or 924 (NTAG216)." }
        }
        Write-Verbose "$($spec.TagType) image, $($spec.UserPages) user pages"

        $session = Connect-PcscCard -ReaderName $ReaderName
        try {
            Write-Verbose "Reader: $($session.Reader)"

            # --- identify the tag (FF CA 00 00 00) ---
            $r = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xCA,0x00,0x00,0x00))
            if (-not $r.Success) { throw "Could not read tag UID (SW=$($r.SW))." }
            $tagHex = ($r.Data | ForEach-Object { $_.ToString('X2') }) -join ':'
            Write-Verbose "Tag UID $tagHex"

            # --- confirm the chip matches the image before committing anything ---
            $actual = Get-NtagType -Session $session
            Write-Verbose "Detected $($actual.TagType) via $($actual.Method)"
            if ($actual.TagType -ne $spec.TagType) {
                throw "Tag on the reader is an $($actual.TagType) ($($actual.UserSize) bytes user memory) but this image is for an $($spec.TagType). Rebuild with -TagType $($actual.TagType)."
            }

            # --- refuse to change the spec version of a tag already carrying data ---
            # Writing 2.001 over a 1.003 spool silently changes what every other reader will
            # make of it, so the versions have to agree unless -Force says otherwise. A blank
            # or non-OpenTag3D tag has nothing to disagree with and writes normally.
            $imageVersion = $null
            try {
                $imagePayload = Get-OpenTag3DNdefPayload -UserMemory $image
                $imageVersion = Get-OpenTag3DPayloadVersion -Payload $imagePayload
            }
            catch { Write-Verbose "Image is not an NDEF OpenTag3D record; no version check." }

            if ($imageVersion) {
                # Read in 48-byte steps until the opentag3d record's payload is in view. One
                # step covers the TLV, record header and 21-byte type; more is needed when
                # another record - a URI for a product page, say - comes first.
                $head  = [byte[]]@()
                $start = $null
                for ($chunk = 0; $chunk -lt 3; $chunk++) {
                    $page = 4 + ($chunk * 12)
                    $r    = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xB0,0x00,[byte]$page,0x30)) -ReceiveLength 64
                    if (-not $r.Success) { Write-Verbose "Could not read page $page for a version check (SW=$($r.SW))."; break }
                    $head  = $head + $r.Data
                    $start = Get-OpenTag3DPayloadStart -UserMemory $head
                    if ($null -ne $start -and $start + 2 -le $head.Length) { break }
                }

                if ($head.Length) {
                    if ($null -ne $start -and $start + 2 -le $head.Length) {
                        $onTag = Get-OpenTag3DPayloadVersion -Payload $head[$start..($start + 1)]
                        $rawOnTag = ([int]$head[$start] -shl 8) -bor $head[$start + 1]
                        $shown = if ($onTag) { $onTag } else { '{0}.{1:D3}' -f [math]::Floor($rawOnTag / 1000), ($rawOnTag % 1000) }

                        if ($shown -ne $imageVersion) {
                            if ($Force) {
                                Write-Warning "Spool tag holds OpenTag3D $shown; writing $imageVersion over it because -Force was given."
                            }
                            else {
                                throw "Spec version mismatch: this image is OpenTag3D $imageVersion, the spool on the reader holds OpenTag3D $shown. Nothing was written. Rebuild the image as $shown, or pass -Force to overwrite the tag with $imageVersion."
                            }
                        }
                        else { Write-Verbose "Spool and image agree on OpenTag3D $shown" }
                    }
                    else { Write-Verbose "Tag holds no readable OpenTag3D record; no version to compare." }
                }
            }

            # --- capability container (page 3), always written ---
            # Page 3 is OTP: WRITE ORs into the existing value, so rewriting the same CC is a
            # no-op. Read back afterwards to confirm the tag holds what the image expects.
            $want    = $image[12..15]
            $wantHex = ($want | ForEach-Object { $_.ToString('X2') }) -join ' '
            if ($PSCmdlet.ShouldProcess($session.Reader, "Write capability container $wantHex to page 3")) {
                $w = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xD6,0x00,0x03,0x04) + $want)
                if (-not $w.Success) { throw "Failed writing CC to page 3 (SW=$($w.SW))." }

                $r = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xB0,0x00,0x03,0x04)) -ReceiveLength 16
                if (-not $r.Success) { throw "Could not read back capability container (SW=$($r.SW))." }
                $now = ($r.Data[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
                if ($now -ne $wantHex) {
                    throw "CC verification failed: page 3 reads $now, expected $wantHex. Page 3 is one-time programmable, so this tag was previously formatted for a different type."
                }
                Write-Verbose "CC $wantHex confirmed"
            }

            # --- write user memory ---
            if (-not $PSCmdlet.ShouldProcess($session.Reader, "Write $($spec.UserPages) pages to $($spec.TagType) tag $tagHex")) { return }

            $written = 0
            $skipped = 0
            for ($p = 0; $p -lt $spec.UserPages; $p++) {
                $page   = 4 + $p
                $offset = 16 + ($p * 4)
                $chunk  = $image[$offset..($offset + 3)]

                if ($SkipBlankPages -and ($chunk | Where-Object { $_ -ne 0 }).Count -eq 0) {
                    $skipped++
                    continue
                }

                $apdu = [byte[]]@(0xFF,0xD6,0x00,[byte]$page,0x04) + $chunk
                $w = Invoke-PcscApdu -Session $session -Apdu $apdu
                if (-not $w.Success) {
                    throw "Write failed at page $page (0x{0:X2}), SW={1}. Tag may be partially written." -f $page, $w.SW
                }
                $written++

                if (($p % 16) -eq 0) {
                    Write-Progress -Activity "Writing $($spec.TagType)" -Status "Page $page" -PercentComplete (100 * $p / $spec.UserPages)
                }
            }
            Write-Progress -Activity "Writing $($spec.TagType)" -Completed
            Write-Verbose "Wrote $written pages, skipped $skipped"

            # --- verify (always) ---
            $bad = 0
            for ($p = 0; $p -lt $spec.UserPages; $p += 4) {
                $page   = 4 + $p
                $count  = [Math]::Min(4, $spec.UserPages - $p)
                $offset = 16 + ($p * 4)
                $r = Invoke-PcscApdu -Session $session -Apdu ([byte[]]@(0xFF,0xB0,0x00,[byte]$page,[byte]($count*4))) -ReceiveLength 32
                if (-not $r.Success) { throw "Verify read failed at page $page (SW=$($r.SW))." }
                for ($b = 0; $b -lt ($count*4); $b++) {
                    if ($r.Data[$b] -ne $image[$offset + $b]) {
                        Write-Warning ("Mismatch at page {0} byte {1}: tag {2:X2}, image {3:X2}" -f ($page + [Math]::Floor($b/4)), ($b % 4), $r.Data[$b], $image[$offset + $b])
                        $bad++
                    }
                }
            }
            if ($bad -gt 0) { throw "Verification failed: $bad byte(s) differ." }
            Write-Verbose "Verified $($spec.UserPages) pages"

            Write-Host "Wrote and verified $written pages to $($spec.TagType) $tagHex"
        }
        finally { Disconnect-PcscCard -Session $session }
    }
}
