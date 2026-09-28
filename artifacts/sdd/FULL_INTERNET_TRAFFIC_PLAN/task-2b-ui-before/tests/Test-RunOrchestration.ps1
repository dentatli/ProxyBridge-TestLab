[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui'
$probeDll = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui.RunProbe\bin\Release\net10.0-windows\ProxyBridge.TestLab.Ui.RunProbe.dll'
$dotnet = 'C:\Program Files\dotnet\dotnet.exe'

Assert-True (Test-Path -LiteralPath $probeDll -PathType Leaf) 'run orchestration probe must be built before the targeted test'
$probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('proxybridge-testlab-run-' + [guid]::NewGuid().ToString('N'))
try {
    $probeOutput = & $dotnet $probeDll $probeRoot
    Assert-Equal 0 $LASTEXITCODE 'run orchestration probe exit code'
    Assert-True (@($probeOutput) -contains 'PASS: offline safe run orchestration') 'run orchestration probe result'

    $program = Get-Content -LiteralPath (Join-Path $uiRoot 'Program.cs') -Raw
    $models = Get-Content -LiteralPath (Join-Path $uiRoot 'Models\RunOrchestrationModels.cs') -Raw
    $executor = Get-Content -LiteralPath (Join-Path $uiRoot 'Services\RunExecutor.cs') -Raw
    $runner = Get-Content -LiteralPath (Join-Path $repoRoot 'Run-WfpMatrix.ps1') -Raw
    $javascript = Get-Content -LiteralPath (Join-Path $uiRoot 'wwwroot\app.js') -Raw
    $html = Get-Content -LiteralPath (Join-Path $uiRoot 'wwwroot\index.html') -Raw

    Assert-True ($program -match 'MapPost\("/runs/dry-run"') 'run review endpoint must exist'
    Assert-True ($program -match 'MapPost\("/runs"') 'run queue endpoint must exist'
    Assert-True ($program -match 'MapPost\("/runs/\{runId\}/cancel"') 'cooperative cancel endpoint must exist'
    Assert-True ($program -match 'MapHub<RunHub>\("/hubs/runs"\)') 'SignalR progress endpoint must exist'
    Assert-True ($program -match 'MapGet\("/runs/\{runId\}/export"') 'sanitized audit export endpoint must exist'
    Assert-True ($models -notmatch 'ExecutablePath|Environment|Credential|OutputRoot|RunnerSwitch') 'public run request must not accept private runner controls'
    Assert-True ($executor -match 'ArgumentList\.Add') 'runner arguments must use typed process argument list'
    Assert-True ($executor -notmatch 'Kill\(.*entireProcessTree') 'cancellation must not use raw process-tree kill'
    Assert-True ($runner -match 'CancellationPath') 'runner must accept the controller-owned cooperative cancellation marker'
    Assert-True ($runner -match 'PreflightOnly' -and $runner -match 'PREFLIGHT_COMPLETE') 'runner must support bounded preflight without scenario execution'
    $preflightService = Get-Content -LiteralPath (Join-Path $uiRoot 'Services\ImmutablePreflightService.cs') -Raw
    Assert-True ($preflightService -match 'SignedImmutablePreflightReceipt') 'controller must sign the exact immutable preflight receipt'
    Assert-True ($preflightService -match 'executeIfNeeded') 'queue revalidation must not silently repeat an expired review preflight'
    Assert-True ($runner -match 'New-EvidenceCompletenessMatrix') 'runner must write a mandatory evidence completeness matrix'
    Assert-True ($runner -match 'mandatory evidence incomplete') 'runner must not preserve a product verdict when mandatory evidence is incomplete'
    Assert-True ($html -match 'Fixture preview never starts ProxyBridge') 'UI must explain fixture isolation'
    Assert-True ($javascript -match 'Product outcomes continue to later independent tests') 'UI must explain continuation policy'
    Assert-True ($javascript -match 'What was tested' -and $javascript -match 'Harness / infrastructure errors') 'result UI must separate deterministic explanation fields'
    Assert-True ($javascript -match 'Assertion timeline and evidence channels') 'result UI must expose the assertion timeline'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedProbe = [System.IO.Path]::GetFullPath($probeRoot)
    if ($resolvedProbe.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedProbe).StartsWith('proxybridge-testlab-run-', [System.StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedProbe) { Remove-Item -LiteralPath $resolvedProbe -Recurse -Force }
    }
}

'PASS: safe UI run orchestration'
