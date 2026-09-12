function Get-OpenTag3DDefaultOutputDir {
    <#
    .SYNOPSIS
        Resolves the default folder for saved tag images.
    .DESCRIPTION
        Windows: the user's Downloads folder. Reads the Shell Folders registry value rather than
        assuming %USERPROFILE%\Downloads, because Downloads is commonly redirected to OneDrive or
        another drive.

        Linux and macOS: the user's home directory.

        Falls back to the current location if the resolved path does not exist.
    #>
    [CmdletBinding()]
    param()

    $candidate = $null

    if ($IsWindows) {
        try {
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
            $guid = '{374DE290-123F-4565-9164-39C4925E467B}'   # FOLDERID_Downloads
            $candidate = (Get-ItemProperty -Path $key -Name $guid -ErrorAction Stop).$guid
        }
        catch {
            Write-Verbose "Downloads not found in the registry; falling back to the profile path."
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = Join-Path $env:USERPROFILE 'Downloads'
        }
    }
    else {
        $candidate = $env:HOME
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = [Environment]::GetFolderPath('UserProfile')
        }
    }

    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
        return $candidate
    }

    Write-Verbose "Default output folder '$candidate' not usable; using the current location."
    return (Get-Location -PSProvider FileSystem).ProviderPath
}
