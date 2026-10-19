$ErrorActionPreference='Stop'
$file=Join-Path $PSScriptRoot '../scripts/Invoke-TargetAccept.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if ($errors.Count) {throw 'CONTROLLER_PARSE_FAILED'}
$function=$ast.Find({param($n);$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-TargetCleanupStep'},$true)
if (-not $function) {throw 'CLEANUP_GUARD_MISSING'}
# Contract regression: the lifecycle RETURN has process_result and no error;
# the EvidenceSink record has error/stdout and no process_result.
$badMember=$ast.Find({param($n);$n -is [Management.Automation.Language.MemberExpressionAst] -and
    $n.Expression.Extent.Text -eq '$lifecycle' -and $n.Member.Extent.Text -eq 'error'},$true)
if ($badMember) {throw 'CLI_RETURN_CONFUSED_WITH_SINK_SCHEMA'}
Invoke-Expression $function.Extent.Text
$run=[ordered]@{cleanup_errors=@()}
$trace=[Collections.Generic.List[string]]::new()
Invoke-TargetCleanupStep {$trace.Add('save');throw 'fixture-disk-error'}
Invoke-TargetCleanupStep {$trace.Add('resident-disable')}
Invoke-TargetCleanupStep {$trace.Add('etw-stop');throw 'fixture-etw-error'}
Invoke-TargetCleanupStep {$trace.Add('restore')}
if (($trace -join ',') -ne 'save,resident-disable,etw-stop,restore' -or
    ($run.cleanup_errors -join ',') -ne 'fixture-disk-error,fixture-etw-error') {throw 'CLEANUP_CHAIN_OR_ERRORS_LOST'}
Write-Output 'TARGET_CLEANUP_CONTINUES_AFTER_FAILURES_PASSED_NO_RUNTIME'
