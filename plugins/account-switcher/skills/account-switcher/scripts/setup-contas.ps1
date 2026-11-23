# Compatibility shim: the script is now setup-accounts.ps1 (the English names came with plugin 1.2.0).
& (Join-Path $PSScriptRoot 'setup-accounts.ps1') @args
