[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [ValidateSet('Single','ConnectionMatrix','RouteMatrix','ExternalReceiverPair')][string]$ExperimentSet='Single')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
$root=Split-Path -Parent $PSScriptRoot
function Assert-PlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'REDIRECT_DIAGNOSTIC_REPARSE_POINT'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) {throw 'REDIRECT_DIAGNOSTIC_JSON_TOO_LARGE'}
    # Keep ISO timestamps as strings in PS7 too; DateTime -> culture string loses the UTC offset.
    $jsonText=Get-Content -LiteralPath $Path -Raw
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $jsonText -DateKind String}
    return ConvertFrom-Json -InputObject $jsonText
}
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $DiagnosticDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $DiagnosticDirectory) -notmatch '^tcp-redirect-context-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'REDIRECT_DIAGNOSTIC_DIRECTORY_INVALID'}
Assert-PlainPath $DiagnosticDirectory
$kit=Join-Path $DiagnosticDirectory 'kit'
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if ($receipt.status -ne 'DIAGNOSTIC_BUILD_PREPARED' -or $receipt.method -notin @('redirect-context-logging-v1','redirect-context-followup-v2','redirect-context-probes-v3','redirect-kernel-context-v4') -or
    -not $receipt.diagnostic_only -or $receipt.performance_comparable -or $receipt.source_commit -ne '63be0ebf9bec92bfba95ef3d6729c375aa9af84e') {throw 'REDIRECT_DIAGNOSTIC_KIT_INVALID'}
if ($receipt.method -eq 'redirect-kernel-context-v4') {
    $validation=Read-Json (Join-Path $DiagnosticDirectory 'verification/validation.json')
    if ($validation.status -ne 'PREPARED_STATIC_CHECKS_PASSED_RUNTIME_PENDING' -or
        $validation.kernel_sha256 -ine (Get-FileHash -LiteralPath (Join-Path $kit 'ProxyBridgeDrv.sys')).Hash -or
        $validation.core_sha256 -ine (Get-FileHash -LiteralPath (Join-Path $kit 'ProxyBridgeCore.dll')).Hash) {throw 'KERNEL_CANDIDATE_INTEGRATION_CHECKS_INCOMPLETE'}
    foreach ($file in $validation.prepared_source_sha256.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $file.Name)).Hash -ine $file.Value) {throw 'KERNEL_CANDIDATE_VALIDATED_SOURCE_CHANGED'}
    }
}
if ($receipt.method -in @('redirect-context-followup-v2','redirect-context-probes-v3') -and (-not $receipt.followup_only_after_api_failure -or -not $receipt.original_verdict_preserved -or
    $receipt.followup_buffer_capacity -ne 1024 -or $receipt.followup_queries_per_failure -ne 3 -or $receipt.followup_payload_recorded)) {throw 'REDIRECT_DIAGNOSTIC_FOLLOWUP_CONTRACT_INVALID'}
if ($receipt.method -eq 'redirect-context-probes-v3' -and ($receipt.probe_policy.positive_first_sequences -ne 4 -or $receipt.probe_policy.positive_sequence_stride -ne 128 -or
    $receipt.probe_policy.positive_limit -ne 16 -or (@($receipt.probe_policy.delayed_targets_ms) -join ',') -ne '5,25,100' -or $receipt.probe_policy.delayed_failure_limit -ne 1000 -or
    $receipt.probe_policy.probe_buffer_capacity -ne 1024 -or $receipt.probe_policy.socket_metadata -ne 'type-and-endpoints-no-so-error-v1' -or
    -not $receipt.probe_policy.original_verdict_preserved -or $receipt.probe_policy.probe_payload_recorded)) {throw 'REDIRECT_DIAGNOSTIC_PROBE_POLICY_INVALID'}
if ($ExperimentSet -eq 'ConnectionMatrix' -and $receipt.method -ne 'redirect-context-followup-v2') {throw 'REDIRECT_MATRIX_REQUIRES_FOLLOWUP_CORE'}
$matrixCaseIds=@('connectex-32','connectex-1','connect-32','connect-1')
$routeMatrix=$null;$externalPair=$null
if ($receipt.PSObject.Properties['external_receiver_policy']) {
    Import-Module (Join-Path $root 'modules/ExternalReceiverDiagnostic.psm1')
    $externalPair=$receipt.external_receiver_policy
    Assert-ExternalReceiverPolicy $externalPair
}
if ($receipt.PSObject.Properties['route_matrix_policy']) {
    Import-Module (Join-Path $root 'modules/RouteMatrixDiagnostic.psm1')
    Assert-RouteMatrixPolicy $receipt.route_matrix_policy
    if ($receipt.method -ne 'redirect-kernel-context-v4' -or ($PSBoundParameters.ContainsKey('ExperimentSet') -and $ExperimentSet -ne $(if ($externalPair) {'ExternalReceiverPair'} else {'RouteMatrix'}))) {throw 'ROUTE_MATRIX_REQUIRES_KERNEL_CORE'}
    $routeMatrix=$receipt.route_matrix_policy
    $ExperimentSet=$(if ($externalPair) {'ExternalReceiverPair'} else {'RouteMatrix'})
    $matrixCaseIds=$(if ($externalPair) {@($externalPair.cases)} else {@($routeMatrix.cases)})
} elseif ($ExperimentSet -in @('RouteMatrix','ExternalReceiverPair')) {throw 'ROUTE_MATRIX_POLICY_MISSING'}
$freezePath=Join-Path $DiagnosticDirectory 'runtime-plan.json'
if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $freezePath) {throw 'REDIRECT_DIAGNOSTIC_PLAN_ALREADY_PREPARED'}
    $files=@('scripts/Invoke-TcpRedirectContextDiagnostic.ps1','scripts/Invoke-LocalTcpConnections.ps1',
        'src/pb_tcp_redirect_context_report.py','src/pb_tcp_connections_report.py','src/pb_controlled_tcp_proxy.py','src/pb_pc_sampler.py',
        'bin/pb_console_host.exe','bin/pb_wfp_state.exe',
        'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe','bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe',
        'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl',
        'bin/tools/windivert-2.2.2/windivertctl.exe','bin/tools/windivert-2.2.2/WinDivert.dll') | ForEach-Object {Join-Path $root $_}
    $files+=@('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence','ConnectionLoad','ProductProfile') | ForEach-Object {Join-Path $root ('modules/'+$_+'.psm1')}
    if ($routeMatrix) {$files+=@((Join-Path $root 'modules/RouteMatrixDiagnostic.psm1'),(Join-Path $root 'src/pb_tcp_route_matrix_report.py'),(Join-Path $root 'src/pb_tcp_route_legs.py'))}
    if ($externalPair) {
        $files+=@('modules/ExternalReceiverDiagnostic.psm1','scripts/Invoke-LinuxCtsReceiver.ps1','scripts/Invoke-KernelTcpExternalReceiverDiagnostic.ps1','src/pb_tcp_external_receiver_evidence.py','src/pb_tcp_external_receiver_report.py','src/pb_cts_push_receiver.py','src/pb_linux_cts_control.py','src/pb_prepare_external_receiver_pair.py') | ForEach-Object {Join-Path $root $_}
        $files+=$externalPair.connection_file
    }
    $files+=@('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys','product.env','redirect-context-diagnostic.json') | ForEach-Object {Join-Path $kit $_}
    $files+=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys'
    if ($receipt.method -in @('redirect-context-followup-v2','redirect-context-probes-v3','redirect-kernel-context-v4')) {$files+=Join-Path $root 'src/pb_tcp_redirect_context_extended_report.py'}
    if ($receipt.method -eq 'redirect-context-probes-v3') {$files+=@('pb_tcp_redirect_context_probes_report.py','pb_prepare_redirect_context_probes.py','pb_prepare_redirect_context_extended.py','pb_prepare_redirect_context_diagnostic.py') | ForEach-Object {Join-Path $root ('src/'+$_)}}
    if ($receipt.method -eq 'redirect-kernel-context-v4') {
        $files+=@('pb_kernel_context_collector.py','pb_tcp_kernel_context_report.py','pb_prepare_kernel_context_diagnostic.py','pb_kernel_diag_shared.h','pb_kernel_diag_internal.h') | ForEach-Object {Join-Path $root ('src/'+$_)}
        $files+=Join-Path $root 'scripts/Invoke-KernelContextDiagnostic.ps1'
        $files+=Join-Path $DiagnosticDirectory 'verification/validation.json'
        $files+=Join-Path $root 'config/runtime.json'
        $files+=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env'
        if ($receipt.PSObject.Properties['timing_policy']) {
            if ($receipt.timing_policy.method -ne 'accept-query-qpc-v1' -or -not $receipt.timing_policy.original_single_query_preserved -or
                -not $receipt.timing_policy.logging_after_original_query -or $receipt.timing_policy.payload_recorded -or
                (@($receipt.timing_policy.points) -join ',') -ne 'accept-return,query-entry,query-exit') {throw 'KERNEL_TIMING_POLICY_INVALID'}
            $files+=Join-Path $root 'src/pb_tcp_kernel_timing_report.py'
            $files+=Join-Path $root 'src/pb_prepare_kernel_timing_diagnostic.py'
            $files+=Join-Path $root 'scripts/Build-KernelTimingDiagnostic.ps1'
        }
    }
    if ($ExperimentSet -eq 'ConnectionMatrix' -or $receipt.method -in @('redirect-context-probes-v3','redirect-kernel-context-v4')) {
        $files+=Join-Path $root 'src/pb_tcp_redirect_context_matrix_report.py'
        $files+=Join-Path $root 'src/pb_proactor_close_guard.py'
        $files+=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/Lib/asyncio/proactor_events.py'
    }
    $python=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $files+=$python
    $hashes=@($files | ForEach-Object {Assert-PlainPath $_;[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
    [ordered]@{schema_version=1;diagnostic_only=$true;performance_comparable=$false;experiment_set=$ExperimentSet;fixture_close_guard=$(if ($ExperimentSet -eq 'ConnectionMatrix' -or $receipt.method -in @('redirect-context-probes-v3','redirect-kernel-context-v4')) {'pinned-proactor-shutdown-reset-close-v1'} else {''});matrix_cases=$(if ($ExperimentSet -eq 'ConnectionMatrix') {$matrixCaseIds} else {@()});created_at_utc=[DateTime]::UtcNow.ToString('o');python=$python;files=$hashes} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $freezePath -Encoding UTF8
    if ($routeMatrix) {
        $routeFreeze=Read-Json $freezePath
        $routeFreeze.matrix_cases=$matrixCaseIds
        $routeFreeze | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $freezePath -Encoding UTF8
    }
}
$freeze=Read-Json $freezePath
if ($freeze.schema_version -ne 1 -or -not $freeze.diagnostic_only -or $freeze.performance_comparable -or $freeze.files.Count -lt 20) {throw 'REDIRECT_DIAGNOSTIC_PLAN_INVALID'}
$frozenExperimentSet='Single'
if ($freeze.PSObject.Properties['experiment_set']) {$frozenExperimentSet=[string]$freeze.experiment_set}
if ($frozenExperimentSet -notin @('Single','ConnectionMatrix','RouteMatrix','ExternalReceiverPair') -or ($PSBoundParameters.ContainsKey('ExperimentSet') -and $ExperimentSet -ne $frozenExperimentSet)) {throw 'REDIRECT_DIAGNOSTIC_EXPERIMENT_SET_DIFFERS'}
if (($frozenExperimentSet -in @('RouteMatrix','ExternalReceiverPair')) -ne [bool]$routeMatrix -or ($routeMatrix -and ((@($freeze.matrix_cases) -join ',') -cne ($matrixCaseIds -join ',') -or $freeze.fixture_close_guard -ne 'pinned-proactor-shutdown-reset-close-v1'))) {throw 'ROUTE_MATRIX_PLAN_INVALID'}
if ($frozenExperimentSet -eq 'ConnectionMatrix' -and ($receipt.method -ne 'redirect-context-followup-v2' -or -not $freeze.PSObject.Properties['matrix_cases'] -or (@($freeze.matrix_cases) -join ',') -ne ($matrixCaseIds -join ','))) {throw 'REDIRECT_DIAGNOSTIC_MATRIX_PLAN_INVALID'}
if ($frozenExperimentSet -eq 'ConnectionMatrix' -and (-not $freeze.PSObject.Properties['fixture_close_guard'] -or $freeze.fixture_close_guard -ne 'pinned-proactor-shutdown-reset-close-v1')) {throw 'REDIRECT_DIAGNOSTIC_MATRIX_CLOSE_POLICY_INVALID'}
if ($receipt.method -in @('redirect-context-probes-v3','redirect-kernel-context-v4') -and (($frozenExperimentSet -ne 'Single' -and -not $routeMatrix) -or $freeze.fixture_close_guard -ne 'pinned-proactor-shutdown-reset-close-v1')) {throw 'REDIRECT_PROBES_PLAN_INVALID'}
foreach ($file in $freeze.files) {
    Assert-PlainPath $file.path
    if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'REDIRECT_DIAGNOSTIC_FROZEN_FILES_CHANGED'}
}
Import-Module (Join-Path $root 'modules/Env.psm1')
Import-Module (Join-Path $root 'modules/ProductBuild.psm1')
$productEnvironment=Import-DotEnv (Join-Path $kit 'product.env')
if ($productEnvironment['PB_PROXYBRIDGE_CLI_EXE'] -ine (Join-Path $kit 'ProxyBridge_CLI.exe') -or
    $productEnvironment['PB_DRIVER_PATH'] -ine (Join-Path $kit 'ProxyBridgeDrv.sys') -or
    $productEnvironment['PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC'] -ne $receipt.method -or
    $freeze.python -ine (Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')) {throw 'REDIRECT_DIAGNOSTIC_PATH_BINDING_INVALID'}
$identity=Get-ProductBuildIdentity -Environment $productEnvironment -Contract driver
if (-not $identity.files_verified) {throw 'REDIRECT_DIAGNOSTIC_FILES_NOT_VERIFIED'}
if ($Phase -ne 'Run') {
    [ordered]@{status='DIAGNOSTIC_FILES_VALIDATED';diagnostic_only=$true;performance_comparable=$false;runtime_ready=$false;
        product_started=$false;traffic_generated=$false;driver_state_observed=$false;experiment_set=$frozenExperimentSet;bundle_sha256=$identity.bundle_sha256} | ConvertTo-Json
    return
}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'LAB_RUN_REQUIRES_ADMINISTRATOR'}
$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark')
$owns=$false;$lease=$null
try {
    try {$owns=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owns=$true}
    if (-not $owns) {throw 'LAB_PLANNED_RUN_ALREADY_ACTIVE'}
    $leasePath=Join-Path $root 'artifacts/benchmark-launch/execution.lock';Assert-PlainPath $leasePath
    try {$lease=[IO.File]::Open($leasePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch {throw 'LAB_OTHER_REAL_RUN_ACTIVE_OR_LEASE_UNAVAILABLE'}
    # Same recorded legacy/cross-boot policy as the planned benchmark wrapper.
    $history=@()
    foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/local-route') -Directory)) {
        if ($directory.Name -match '(?:4\.0\.0|v4\.0\.0)') {
            $file=Join-Path $directory.FullName 'comparison-manifest.json'
            if (Test-Path -LiteralPath $file) {$history+=$file}
        }
    }
    foreach ($preflight in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/version-comparison') -Directory -Filter 'preflight-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $preflight.FullName -Directory -Filter 'legacy-lifecycle-*')) {
            $file=Join-Path $directory.FullName 'lifecycle-receipt.json'
            if (Test-Path -LiteralPath $file) {$history+=$file}
        }
    }
    $latestLegacy=[DateTimeOffset]::MinValue
    foreach ($file in $history) {
        $saved=Read-Json $file
        foreach ($name in @('started_at_utc','completed_at_utc')) {
            if ($saved.PSObject.Properties[$name] -and $saved.$name) {
                $time=[DateTimeOffset]::Parse([string]$saved.$name);if ($time -gt $latestLegacy) {$latestLegacy=$time}
            }
        }
        $written=[DateTimeOffset](Get-Item -LiteralPath $file).LastWriteTimeUtc
        if ($written -gt $latestLegacy) {$latestLegacy=$written}
    }
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5
    $boot=[DateTimeOffset](([DateTime]$os.LastBootUpTime).ToUniversalTime())
    if ($boot -le $latestLegacy) {throw 'LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0'}
    foreach ($control in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter '*-control')) {
        $file=Join-Path $control.FullName 'job.json'
        if (Test-Path -LiteralPath $file) {
            $saved=Read-Json $file
            if ($saved.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $boot -le [DateTimeOffset]::Parse([string]$saved.updatedAtUtc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN'}
        }
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter 'tcp-redirect-context-run-*')) {
        $file=Join-Path $directory.FullName 'diagnostic-run.json'
        if (Test-Path -LiteralPath $file) {
            $saved=Read-Json $file
            if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/tcp-redirect-context-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    # The controller owns creation of its fresh evidence directory; wrapper receipts stay in the parent.
    $workloadEvidence=Join-Path $evidence 'workload'
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');runtime_plan_sha256=(Get-FileHash -LiteralPath $freezePath).Hash;workload_directory='workload';error=''}
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    Copy-Item -LiteralPath $freezePath -Destination (Join-Path $evidence 'runtime-plan.json')
    Copy-Item -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Destination (Join-Path $evidence 'diagnostic-build.json')
    $matrix=$null
    if ($frozenExperimentSet -in @('ConnectionMatrix','RouteMatrix','ExternalReceiverPair')) {
        $matrix=[ordered]@{schema_version=1;method=$(if ($externalPair) {'local-linux-receiver-pair-v1'} elseif ($routeMatrix) {'listener-route-matrix-v1'} else {'redirect-context-matrix-v2'});fixture_close_guard=$freeze.fixture_close_guard;diagnostic_only=$true;performance_comparable=$false;status='RUNNING';error='';cases=@($matrixCaseIds | ForEach-Object {[ordered]@{id=$_;directory=$_;status='SKIPPED'}})}
        $run['experiment_set']=$frozenExperimentSet;$run.workload_directory=''
        if ($externalPair) {Write-Host 'Парный контроль: локальный / Linux получатель, исходная очередь Core и локальный SOCKS5. Каждый 4 → 64 → 256 → 640 → 4; примерно 4–8 минут плюс трасса. Не измерение скорости.'}
        elseif ($routeMatrix) {Write-Host 'Три варианта одной командой: исходная очередь / очередь 1024 / очередь 1024 с задержкой приёма 650 мс. Каждый 4 → 64 → 256 → 640 → 4; примерно 6–12 минут. Общая TCP-трасса, kernel/Core/query/data; не сравнение скорости.'}
        else {Write-Host 'Диагностика четырёх вариантов: ConnectEx/connect × 32/1 ожидающих подключений; каждый 4 → 64 → 256 → 640 → 4. Примерно 8–16 минут; одна команда. Не сравнение скорости.'}
    } elseif ($receipt.method -eq 'redirect-context-probes-v3') {Write-Host 'Три проверки за один запуск: RECORDS на успешных сокетах; context спустя 5/25/100 мс; тип и адреса отказавшего сокета. ConnectEx/32, 4 → 64 → 256 → 640 → 4. Примерно 2–5 минут; задержки меняют условия, не сравнение скорости.'}
    elseif ($receipt.method -eq 'redirect-kernel-context-v4') {Write-Host 'Диагностика kernel → Core: выделение контекста, WFP attachment/Apply, повторная classify и исходный query. ConnectEx/32, 4 → 64 → 256 → 640 → 4; примерно 2–4 минуты. Отдельный подписанный драйвер; не сравнение скорости.'}
    else {Write-Host 'Диагностика: исходные CLI/driver, отдельный Core с журналом; только PROXY, 4 → 64 → 256 → 640 → 4; примерно 2–4 минуты. Не сравнение скорости.'}
    try {
        if ($matrix) {
            foreach ($case in $matrix.cases) {
                $case.status='RUNNING'
                $matrix | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'matrix-manifest.json') -Encoding UTF8
                Write-Host ('Вариант / Case: '+$case.id)
                try {
                    if ($externalPair) {
                        Invoke-ExternalReceiverCase -Case $case.id -Workload {
                            & (Join-Path $PSScriptRoot 'Invoke-LocalTcpConnections.ps1') -Profile SMOKE -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $freeze.python -EvidenceDirectory (Join-Path $evidence $case.directory) -DiagnosticRedirectContext -DiagnosticConnectionCase 'connectex-32' -DiagnosticFixtureCloseGuard -DiagnosticRouteCase original -DiagnosticReceiverCase $case.id
                        }
                    } elseif ($routeMatrix) {
                        Invoke-RouteMatrixCase -Case $case.id -Workload {
                            & (Join-Path $PSScriptRoot 'Invoke-LocalTcpConnections.ps1') -Profile SMOKE -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $freeze.python -EvidenceDirectory (Join-Path $evidence $case.directory) -DiagnosticRedirectContext -DiagnosticConnectionCase 'connectex-32' -DiagnosticFixtureCloseGuard -DiagnosticRouteCase $case.id
                        }
                    } else {
                        & (Join-Path $PSScriptRoot 'Invoke-LocalTcpConnections.ps1') -Profile SMOKE -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $freeze.python -EvidenceDirectory (Join-Path $evidence $case.directory) -DiagnosticRedirectContext -DiagnosticConnectionCase $case.id -DiagnosticFixtureCloseGuard
                    }
                    $case.status='CONTROLLER_RETURNED'
                } catch {$case.status='FAILED';throw}
            }
            $matrix.status='COMPLETED'
        } elseif ($receipt.method -in @('redirect-context-probes-v3','redirect-kernel-context-v4')) {
            & (Join-Path $PSScriptRoot 'Invoke-LocalTcpConnections.ps1') -Profile SMOKE -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $freeze.python -EvidenceDirectory $workloadEvidence -DiagnosticRedirectContext -DiagnosticConnectionCase 'connectex-32' -DiagnosticFixtureCloseGuard
        } else {
            & (Join-Path $PSScriptRoot 'Invoke-LocalTcpConnections.ps1') -Profile SMOKE -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $freeze.python -EvidenceDirectory $workloadEvidence -DiagnosticRedirectContext
        }
        $run.status='CONTROLLER_RETURNED'
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;if ($matrix) {$matrix.status='FAILED';$matrix.error=$run.error};throw}
    finally {
        if ($matrix) {
            $matrix | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'matrix-manifest.json') -Encoding UTF8
            & $freeze.python (Join-Path $root $(if ($externalPair) {'src/pb_tcp_external_receiver_report.py'} elseif ($routeMatrix) {'src/pb_tcp_route_matrix_report.py'} else {'src/pb_tcp_redirect_context_matrix_report.py'})) --evidence-directory $evidence
            $run['matrix_report_exit_code']=$LASTEXITCODE
            if ($LASTEXITCODE -ne 0 -and $run.status -ne 'FAILED') {$run.status='FAILED';$run.error='REDIRECT_CONTEXT_MATRIX_CAPTURE_INCOMPLETE'}
        }
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('Diagnostic results / Диагностические результаты: '+$evidence)
    }
    if ($run.status -eq 'FAILED') {throw $run.error}
} finally {
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
