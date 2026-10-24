#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BindingPath,[Parameter(Mandatory)][ValidateSet('Enable','Disable')][string]$Action)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$binding=Get-Content -LiteralPath $BindingPath -Raw|ConvertFrom-Json
if($binding.product_contract -ne 'driver' -or $binding.runtime_mode -ne 'local'){throw 'TRAFFIC_PNP_LOCAL_WFP_ONLY'}
$leasePath=Join-Path (Split-Path -Parent $BindingPath) 'wfp-device-lease.json'
if($Action -eq 'Disable' -and -not(Test-Path -LiteralPath $leasePath)){
    '{"applicable":false,"reason":"no-owned-device-lease"}';exit 0
}
Import-Module (Join-Path $binding.root 'modules/InterceptionState.psm1') -ErrorAction Stop
$environment=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$environment['PB_PROXYBRIDGE_SERVICE']='ProxyBridgeDrv'
$environment['PB_DRIVER_PATH']=[string]$binding.driver
$environment['PB_EXPECTED_DRIVER_SHA256']=[string]$binding.driver_sha256
$state=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
if(-not $state.wfp.file_hash_matches -or -not $state.wfp.configured_file_matches){throw 'TRAFFIC_PNP_DRIVER_IDENTITY_CHANGED'}
$devices=@(Get-PnpDevice -ErrorAction Stop|Where-Object InstanceId -like 'ROOT\INTERCEPTSUITE_PROXYBRIDGE*')
if($devices.Count -eq 0 -and $Action -eq 'Enable'){'{"applicable":false,"reason":"legacy-service"}';exit 0}
if($devices.Count -ne 1){throw 'TRAFFIC_PNP_DEVICE_NOT_UNIQUE'}
$device=$devices[0]
$id=[string]$device.InstanceId
$service=(Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Service' -ErrorAction Stop).Data
$hardware=@((Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop).Data)
if($service -ne 'ProxyBridgeDrv' -or $hardware -notcontains 'ROOT\InterceptSuite_ProxyBridge'){throw 'TRAFFIC_PNP_DEVICE_IDENTITY_CHANGED'}
$problem=[int](Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data
if(@(Get-Process -Name ProxyBridge,ProxyBridge_CLI,ProxyBridgeSvc,pb_core_host -ErrorAction SilentlyContinue).Count){throw 'TRAFFIC_PNP_PRODUCT_STILL_RUNNING'}
if($Action -eq 'Enable'){
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    if($problem -ne 22 -or $state.wfp.service_state -ne 'Stopped' -or -not $state.current_driver_preparation_allowed -or
        -not $state.wfp_detachment_observed -or -not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent){throw 'TRAFFIC_PNP_OFF_NOT_VERIFIED'}
    if(Test-Path -LiteralPath $leasePath){throw 'TRAFFIC_PNP_LEASE_ALREADY_EXISTS'}
    $lease=[ordered]@{id=$binding.id;instance_id=$id;driver_sha256=$binding.driver_sha256;driver_path=$binding.driver;disabled_before=$true;state='ENABLING'}
    [IO.File]::WriteAllText($leasePath,($lease|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
}else{
    $lease=Get-Content -LiteralPath $leasePath -Raw|ConvertFrom-Json
    if($lease.id -ne $binding.id -or $lease.instance_id -ne $id -or -not $lease.disabled_before -or
        $lease.driver_sha256 -ine $binding.driver_sha256 -or $lease.driver_path -ine $binding.driver){throw 'TRAFFIC_PNP_RESTORE_OWNERSHIP_NOT_CONFIRMED'}
    if($problem -notin @(0,22)){throw 'TRAFFIC_PNP_UNEXPECTED_DEVICE_PROBLEM'}
    if($problem -ne 22){Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop}
}
$deadline=[DateTime]::UtcNow.AddSeconds(5)
do{
    $problem=[int](Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data
    $serviceState=Get-WfpServiceState -Name ProxyBridgeDrv -AllowProductRuntime
    if(($Action -eq 'Enable' -and $problem -eq 0 -and $serviceState.state -eq 'Running') -or
       ($Action -eq 'Disable' -and $problem -eq 22 -and $serviceState.state -eq 'Stopped')){break}
    Start-Sleep -Milliseconds 100
}while([DateTime]::UtcNow -lt $deadline)
if(($Action -eq 'Enable' -and ($problem -ne 0 -or $serviceState.state -ne 'Running')) -or
   ($Action -eq 'Disable' -and ($problem -ne 22 -or $serviceState.state -ne 'Stopped'))){throw 'TRAFFIC_PNP_STATE_NOT_VERIFIED'}
if($Action -eq 'Disable'){
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $objects=Get-WfpObjectObservation -TimeoutMs 5000
    if(-not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent -or -not $objects.query_complete -or -not $objects.no_known_objects_observed){throw 'TRAFFIC_PNP_DETACHMENT_NOT_VERIFIED'}
}
$lease.state=if($Action -eq 'Enable'){'ENABLED'}else{'RESTORED_DISABLED'}
[IO.File]::WriteAllText($leasePath,($lease|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
[ordered]@{applicable=$true;action=$Action;instance_id=$id;problem_code=$problem;service_state=$serviceState.state;verified=$true;scope='owned-selected-root-PnP-device-once-per-queue'}|ConvertTo-Json -Compress
