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
    $base='http://127.0.0.1:5178/api/v1/lab/'
    $identity=Invoke-RestMethod ($base+'application') -TimeoutSec 3
    if($identity.name -ne 'ProxyBridge-TestLab' -or -not [string]::Equals([IO.Path]::GetFullPath($identity.repository_root),$packageRoot,[StringComparison]::OrdinalIgnoreCase)) {throw 'TESTLAB_STOP_INSTANCE_NOT_VERIFIED'}
    $traffic=Invoke-RestMethod ($base+'traffic/state') -TimeoutSec 3
    $legacy=Invoke-RestMethod ($base+'run') -TimeoutSec 3
    if($traffic.execution.active -or $traffic.runtime.busy -or ($legacy.run -and -not $legacy.run.terminal) -or ($legacy.suite -and -not $legacy.suite.terminal)) {throw 'TESTLAB_STOP_ACTIVE_TEST_FIRST: stop the check in the UI and wait for cleanup'}
    $process.CloseMainWindow() | Out-Null
    if (-not $process.WaitForExit(3000)) { Stop-Process -Id $process.Id; if (-not $process.WaitForExit(7000)) { throw 'TESTLAB_STOP_TIMEOUT' } }
    $stopped++
}
"STOPPED=$stopped"
