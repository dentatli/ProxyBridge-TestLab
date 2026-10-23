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
$browserUri = $uri + 'lab.html'
try {
    $identity=Invoke-RestMethod -Uri ($uri+'api/v1/lab/application') -TimeoutSec 2
    if($identity.name -ne 'ProxyBridge-TestLab' -or -not [string]::Equals([IO.Path]::GetFullPath($identity.repository_root),[IO.Path]::GetFullPath($packageRoot),[StringComparison]::OrdinalIgnoreCase)) {throw 'TESTLAB_OTHER_PACKAGE_ACTIVE'}
    $response = Invoke-WebRequest -Uri ($uri + 'api/v1/lab/traffic/state') -UseBasicParsing -TimeoutSec 2
    if ($response.StatusCode -eq 200) {
        $state=$response.Content | ConvertFrom-Json
        if(-not $state.runtime.administrator) { throw "TESTLAB_EXISTING_UI_NOT_ELEVATED: close its console or use packaging/Stop-ProxyBridge-TestLab.ps1, then run Start.cmd" }
        Start-Process $browserUri; return
    }
}
catch { if($_.Exception.Message -like "TESTLAB_*") {throw} }

$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,5178)
try {$listener.Start()} catch {throw 'TESTLAB_UI_PORT_BUSY: close the other application first'} finally {$listener.Stop()}

$arguments = @("--RepositoryRoot=`"$packageRoot`"")
if (-not [string]::IsNullOrWhiteSpace($DataRoot)) {
    $resolvedDataRoot = [System.IO.Path]::GetFullPath($DataRoot)
    $arguments += @("--ConfigRoot=`"$resolvedDataRoot`"")
}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
$start=@{FilePath=$executable;ArgumentList=$arguments;WorkingDirectory=$packageRoot;WindowStyle='Hidden';PassThru=$true}
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { $start['Verb']='RunAs' }
$process = Start-Process @start
$deadline = [datetime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
do {
    if ($process.HasExited) { throw "TESTLAB_START_FAILED exit=$($process.ExitCode)" }
    try {
        $response = Invoke-WebRequest -Uri ($uri + 'api/v1/lab/traffic/state') -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) { Start-Process $browserUri; return }
    }
    catch { }
    Start-Sleep -Milliseconds 250
} while ([datetime]::UtcNow -lt $deadline)

throw 'TESTLAB_STARTUP_TIMEOUT'
