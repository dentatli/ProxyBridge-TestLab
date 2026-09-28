[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$expected = [System.IO.Path]::GetFullPath((Join-Path $packageRoot 'app\ProxyBridge.TestLab.Ui.exe'))
$stopped = 0
foreach ($process in @(Get-Process -Name 'ProxyBridge.TestLab.Ui' -ErrorAction SilentlyContinue)) {
    $actual = ''
    try { $actual = [System.IO.Path]::GetFullPath([string]$process.MainModule.FileName) } catch { continue }
    if (-not [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    $process.CloseMainWindow() | Out-Null
    if (-not $process.WaitForExit(3000)) { Stop-Process -Id $process.Id; if (-not $process.WaitForExit(7000)) { throw 'TESTLAB_STOP_TIMEOUT' } }
    $stopped++
}
"STOPPED=$stopped"
