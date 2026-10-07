#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvPath,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [switch]$AllowDriverRegistration
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AllowDriverRegistration) { throw 'DRIVER_REGISTRATION_NOT_AUTHORIZED' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'DRIVER_REGISTRATION_REQUIRES_ELEVATION' }
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/Env.psm1')
Import-Module (Join-Path $root 'modules/ProductBuild.psm1')
Import-Module (Join-Path $root 'modules/InterceptionState.psm1')
$environment = Import-DotEnv -Path $EnvPath
if (-not $environment.ContainsKey('PB_PROXYBRIDGE_SERVICE') -or $environment['PB_PROXYBRIDGE_SERVICE'] -cne 'ProxyBridgeDrv') { throw 'DRIVER_REGISTRATION_SERVICE_NAME_INVALID' }
$identity = Get-ProductBuildIdentity -Environment $environment -Contract driver
if (-not $identity.files_verified) { throw 'DRIVER_REGISTRATION_FILES_NOT_VERIFIED' }
$driverPath = [IO.Path]::GetFullPath($environment['PB_DRIVER_PATH'])
$cliDirectory = Split-Path -Parent $environment['PB_PROXYBRIDGE_CLI_EXE']
if (-not [string]::Equals($driverPath, [IO.Path]::GetFullPath((Join-Path $cliDirectory 'ProxyBridgeDrv.sys')), [StringComparison]::OrdinalIgnoreCase)) { throw 'DRIVER_REGISTRATION_NOT_BESIDE_CLI' }
$signature = Get-AuthenticodeSignature -LiteralPath $driverPath
if ($signature.Status -ne 'Valid') { throw 'DRIVER_REGISTRATION_SIGNATURE_NOT_VALID' }
$receipt = [ordered]@{
    schema_version=1; started_at_utc=[DateTime]::UtcNow.ToString('o'); status='NOT_COMPLETED'
    service_name='ProxyBridgeDrv'; driver_path=$driverPath; expected_driver_sha256=$environment['PB_EXPECTED_DRIVER_SHA256']
    created=$false; driver_load_requested=$false; product_start_requested=$false; registry_only=$true
    interception_cleanup_verified=$false; version_switch_ready=$false; reason=''
}
try {
    # Read-only interception observation before touching SCM. Service may be absent.
    $before = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    if (-not $before.wfp_objects.query_complete -or -not $before.wfp_objects.no_known_objects_observed) { throw 'DRIVER_REGISTRATION_WFP_STATE_UNSETTLED' }
    if ($before.windivert.configured -and (-not $before.windivert.capture_complete -or $before.windivert.observed_handle_count -gt 0)) { throw 'DRIVER_REGISTRATION_WINDIVERT_CONFLICT' }
    $processes = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
    if ($processes.Count) { throw 'DRIVER_REGISTRATION_PRODUCT_PROCESS_PRESENT' }
    if ($before.wfp.service_exists -eq $true) {
        if ($before.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $before.wfp.service_state -ne 'Stopped') { throw 'DRIVER_REGISTRATION_EXISTING_SERVICE_CONFLICT' }
        $receipt.status = 'EXISTING_REGISTRATION_VERIFIED'
    } elseif ($before.wfp.status -eq 'SERVICE_MISSING') {
        $sc = Join-Path $env:SystemRoot 'System32/sc.exe'
        # Kernel ImagePath is a file path, not a quoted executable command line.
        $scOutput = & $sc create ProxyBridgeDrv type= kernel start= demand binPath= $driverPath DisplayName= 'ProxyBridge WFP' 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'DRIVER_REGISTRATION_CREATE_FAILED' }
        $receipt.created = $true
        $after = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
        if ($after.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $after.wfp.service_state -ne 'Stopped') { throw 'DRIVER_REGISTRATION_READBACK_FAILED' }
        $receipt.status = 'REGISTERED_NOT_LOADED'
    } else { throw 'DRIVER_REGISTRATION_STATE_UNOBSERVED' }
} catch {
    $receipt.status='FAILED'
    $receipt.reason=$_.Exception.Message
    throw
} finally {
    $receipt.completed_at_utc=[DateTime]::UtcNow.ToString('o')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReceiptPath))) -Force
    $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
}
Write-Output $receipt.status
