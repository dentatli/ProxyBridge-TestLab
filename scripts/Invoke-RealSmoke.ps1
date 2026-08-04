[CmdletBinding()]
param(
    [switch]$ConfirmRealRuntime,
    [string]$EnvPath,
    [string]$OutputRoot,
    [switch]$SkipEnvironmentPreparation,
    [string]$VpsEvidenceImportPath,
    [string]$ExpectedDirectEgressIpv4,
    [string]$ExpectedProxyEgressIpv4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $ConfirmRealRuntime) { throw 'REAL_RUNTIME_CONFIRMATION_REQUIRED' }
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $repoRoot '.env' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'evidence/real-smoke' }
$runnerParameters = @{
    EnvPath=$EnvPath
    CapabilitiesPath=(Join-Path $repoRoot 'config/capabilities.json')
    SuitePath=(Join-Path $repoRoot 'config/suites/real-smoke.json')
    KnownDefectsPath=(Join-Path $repoRoot 'config/known-defects.json')
    RuntimeConfigPath=(Join-Path $repoRoot 'config/runtime.json')
    ScenarioRoot=(Join-Path $repoRoot 'scenarios')
    OutputRoot=$OutputRoot
    Only=@('issue206-proxy-to-block-abortive')
    MaxScenarios=1
    StopOnInfrastructureFailure=$true
    AllowProductRuntime=$true
    PrepareRuntimeEnvironment=(-not $SkipEnvironmentPreparation)
}
if (-not [string]::IsNullOrWhiteSpace($VpsEvidenceImportPath)) { $runnerParameters.VpsEvidenceImportPath=$VpsEvidenceImportPath }
if (-not [string]::IsNullOrWhiteSpace($ExpectedDirectEgressIpv4)) { $runnerParameters.ExpectedDirectEgressIpv4=$ExpectedDirectEgressIpv4 }
if (-not [string]::IsNullOrWhiteSpace($ExpectedProxyEgressIpv4)) { $runnerParameters.ExpectedProxyEgressIpv4=$ExpectedProxyEgressIpv4 }

$runnerOutput=[System.Collections.Generic.List[string]]::new();$runnerFailure=$null
try {
    & (Join-Path $repoRoot 'Run-WfpMatrix.ps1') @runnerParameters | ForEach-Object { $line=[string]$_;$runnerOutput.Add($line);Write-Output $line }
}
catch { $runnerFailure=$_ }

$completion=@($runnerOutput|Where-Object{$_ -match '^RUN_COMPLETE\s'})|Select-Object -Last 1
if($null -eq $completion -or [string]$completion -notmatch '\brun_id=(?<run_id>[^\s]+)'){
    Write-Output 'REAL_SMOKE_RESULT=FAIL run_id=UNKNOWN runtime_status=NO_RUN_RESULT'
    if($null -ne $runnerFailure){throw $runnerFailure};throw 'REAL_SMOKE_RESULT_NOT_FOUND'
}
$runId=[string]$Matches.run_id;$runRoot=Join-Path $OutputRoot $runId;$resultsPath=Join-Path $runRoot 'results.jsonl'
$runtimeStatus='FAIL_INFRASTRUCTURE';$formalStatus='FAIL'
if(Test-Path -LiteralPath $resultsPath -PathType Leaf){
    $records=@(foreach($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $resultsPath))){if(-not [string]::IsNullOrWhiteSpace($line)){$line|ConvertFrom-Json}})
    $executed=@($records|Where-Object{[bool]$_.selected -and [int]$_.attempt -gt 0})
    if($executed.Count -eq 1){$runtimeStatus=[string]$executed[0].status;$formalStatus=$(if($runtimeStatus -eq 'PASS'){'PASS'}elseif($runtimeStatus -match 'HOLD|AMBIGUOUS|CONTAMINATED'){'HOLD'}else{'FAIL'})}
}
Write-Output "REAL_SMOKE_RESULT=$formalStatus run_id=$runId runtime_status=$runtimeStatus"
if(@($runnerOutput|Where-Object{$_ -match '^EVIDENCE_PATH='}).Count -eq 0){Write-Output "EVIDENCE_PATH=$runRoot"}
if($null -ne $runnerFailure){throw $runnerFailure}
if($formalStatus -ne 'PASS'){throw "REAL_SMOKE_$formalStatus status=$runtimeStatus"}
