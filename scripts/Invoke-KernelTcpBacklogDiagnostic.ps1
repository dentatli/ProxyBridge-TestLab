[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run')][string]$Phase='Inspect')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$inner=Join-Path $PSScriptRoot 'Invoke-KernelTcpHandshakeDiagnostic.ps1'
# The existing wrapper validates paths, files, kernel gates and its trace plan.
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $(if ($Phase -eq 'Prepare') {'Prepare'} else {'Inspect'})
$policyPath=Join-Path $DiagnosticDirectory 'verification/listener-backlog-policy.json'
$buildPath=Join-Path $DiagnosticDirectory 'kit/redirect-context-diagnostic.json'
$planPath=Join-Path $DiagnosticDirectory 'listener-backlog-plan.json'
function Assert-BacklogPolicy($Policy) {
    if ($Policy.method -cne 'listener-backlog-hint-v1' -or -not $Policy.diagnostic_only -or $Policy.performance_comparable -or
        $Policy.original_argument -cne 'SOMAXCONN' -or $Policy.candidate_argument -cne 'SOMAXCONN_HINT(1024)' -or
        $Policy.candidate_argument_value -ne -1024 -or $Policy.calls_changed -ne 2 -or
        (@($Policy.sockets) -join ',') -cne 'IPv4,IPv6' -or $Policy.only_changed_source -cne 'Windows/src/relay/pb_relay_tcp.c' -or
        -not $Policy.original_context_query_and_verdict_preserved -or -not $Policy.allocation_and_apply_unchanged -or
        -not $Policy.payload_pump_and_accept_loop_unchanged -or $Policy.effective_queue_capacity_observed -or
        -not $Policy.runtime_pending -or $Policy.source_before_sha256 -notmatch '^[a-f0-9]{64}$' -or
        $Policy.source_after_sha256 -notmatch '^[a-f0-9]{64}$') {throw 'TCP_BACKLOG_POLICY_INVALID'}
}
$policy=Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$build=Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
Assert-BacklogPolicy $policy
Assert-BacklogPolicy $build.listener_backlog_policy
if (($policy | ConvertTo-Json -Depth 6 -Compress) -cne ($build.listener_backlog_policy | ConvertTo-Json -Depth 6 -Compress)) {throw 'TCP_BACKLOG_POLICY_BINDING_DIFFERS'}
$paths=@($PSCommandPath,$policyPath,$buildPath,(Join-Path $DiagnosticDirectory 'source/Windows/src/relay/pb_relay_tcp.c'),
    (Join-Path $DiagnosticDirectory 'runtime-plan.json'),(Join-Path $DiagnosticDirectory 'tcp-handshake-plan.json'))
foreach ($path in $paths) {
    $cursor=[IO.Path]::GetFullPath($path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'TCP_BACKLOG_REPARSE_POINT'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
if ((Get-FileHash -LiteralPath $paths[3]).Hash -ine $policy.source_after_sha256) {throw 'TCP_BACKLOG_SOURCE_CHANGED'}
if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $planPath) {throw 'TCP_BACKLOG_PLAN_ALREADY_EXISTS'}
    [ordered]@{method='listener-backlog-hint-v1';files=@($paths | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8
}
$plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($plan.method -cne 'listener-backlog-hint-v1' -or $plan.files.Count -ne 6 -or
    (@($plan.files.path | Sort-Object) -join '|') -ine (@($paths | Sort-Object) -join '|')) {throw 'TCP_BACKLOG_PLAN_INVALID'}
foreach ($file in $plan.files) {
    if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'TCP_BACKLOG_FROZEN_FILES_CHANGED'}
}
if ($Phase -in @('Prepare','Inspect')) {Write-Host 'Isolated listener backlog hint 1024 validated; runtime pending; no installation/traffic.';return}
Write-Host 'Separate Core: only two listen arguments changed to SOMAXCONN_HINT(1024). Same kernel, CLI, data pump and context query; diagnostic only, not a speed comparison.'
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $Phase
