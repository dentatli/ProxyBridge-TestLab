[CmdletBinding()]
param(
    [switch]$ConfirmRemoval,
    [string]$DataRoot = (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'ProxyBridge-TestLab')
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmRemoval) { throw 'CONFIRM_REMOVAL_REQUIRED' }
& (Join-Path $PSScriptRoot 'Stop-ProxyBridge-TestLab.ps1') | Out-Null
$target = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\')
$root = [System.IO.Path]::GetPathRoot($target).TrimEnd('\')
$profile = [System.IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($target) -or $target -eq $root -or $target -eq $profile -or [System.IO.Path]::GetFileName($target) -ne 'ProxyBridge-TestLab') { throw 'DATA_ROOT_REFUSED' }
if (Test-Path -LiteralPath $target) {
    if ((Get-Item -LiteralPath $target).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'DATA_ROOT_REPARSE_POINT_REFUSED' }
    Remove-Item -LiteralPath $target -Recurse -Force
    "REMOVED=$target"
} else { 'REMOVED=0' }
