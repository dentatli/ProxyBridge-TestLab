[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run')][string]$Phase='Inspect')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$inner=Join-Path $PSScriptRoot 'Invoke-KernelTcpHandshakeDiagnostic.ps1'
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $(if ($Phase -eq 'Prepare') {'Prepare'} else {'Inspect'})
Import-Module (Join-Path $root 'modules/RouteMatrixDiagnostic.psm1')
$policyPath=Join-Path $DiagnosticDirectory 'verification/route-policy.json'
$buildPath=Join-Path $DiagnosticDirectory 'kit/redirect-context-diagnostic.json'
$policy=Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$build=Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
Assert-RouteMatrixPolicy $policy
Assert-RouteMatrixPolicy $build.route_matrix_policy
if (($policy | ConvertTo-Json -Depth 6 -Compress) -cne ($build.route_matrix_policy | ConvertTo-Json -Depth 6 -Compress)) {throw 'ROUTE_MATRIX_POLICY_BINDING_DIFFERS'}
$paths=@($PSCommandPath,$policyPath,$buildPath,(Join-Path $DiagnosticDirectory 'source/Windows/src/relay/pb_relay_tcp.c'),
    (Join-Path $DiagnosticDirectory 'runtime-plan.json'),(Join-Path $DiagnosticDirectory 'tcp-handshake-plan.json'),
    (Join-Path $root 'src/pb_prepare_route_matrix.py'),(Join-Path $root 'modules/RouteMatrixDiagnostic.psm1'))
foreach ($path in $paths) {
    $cursor=[IO.Path]::GetFullPath($path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'ROUTE_MATRIX_REPARSE_POINT'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
if ((Get-FileHash -LiteralPath $paths[3]).Hash -ine $policy.source_after_sha256) {throw 'ROUTE_MATRIX_SOURCE_CHANGED'}
$planPath=Join-Path $DiagnosticDirectory 'route-matrix-plan.json'
if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $planPath) {throw 'ROUTE_MATRIX_PLAN_ALREADY_EXISTS'}
    [ordered]@{method='listener-route-matrix-v1';files=@($paths | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8
}
$plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($plan.method -cne 'listener-route-matrix-v1' -or $plan.files.Count -ne 8 -or
    (@($plan.files.path | Sort-Object) -join '|') -ine (@($paths | Sort-Object) -join '|')) {throw 'ROUTE_MATRIX_PLAN_INVALID'}
foreach ($file in $plan.files) {
    if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'ROUTE_MATRIX_FROZEN_FILES_CHANGED'}
}
if ($Phase -in @('Prepare','Inspect')) {Write-Host 'Three route cases validated; one trace/kernel installation; runtime pending; no installation/traffic.';return}
Write-Host 'Диагностика нескольких гипотез: 3 варианта, примерно 6–12 минут плюс сохранение трассы. Все исходные ошибки сохраняются. Это не измерение скорости.'
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $Phase
