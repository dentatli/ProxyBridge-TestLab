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
$errorCode=''
$cleanupVerified=$false
try {
    if (-not $binding.debugger_inactive) { throw 'TRAFFIC_DEBUGGER_STATE_REQUIRED' }
    $env:PYTHONPATH=Join-Path $binding.root 'src'
    foreach ($case in $binding.cases) {
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
        if ($code -gt 1) { throw 'TRAFFIC_RUNNER_CONFIGURATION_FAILED' }
        if (-not $result.complete) { $errorCode='TRAFFIC_CASE_FAILED'; break }
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
    $temporary=$attemptPath + '.tmp'
    [IO.File]::WriteAllText($temporary,($finished | ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $attemptPath -Force
}
if (-not $complete) { exit 1 }
