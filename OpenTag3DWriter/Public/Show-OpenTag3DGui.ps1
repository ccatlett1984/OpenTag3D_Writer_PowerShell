function Show-OpenTag3DGui {
<#
.SYNOPSIS
    Starts a local browser UI for looking up spools, saving tag images and writing tags.

.DESCRIPTION
    Serves a small single-page UI on localhost and opens it in the default browser. The page
    posts back to Export-OpenTag3DPayload, so it can save a .bin image or write straight to a
    tag on a PC/SC reader.

    Uses System.Net.HttpListener, so the UI runs on Windows, Linux and macOS. The tag buttons
    are enabled when a PC/SC reader is reachable at startup; if none is, the page says why.

    The listener binds to localhost only. It stops when the page is closed, when you press the
    Stop button, or with Ctrl+C. The page sends a heartbeat every few seconds; once the first
    one arrives, the server shuts down if the heartbeat stops for -IdleTimeout seconds. A page
    reload is not a close: the new page resumes the heartbeat within the grace period.

.PARAMETER Port
    TCP port to listen on. Defaults to 8787. When left at the default, the next 20 ports are
    tried if that one is taken; naming a port explicitly disables the search so a failure is
    reported rather than silently moving.

.PARAMETER NoBrowser
    Do not launch a browser; just print the URL.

.PARAMETER IdleTimeout
    Seconds without a heartbeat before the server stops. Defaults to 15. The timer only arms
    after the first heartbeat, so -NoBrowser sessions are not killed before a page connects.

.PARAMETER KeepAlive
    Never stop automatically; run until Ctrl+C or the Stop button.

.EXAMPLE
    Show-OpenTag3DGui

    Starts the UI on http://localhost:8787/ and opens it in the default browser.

.EXAMPLE
    Show-OpenTag3DGui -Port 9000 -NoBrowser

    Starts on a different port and prints the URL instead of launching a browser. Useful over
    SSH with a forwarded port.
#>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter()]
        [ValidateRange(1024, 65535)]
        [int]$Port = 8787,

        [Parameter()]
        [switch]$NoBrowser,

        [Parameter()]
        [ValidateRange(5, 3600)]
        [int]$IdleTimeout = 15,

        [Parameter()]
        [switch]$KeepAlive
    )

    # Tag access needs a PC/SC service, not a particular OS: winscard on Windows, pcsc-lite
    # elsewhere. Probe for a reader rather than assuming from the platform.
    $canWrite = $true
    try { $null = Get-PcscReader }
    catch {
        $canWrite = $false
        $pcscError = $_.Exception.Message
        Write-Verbose "PC/SC unavailable: $pcscError"
    }

    $html = Get-OpenTag3DGuiHtml -CanWrite $canWrite -DefaultDir (Get-OpenTag3DDefaultOutputDir) -PcscError $pcscError

    # HTTP.sys on Windows rejects a prefix already reserved by another registration, and some
    # ports sit inside Hyper-V/WSL reserved ranges. Try both loopback spellings, and walk up
    # the port range unless the caller pinned a specific port.
    $bindHosts = @('localhost','127.0.0.1')
    $ports     = if ($PSBoundParameters.ContainsKey('Port')) { @($Port) } else { $Port..($Port + 20) }

    $listener = $null
    $lastErr  = $null
    foreach ($p in $ports) {
        foreach ($bindHost in $bindHosts) {
            $candidate = [System.Net.HttpListener]::new()
            $candidate.Prefixes.Add("http://${bindHost}:$p/")
            try {
                $candidate.Start()
                $listener = $candidate
                $Port     = $p
                $useHost  = $bindHost
                break
            }
            catch {
                $lastErr = $_.Exception.Message
                $candidate.Close()
            }
        }
        if ($listener) { break }
    }

    if (-not $listener) {
        $hint = if ($PSBoundParameters.ContainsKey('Port')) {
                    "Try a different port, e.g. Show-OpenTag3DGui -Port $($Port + 113)."
                } else {
                    "Ports $Port-$($Port + 20) are all unavailable. Pick one explicitly with -Port."
                }
        throw @"
Could not start the UI listener. $hint

Last error: $lastErr

On Windows this usually means one of:
  * another copy of this UI is still running - close it, or check: netstat -ano | findstr $Port
  * a URL reservation owned by another account - check: netsh http show urlacl | findstr $Port
  * the port falls in a Hyper-V/WSL reserved range - check:
      netsh interface ipv4 show excludedportrange protocol=tcp
"@
    }

    $url = "http://${useHost}:$Port/"
    Write-Host "OpenTag3D UI listening on $url  (Ctrl+C to stop)"
    if (-not $canWrite) {
        Write-Host "No PC/SC reader available, so tag read/write is disabled: $pcscError"
        Write-Host "Image export and decoding still work."
    }

    if (-not $NoBrowser) {
        try {
            if ($IsMacOS)      { Start-Process 'open' $url }
            elseif ($IsLinux)  { Start-Process 'xdg-open' $url }
            else               { Start-Process $url }
        }
        catch { Write-Verbose "Could not launch a browser: $($_.Exception.Message)" }
    }

    $stop     = $false
    $reason   = 'Stop requested'
    $lastPing = $null      # set by the first heartbeat; until then the idle timer is unarmed
    $byeAt    = $null      # set by the page's unload beacon; a reload clears it again

    try {
        while ($listener.IsListening -and -not $stop) {
            # Poll rather than block, so Ctrl+C and the idle timer are honoured between requests.
            $task = $listener.GetContextAsync()
            while (-not $task.AsyncWaitHandle.WaitOne(200)) {
                if (-not $listener.IsListening) { return }
                if ($KeepAlive -or -not $lastPing) { continue }

                # A reload fires the unload beacon too, so wait a moment for the new page to
                # resume its heartbeat before treating the beacon as a real close.
                if ($byeAt -and ((Get-Date) - $byeAt).TotalSeconds -ge 3) {
                    $stop = $true; $reason = 'Page closed'; break
                }
                if (((Get-Date) - $lastPing).TotalSeconds -ge $IdleTimeout) {
                    $stop = $true; $reason = "No heartbeat for $IdleTimeout seconds"; break
                }
            }
            if ($stop) { break }
            $ctx = $task.GetAwaiter().GetResult()

            $req  = $ctx.Request
            $path = $req.Url.AbsolutePath
            Write-Verbose "$($req.HttpMethod) $path"

            switch -Regex ("$($req.HttpMethod) $path") {

                '^GET /$' {
                    Write-HttpResponse -Context $ctx -ContentType 'text/html; charset=utf-8' -Body $html
                    break
                }

                '^POST /api/(export|write|read|load|apply|profile)$' {
                    $action = $Matches[1]
                    $body   = [IO.StreamReader]::new($req.InputStream, $req.ContentEncoding).ReadToEnd()
                    $result = Invoke-OpenTag3DGuiAction -Action $action -Body $body -CanWrite $canWrite
                    Write-HttpResponse -Context $ctx -ContentType 'application/json; charset=utf-8' -Body ($result | ConvertTo-Json -Compress -Depth 6)
                    break
                }

                '^POST /api/ping$' {
                    $lastPing = Get-Date
                    $byeAt    = $null
                    Write-HttpResponse -Context $ctx -ContentType 'application/json; charset=utf-8' -Body '{"ok":true}'
                    break
                }

                '^POST /api/bye$' {
                    $byeAt = Get-Date
                    Write-HttpResponse -Context $ctx -ContentType 'application/json; charset=utf-8' -Body '{"ok":true}'
                    break
                }

                '^POST /api/stop$' {
                    # Answer first, then leave the loop; stopping mid-request truncates the reply.
                    Write-HttpResponse -Context $ctx -ContentType 'application/json; charset=utf-8' -Body '{"ok":true}'
                    $stop   = $true
                    $reason = 'Stopped from the page'
                    break
                }

                default {
                    $ctx.Response.StatusCode = 404
                    Write-HttpResponse -Context $ctx -ContentType 'text/plain' -Body 'Not found'
                }
            }
        }
    }
    finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
        Write-Host "UI stopped. ($reason)"
    }
}
