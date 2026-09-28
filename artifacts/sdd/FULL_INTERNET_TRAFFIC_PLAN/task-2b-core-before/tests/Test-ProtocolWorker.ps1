[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ProtocolWorker.psm1') -Force

$runtimePath = Join-Path $root 'config/protocol-worker-runtime.json'
$manifestPath = Join-Path $root 'src/protocol_worker/plugins/manifest.json'
$evidenceContractPath = Join-Path $root 'config/protocol-evidence-contract.json'
$entrypointPath = Join-Path $root 'src/protocol_worker/pb_protocol_worker.py'
$bundleBuilderPath = Join-Path $root 'scripts/Build-ProtocolWorkerBundle.ps1'
$contracts = Import-ProtocolWorkerRuntimeContract -RuntimeContractPath $runtimePath -PluginManifestPath $manifestPath
Assert-Equal 19 @($contracts.manifest.plugins | Where-Object implementation_status -eq 'IMPLEMENTED').Count 'Milestones 12-16 worker plugins plus offline self-test'

$plan = New-ProtocolWorkerPlan -RunId 'run-worker-001' -ScenarioId 'protocol-worker-selftest' -AttemptId 'attempt-1' -FlowId 'flow-1' -PluginId 'contract-selftest' -ProtocolFamily 'native-tcp' -Transport NONE -OperationTimeoutMs 5000 -Parameters ([pscustomobject]@{mode='offline'}) -Expected ([pscustomobject]@{result='PASS'}) -RuntimeContracts $contracts
Assert-True (Test-ProtocolWorkerPlan -Plan $plan -RuntimeContracts $contracts) 'valid worker plan'
Assert-Throws { New-ProtocolWorkerPlan -RunId 'run-worker-001' -ScenarioId 'unknown' -AttemptId 'attempt-1' -FlowId 'flow-1' -PluginId 'unknown-plugin' -ProtocolFamily 'http1' -Transport TCP -OperationTimeoutMs 5000 -RuntimeContracts $contracts } 'PROTOCOL_WORKER_PLUGIN_NOT_IMPLEMENTED' 'unknown plugin must fail closed'
Assert-Throws { New-ProtocolWorkerPlan -RunId 'run-worker-001' -ScenarioId 'secret' -AttemptId 'attempt-1' -FlowId 'flow-1' -PluginId 'contract-selftest' -ProtocolFamily 'native-tcp' -Transport NONE -OperationTimeoutMs 5000 -Parameters ([pscustomobject]@{api_token='fixture-value'}) -RuntimeContracts $contracts } 'PROTOCOL_WORKER_PLAN_SECRET_VALUE_FORBIDDEN' 'secret values must not enter the public protocol plan'

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) { throw 'TEST_PYTHON_NOT_FOUND' }
$temp = New-TestDirectory
try {
    $planPath = Join-Path $temp 'plan.json'
    $outputPath = Join-Path $temp 'evidence.jsonl'
    Write-ProtocolWorkerPlan -Plan $plan -Path $planPath -RuntimeContracts $contracts
    Assert-NoUtf8Bom $planPath 'protocol worker plan must be UTF-8 without BOM'
    $launch = Get-ProtocolWorkerLaunchPlan -PythonExecutablePath $pythonCommand.Source -EntrypointPath $entrypointPath -ManifestPath $manifestPath -PlanPath $planPath -OutputJsonlPath $outputPath -ProcessTimeoutMs 10000
    Assert-True (@($launch.argument_list) -contains '-I') 'worker Python must use isolated mode'
    Assert-True (@($launch.argument_list) -contains '-B') 'worker must not write bytecode beside public source'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $launch.executable_path
    $quoted = foreach ($argument in @($launch.argument_list)) { '"' + ([string]$argument).Replace('"','\"') + '"' }
    $psi.Arguments = $quoted -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    Assert-True $process.Start() 'offline protocol worker must start'
    Assert-True $process.WaitForExit(10000) 'offline protocol worker must finish within the bounded timeout'
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    Assert-Equal 0 $process.ExitCode 'offline protocol worker exit code'
    Assert-Equal 'PROTOCOL_WORKER_OK records=1' $stdout 'worker stdout must contain only a stable status'
    Assert-Equal '' $stderr 'valid worker stderr must be empty'
    Assert-NoUtf8Bom $outputPath 'protocol worker JSONL must be UTF-8 without BOM'
    $records = @(Read-ProtocolWorkerEvidence -Path $outputPath -Plan $plan -RuntimeContracts $contracts -EvidenceContractPath $evidenceContractPath)
    Assert-Equal 1 $records.Count 'offline self-test evidence record count'
    Assert-Equal 'SELF_TEST_COMPLETED' $records[0].event 'offline self-test event'
    Assert-Equal 'PASS' $records[0].result 'offline self-test result'

    $tamperedPath = Join-Path $temp 'tampered.jsonl'
    $tampered = $records[0] | Select-Object * -ExcludeProperty payload_sha256
    Write-TestUtf8NoBom $tamperedPath (($tampered | ConvertTo-Json -Compress) + [Environment]::NewLine)
    Assert-Throws { Read-ProtocolWorkerEvidence -Path $tamperedPath -Plan $plan -RuntimeContracts $contracts -EvidenceContractPath $evidenceContractPath } 'PROTOCOL_WORKER_EVIDENCE_FIELD_MISSING' 'missing mandatory evidence field must fail closed'

    $bundleRoot = Join-Path $temp 'bundle-output'
    $sourcePythonRoot = Split-Path -Parent $pythonCommand.Source
    $bundleResult = & $bundleBuilderPath -PythonRuntimeRoot $sourcePythonRoot -OutputRoot $bundleRoot -BundleName 'worker-test'
    Assert-True ([bool]$bundleResult.self_test_passed) 'assembled protocol worker runtime must pass its own offline self-test'
    Assert-Equal 'x64' $bundleResult.architecture 'assembled protocol worker runtime architecture'
    $bundlePath = [string]$bundleResult.bundle_path
    foreach ($required in @('runtime/python/python.exe','worker/pb_protocol_worker.py','worker/plugins/manifest.json','worker/_vendor/aioquic/__init__.py','config/protocol-dependencies.lock.json','BUNDLE-MANIFEST.json','SHA256SUMS.txt')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $bundlePath $required) -PathType Leaf) "bundle required file $required"
    }
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $bundlePath -Recurse -Force | Where-Object { $_.Name -in @('site-packages','__pycache__') -or $_.Extension -in @('.pdb','.pyc','.pyo') }).Count 'bundle must exclude user packages, bytecode and debug artifacts'
    Assert-NoUtf8Bom (Join-Path $bundlePath 'BUNDLE-MANIFEST.json') 'bundle manifest must be UTF-8 without BOM'
    Assert-NoUtf8Bom (Join-Path $bundlePath 'SHA256SUMS.txt') 'bundle checksums must be UTF-8 without BOM'
    $bundleManifest = Get-Content -LiteralPath (Join-Path $bundlePath 'BUNDLE-MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 'protocol-quic-1' ([string]$bundleManifest.dependency_set) 'bundle must identify its exact offline dependency set'
    Assert-True (-not [bool]$bundleManifest.network_installation_allowed) 'bundle must prohibit runtime dependency downloads'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: bundled protocol worker contract and offline self-test'
