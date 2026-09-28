[CmdletBinding()]
param(
    [string]$DataRoot = '',
    [int]$StartupTimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$executable = Join-Path $packageRoot 'app\ProxyBridge.TestLab.Ui.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'TESTLAB_APPLICATION_NOT_FOUND' }
if ($StartupTimeoutSeconds -lt 5 -or $StartupTimeoutSeconds -gt 120) { throw 'STARTUP_TIMEOUT_INVALID' }

$uri = 'http://127.0.0.1:5178/'
try {
    $response = Invoke-WebRequest -Uri ($uri + 'api/v1/system/status') -UseBasicParsing -TimeoutSec 2
    if ($response.StatusCode -eq 200) { Start-Process $uri; return }
}
catch { }

$arguments = @("--RepositoryRoot=`"$packageRoot`"")
if (-not [string]::IsNullOrWhiteSpace($DataRoot)) {
    $resolvedDataRoot = [System.IO.Path]::GetFullPath($DataRoot)
    $arguments += @("--ConfigRoot=`"$resolvedDataRoot`"")
}
$process = Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $packageRoot -WindowStyle Hidden -PassThru
$deadline = [datetime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
do {
    if ($process.HasExited) { throw "TESTLAB_START_FAILED exit=$($process.ExitCode)" }
    try {
        $response = Invoke-WebRequest -Uri ($uri + 'api/v1/system/status') -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) { Start-Process $uri; return }
    }
    catch { }
    Start-Sleep -Milliseconds 250
} while ([datetime]::UtcNow -lt $deadline)

throw 'TESTLAB_STARTUP_TIMEOUT'
