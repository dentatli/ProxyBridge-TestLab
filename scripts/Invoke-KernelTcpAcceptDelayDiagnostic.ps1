[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run')][string]$Phase='Inspect')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$inner=Join-Path $PSScriptRoot 'Invoke-KernelTcpHandshakeDiagnostic.ps1'
# The existing wrapper validates paths, files, kernel gates and its trace plan.
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $(if ($Phase -eq 'Prepare') {'Prepare'} else {'Inspect'})
$policyPath=Join-Path $DiagnosticDirectory 'verification/accept-delay-policy.json'
$buildPath=Join-Path $DiagnosticDirectory 'kit/redirect-context-diagnostic.json'
$planPath=Join-Path $DiagnosticDirectory 'accept-delay-plan.json'
function Assert-AcceptDelayPolicy($Policy) {
    if ($Policy.method -cne 'first-ipv4-accept-delay-v1' -or -not $Policy.diagnostic_only -or $Policy.performance_comparable -or
        $Policy.delay_ms -ne 650 -or $Policy.delay_count -ne 1 -or $Policy.point -cne 'after-readable-before-first-ipv4-accept' -or
        $Policy.backlog_argument -cne 'SOMAXCONN_HINT(1024)' -or $Policy.backlog_argument_value -ne -1024 -or
        $Policy.only_changed_source -cne 'Windows/src/relay/pb_relay_tcp.c' -or
        -not $Policy.original_context_query_and_verdict_preserved -or -not $Policy.payload_pump_unchanged -or
        -not $Policy.wsa_state_preserved -or -not $Policy.no_delay_before_query_after_accept -or -not $Policy.no_extra_context_query -or
        $Policy.delay_runtime_observed -or -not $Policy.runtime_pending -or
        $Policy.source_before_sha256 -notmatch '^[a-f0-9]{64}$' -or $Policy.source_after_sha256 -notmatch '^[a-f0-9]{64}$') {throw 'TCP_ACCEPT_DELAY_POLICY_INVALID'}
}
$policy=Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$build=Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
Assert-AcceptDelayPolicy $policy
Assert-AcceptDelayPolicy $build.accept_delay_policy
if (($policy | ConvertTo-Json -Depth 6 -Compress) -cne ($build.accept_delay_policy | ConvertTo-Json -Depth 6 -Compress)) {throw 'TCP_ACCEPT_DELAY_POLICY_BINDING_DIFFERS'}
$paths=@($PSCommandPath,$policyPath,$buildPath,(Join-Path $DiagnosticDirectory 'source/Windows/src/relay/pb_relay_tcp.c'),
    (Join-Path $DiagnosticDirectory 'runtime-plan.json'),(Join-Path $DiagnosticDirectory 'tcp-handshake-plan.json'))
foreach ($path in $paths) {
    $cursor=[IO.Path]::GetFullPath($path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'TCP_ACCEPT_DELAY_REPARSE_POINT'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
if ((Get-FileHash -LiteralPath $paths[3]).Hash -ine $policy.source_after_sha256) {throw 'TCP_ACCEPT_DELAY_SOURCE_CHANGED'}
if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $planPath) {throw 'TCP_ACCEPT_DELAY_PLAN_ALREADY_EXISTS'}
    [ordered]@{method='first-ipv4-accept-delay-v1';files=@($paths | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8
}
$plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($plan.method -cne 'first-ipv4-accept-delay-v1' -or $plan.files.Count -ne 6 -or
    (@($plan.files.path | Sort-Object) -join '|') -ine (@($paths | Sort-Object) -join '|')) {throw 'TCP_ACCEPT_DELAY_PLAN_INVALID'}
foreach ($file in $plan.files) {
    if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'TCP_ACCEPT_DELAY_FROZEN_FILES_CHANGED'}
}
if ($Phase -in @('Prepare','Inspect')) {Write-Host 'Isolated first IPv4 accept delay 650 ms validated; backlog hint 1024; runtime pending; no installation/traffic.';return}
Write-Host 'Separate Core: backlog hint 1024; one 650 ms wait after readability before the first IPv4 accept. Same kernel, CLI, data pump and original context query; not a speed comparison.'
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $Phase
