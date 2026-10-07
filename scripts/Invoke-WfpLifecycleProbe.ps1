#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvPath,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [switch]$AllowProductRuntime
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AllowProductRuntime) { throw 'PRODUCT_RUNTIME_NOT_ALLOWED' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'LIFECYCLE_PROBE_REQUIRES_ELEVATION' }
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter')) { Import-Module (Join-Path $root ('modules/' + $module + '.psm1')) }
$environment = Import-DotEnv -Path $EnvPath
$null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force
$receipt = [ordered]@{schema_version=1;status='NOT_COMPLETED';started_at_utc=[DateTime]::UtcNow.ToString('o');traffic_generated=$false;startup_shutdown_verified=$false;driver_stop_observed=$false;interception_cleanup_verified=$false;version_switch_ready=$false;reason=''}
$serviceStartAttempted = $false
try {
    $identity = Get-ProductBuildIdentity -Environment $environment -Contract driver
    $identity | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'product-build.json') -Encoding UTF8
    if (-not $identity.files_verified) { throw 'LIFECYCLE_FILES_NOT_VERIFIED' }
    $runtimeConfig = Get-Content -LiteralPath (Join-Path $root 'config/runtime.json') -Raw | ConvertFrom-Json
    $plan = New-RuntimeEnvironmentPlan -Environment $environment -RuntimeConfig $runtimeConfig -ProductOnly
    if ($plan.service_bootstrap -ne 'driver-service') { throw 'LIFECYCLE_PROBE_REQUIRES_HEADLESS_KIT' }
    $plan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'preparation-plan.json') -Encoding UTF8
    $before = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    $before | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'interception-before.json') -Encoding UTF8
    if (-not $before.current_driver_preparation_allowed -or $before.wfp.service_state -ne 'Stopped') { throw 'LIFECYCLE_REQUIRES_VERIFIED_STOPPED_DRIVER' }
    $active = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
    if ($active.Count) { throw 'LIFECYCLE_PRODUCT_PROCESS_CONFLICT' }
    $adapter = New-SystemRuntimeEnvironmentAdapter
    $serviceStartAttempted = $true
    $preparation = Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $adapter -AllowProductRuntime
    $preparation | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'preparation-result.json') -Encoding UTF8
    if (-not $preparation.prepared) { throw 'LIFECYCLE_PREPARATION_FAILED' }
    # A single DIRECT rule for an unused process satisfies upstream CLI's
    # nonempty-profile requirement. No proxy config, worker or client is started.
    $profile = [ordered]@{Version='1.0';LocalhostViaProxy=$false;IsTrafficLoggingEnabled=$false;ProxyConfigs=@();ProxyRules=@([ordered]@{ProcessName='ProxyBridge_TestLab_Lifecycle_Probe.exe';TargetHosts='*';TargetPorts='*';TargetDomains='';Protocol='TCP';Action='DIRECT';ProxyConfigId=0;IsEnabled=$true})}
    $profilePath = Join-Path $EvidenceDirectory 'lifecycle.pbprofile'
    $profile | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $profilePath -Encoding UTF8
    $variant = $(if ($environment.ContainsKey('PB_PROXYBRIDGE_CLI_VARIANT')) { $environment['PB_PROXYBRIDGE_CLI_VARIANT'] } else { 'upstream' })
    $cliPlan = New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $profilePath -ProductProfileContract driver -CliVariant $variant -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 5000
    $sink = {param($value) $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'cli-lifecycle.json') -Encoding UTF8}.GetNewClosure()
    $lifecycle = Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime -EvidenceSink $sink
    $receipt.startup_shutdown_verified = $lifecycle.ready -and $lifecycle.graceful_stop -and $lifecycle.post_stop_verified -and $lifecycle.process_result.output_capture_complete -and $lifecycle.process_result.exit_code -eq 0
    if (-not $receipt.startup_shutdown_verified) { throw 'LIFECYCLE_START_STOP_NOT_VERIFIED' }
    $receipt.status = 'START_STOP_OBSERVED'
} catch {
    $receipt.status='FAILED'
    $receipt.reason=$_.Exception.Message
} finally {
    if ($serviceStartAttempted) {
        try {
            $remaining = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
            if ($remaining.Count) { throw 'LIFECYCLE_PROCESS_REMAINS_BEFORE_DRIVER_STOP' }
            $afterCli = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
            if ($afterCli.wfp.status -ne 'SERVICE_FILE_VERIFIED') { throw 'LIFECYCLE_DRIVER_IDENTITY_CHANGED' }
            $controller = [ServiceProcess.ServiceController]::new('ProxyBridgeDrv')
            try {
                if ($controller.Status -eq [ServiceProcess.ServiceControllerStatus]::Running) { $controller.Stop() }
                $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(10))
            } finally { $controller.Dispose() }
            $after = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
            $after | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'interception-after.json') -Encoding UTF8
            $receipt.driver_stop_observed = $after.wfp.service_state -eq 'Stopped' -and $after.wfp_objects.query_complete -and $after.wfp_objects.no_known_objects_observed
            if (-not $receipt.driver_stop_observed) { throw 'LIFECYCLE_DRIVER_STOP_NOT_OBSERVED' }
        } catch { $receipt.status='FAILED'; $receipt.reason += '; cleanup: ' + $_.Exception.Message }
    }
    $receipt.completed_at_utc=[DateTime]::UtcNow.ToString('o')
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'lifecycle-receipt.json') -Encoding UTF8
}
if ($receipt.status -eq 'FAILED') { throw $receipt.reason }
Write-Output $receipt.status
