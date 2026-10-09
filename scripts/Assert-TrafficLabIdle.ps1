#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BindingPath,[switch]$RestoreOwnedDriver)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$binding=Get-Content -LiteralPath $BindingPath -Raw | ConvertFrom-Json
Import-Module (Join-Path $binding.root 'modules/InterceptionState.psm1') -ErrorAction Stop
$environment=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$environment['PB_PROXYBRIDGE_SERVICE']='ProxyBridgeDrv'
$environment['PB_DRIVER_PATH']=[string]$binding.driver
$environment['PB_EXPECTED_DRIVER_SHA256']=[string]$binding.driver_sha256
$state=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
$loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
$processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
if($RestoreOwnedDriver -and $state.wfp.service_state -eq 'Running'){
    $claim=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $BindingPath) 'driver-ownership.json') -Raw | ConvertFrom-Json
    if($claim.id -ne $binding.id -or -not $claim.off_before -or -not $claim.cli_ready -or -not $claim.cli_cleanup_verified -or
        $claim.driver_sha256 -ine $binding.driver_sha256 -or -not $state.wfp.file_hash_matches -or -not $state.wfp.configured_file_matches -or
        $processes.Count -ne 0 -or -not $loaded.query_complete -or
        @($loaded.known_interception_drivers | Where-Object {$_ -ine 'ProxyBridgeDrv.sys'}).Count -ne 0){throw 'TRAFFIC_DRIVER_RESTORE_OWNERSHIP_NOT_CONFIRMED'}
    # Only the exact service observed Stopped before this owned CLI session is restored.
    # No installation, signing, boot changes, or other service/driver operations.
    Stop-Service -Name ProxyBridgeDrv -ErrorAction Stop
    (Get-Service -Name ProxyBridgeDrv).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10))
    $state=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
}
$off=$state.current_driver_preparation_allowed -and $state.wfp_detachment_observed -and $state.wfp.service_state -eq 'Stopped' -and
    $loaded.query_complete -and $loaded.known_interception_driver_names_absent -and $processes.Count -eq 0
[ordered]@{off_verified=[bool]$off;service_state=$state.wfp.service_state;file_verified=$state.wfp.file_hash_matches;
    no_known_wfp_objects=$state.wfp_objects.no_known_objects_observed;loaded_query_complete=$loaded.query_complete;
    known_driver_names_absent=$loaded.known_interception_driver_names_absent;product_process_count=$processes.Count;
    scope='SCM-file-identity-known-WFP-objects-and-loaded-driver-names';loaded_binary_verified=$false} | ConvertTo-Json -Compress
if (-not $off) { exit 2 }
