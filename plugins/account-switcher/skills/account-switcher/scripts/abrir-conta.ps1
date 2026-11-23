# Compatibility shim: the script is now open-account.ps1 (the English names came with plugin 1.2.0).
# Other tools still call abrir-conta.ps1 <conta> [pasta] [-Rc | -NoRc]; this forwards to the new script.
param([Parameter(Mandatory)][string]$Conta, [string]$Pasta, [switch]$Rc, [switch]$NoRc)
$forward = @{ Account = $Conta; Rc = $Rc; NoRc = $NoRc }
if ($PSBoundParameters.ContainsKey('Pasta')) { $forward.Folder = $Pasta }
& (Join-Path $PSScriptRoot 'open-account.ps1') @forward
