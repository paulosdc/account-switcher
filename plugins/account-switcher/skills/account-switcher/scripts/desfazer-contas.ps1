# Compatibility shim: the script is now uninstall.ps1 (the English names came with plugin 1.2.0).
# -ApagarPastas is now -DeleteFolders.
param([switch]$ApagarPastas)
& (Join-Path $PSScriptRoot 'uninstall.ps1') -DeleteFolders:$ApagarPastas
