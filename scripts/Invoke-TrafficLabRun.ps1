#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BindingPath,[Parameter(Mandatory)][string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$binding=Get-Content -LiteralPath $BindingPath -Raw | ConvertFrom-Json
$attemptPath=Join-Path $OutputRoot 'attempt.json'
$attempt=Get-Content -LiteralPath $attemptPath -Raw | ConvertFrom-Json
$results=[Collections.Generic.List[object]]::new()
$recoveryChecks=[Collections.Generic.List[object]]::new()
$continueAfterFailure=$binding.PSObject.Properties.Name -contains 'continue_after_failure' -and $binding.continue_after_failure -eq $true
$caseIndex=0
$errorCode=''
$cleanupVerified=$false
try {
    $env:PYTHONPATH=Join-Path $binding.root 'src'
    foreach ($case in $binding.cases) {
        $caseIndex++
        if (Test-Path -LiteralPath $binding.cancellation_path) { break }
        foreach ($property in $binding.source_hashes.PSObject.Properties) {
            if (-not (Test-Path -LiteralPath $property.Name -PathType Leaf) -or
                (Get-FileHash -LiteralPath $property.Name -Algorithm SHA256).Hash -ine [string]$property.Value) { throw 'TRAFFIC_IMMUTABLE_FILE_CHANGED' }
        }
        $report=Join-Path $OutputRoot ($case.case_id + '.report.json')
        & $binding.python -B -m trafficlab.runner --binding $BindingPath --case $case.case_id --output $report --progress (Join-Path $OutputRoot 'progress.json')
        $code=$LASTEXITCODE
        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) { throw 'TRAFFIC_CASE_REPORT_MISSING' }
        $result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
        if ($result.case_id -ne $case.case_id -or $result.duration -ne $case.duration -or $result.load -ne $case.load -or
            $result.complete -isnot [bool] -or $result.cleanup_verified -isnot [bool]) { throw 'TRAFFIC_CASE_REPORT_INVALID' }
        foreach ($property in $binding.source_hashes.PSObject.Properties) {
            if (-not (Test-Path -LiteralPath $property.Name -PathType Leaf) -or
                (Get-FileHash -LiteralPath $property.Name -Algorithm SHA256).Hash -ine [string]$property.Value) {
                $result.complete=$false
                $result.errors=@($result.errors)+@('TRAFFIC_IMMUTABLE_FILE_CHANGED')
            }
        }
        $results.Add($result)
        $cleanupVerified=[bool]$result.cleanup_verified
        if (-not $cleanupVerified) { throw 'TRAFFIC_CLEANUP_NOT_VERIFIED' }
        if ($code -notin @(0,1) -or $code -ne [int](-not $result.complete)) { throw 'TRAFFIC_RUNNER_CONFIGURATION_FAILED' }
        if (-not $result.complete) {
            $errorCode='TRAFFIC_CASE_FAILED'
            if (Test-Path -LiteralPath $binding.cancellation_path) { break }
            if (-not $continueAfterFailure -or $caseIndex -eq @($binding.cases).Count) { break }
            $guardJson=& $binding.python -B -m trafficlab.queue_guard --binding $BindingPath --report $report
            $guardExit=$LASTEXITCODE
            if (-not $guardJson) { throw 'TRAFFIC_RECOVERY_REPORT_MISSING' }
            $guard=$guardJson | ConvertFrom-Json
            if ($guard.case_id -ne $case.case_id -or $guard.safe_to_continue -isnot [bool]) { throw 'TRAFFIC_RECOVERY_REPORT_INVALID' }
            $recoveryChecks.Add($guard)
            if ($guard.fresh_off_verified -is [bool]) { $cleanupVerified=$guard.fresh_off_verified }
            foreach ($property in $binding.source_hashes.PSObject.Properties) {
                if (-not (Test-Path -LiteralPath $property.Name -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $property.Name -Algorithm SHA256).Hash -ine [string]$property.Value) { throw 'TRAFFIC_IMMUTABLE_FILE_CHANGED' }
            }
            if (Test-Path -LiteralPath $binding.cancellation_path) { break }
            if ($guardExit -ne 0 -or -not $guard.safe_to_continue) { throw 'TRAFFIC_RECOVERY_BLOCKED' }
        }
    }
} catch {
    $message=[string]$_.Exception.Message
    $errorCode=if ($message -match '^TRAFFIC_[A-Z0-9_]+$') {$message} else {'TRAFFIC_CONTROLLER_FAILED'}
} finally {
    $cancelled=Test-Path -LiteralPath $binding.cancellation_path
    if($results.Count -eq 0){
        try {
            $off=& (Join-Path $binding.root 'scripts/Assert-TrafficLabIdle.ps1') -BindingPath $BindingPath | ConvertFrom-Json
            $cleanupVerified=[bool]$off.off_verified
        } catch { $cleanupVerified=$false }
    }
    foreach($case in $binding.cases){
        if(@($results | Where-Object case_id -eq $case.case_id).Count -eq 0){
            $results.Add([pscustomobject]@{case_id=$case.case_id;duration=$case.duration;load=$case.load;complete=$false;
                cancelled=[bool]$cancelled;skipped=$true;cleanup_verified=[bool]$cleanupVerified;
                errors=@($(if($cancelled){'SKIPPED_AFTER_CANCEL'}else{'SKIPPED_AFTER_FAILURE'}));measurements=@()})
        }
    }
    $complete=-not $cancelled -and -not $errorCode -and $results.Count -eq @($binding.cases).Count -and
        @($results | Where-Object {-not $_.complete}).Count -eq 0 -and $cleanupVerified
    $finished=[ordered]@{id=$binding.id;state=$(if ($cancelled) {'CANCELLED'} elseif ($complete) {'COMPLETE'} else {'FAILED'});
        build_id=$binding.build_id;build_sha256=$binding.build_sha256;remote_bundle_sha256=$binding.remote_bundle_sha256;
        cases=$attempt.cases;started_at_utc=$attempt.started_at_utc;completed_at_utc=[DateTime]::UtcNow.ToString('o');
        complete=[bool]$complete;cleanup_verified=[bool]$cleanupVerified;error=$errorCode;results=@($results)}
    $finished['continue_after_failure']=[bool]$continueAfterFailure
    $finished['recovery_checks']=@($recoveryChecks)
    $temporary=$attemptPath + '.tmp'
    [IO.File]::WriteAllText($temporary,($finished | ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $attemptPath -Force
}
if (-not $complete) { exit 1 }
