#Requires -Version 7.0

# Dot-source every function file, export only the public ones.
$public  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1"  -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)

foreach ($file in @($public + $private)) {
    try   { . $file.FullName }
    catch { throw "Failed to import function $($file.FullName): $_" }
}

Export-ModuleMember -Function $public.BaseName
