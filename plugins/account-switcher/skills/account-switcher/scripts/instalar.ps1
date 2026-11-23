# Compatibility shim: the script is now install.ps1 (the English names came with plugin 1.2.0).
# -Verificar is now -Check. An install made by an older version is migrated by install.ps1.
param([switch]$Verificar)
& (Join-Path $PSScriptRoot 'install.ps1') -Check:$Verificar
