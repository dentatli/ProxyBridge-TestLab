#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BindingPath,[switch]$RestoreOwnedDriver)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$binding=Get-Content -LiteralPath $BindingPath -Raw | ConvertFrom-Json
if($binding.product_contract -ne 'v4.0.0'){throw 'TRAFFIC_WINDIVERT_CONTRACT_REQUIRED'}
Import-Module (Join-Path $binding.root 'modules/InterceptionState.psm1') -ErrorAction Stop
function Assert-BoundFile([string]$Path,[string]$Expected) {
    if($Expected -notmatch '^[a-fA-F0-9]{64}$' -or -not(Test-Path -LiteralPath $Path -PathType Leaf) -or
        ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Expected){throw 'TRAFFIC_IMMUTABLE_FILE_CHANGED'}
}
Assert-BoundFile $binding.driver $binding.driver_sha256
$loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
$processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe','ProxyBridgeSvc.exe'))
if($RestoreOwnedDriver -and -not $loaded.known_interception_driver_names_absent){
    $claim=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $BindingPath) 'driver-ownership.json') -Raw | ConvertFrom-Json
    $exitVerified=$claim.cli_cleanup_verified -or ($claim.PSObject.Properties.Name -contains 'cli_exit_verified' -and $claim.cli_exit_verified -eq $true)
    $identityVerified=$claim.cli_ready -or ($claim.PSObject.Properties.Name -contains 'cli_path_verified' -and $claim.cli_path_verified -eq $true)
    if($claim.id -ne $binding.id -or $claim.product_contract -ne 'v4.0.0' -or -not $claim.off_before -or
        -not $identityVerified -or -not $exitVerified -or $claim.driver_sha256 -ine $binding.driver_sha256 -or
        $processes.Count -ne 0 -or -not $loaded.query_complete -or
        @($loaded.known_interception_drivers | Where-Object {$_ -ine 'WinDivert64.sys'}).Count -ne 0){throw 'TRAFFIC_WINDIVERT_RESTORE_OWNERSHIP_NOT_CONFIRMED'}
    # Driver teardown can finish after the owned CLI exits. Observe its bounded
    # settlement before opening the reflect observer, which can keep it loaded.
    $settleUntil=[DateTime]::UtcNow.AddSeconds(5)
    while(-not $loaded.known_interception_driver_names_absent -and [DateTime]::UtcNow -lt $settleUntil){
        Start-Sleep -Milliseconds 100
        $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    }
    if(-not $loaded.known_interception_driver_names_absent){
    $ctl=Join-Path $binding.root 'bin/tools/windivert-2.2.2/windivertctl.exe'
    $dll=Join-Path (Split-Path -Parent $ctl) 'WinDivert.dll'
    $environment=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $environment['PB_WINDIVERT_CTL_EXE']=$ctl
    function Get-BoundHash([string]$Path){
        $matches=@($binding.source_hashes.PSObject.Properties|Where-Object {[string]::Equals([IO.Path]::GetFullPath($_.Name),[IO.Path]::GetFullPath($Path),[StringComparison]::OrdinalIgnoreCase)})
        if($matches.Count -ne 1){throw 'TRAFFIC_OBSERVER_BINDING_NOT_UNIQUE'}
        return [string]$matches[0].Value
    }
    $environment['PB_EXPECTED_WINDIVERT_CTL_SHA256']=Get-BoundHash $ctl
    $environment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']=Get-BoundHash $dll
    $handles=Get-WinDivertHandleObservation -Environment $environment -TimeoutMs 5000
    if(-not $handles.capture_complete -or $handles.observed_handle_count -ne 0){throw 'TRAFFIC_WINDIVERT_HANDLES_NOT_CLEAR'}
    $services=@(Get-CimInstance Win32_SystemDriver -OperationTimeoutSec 5 | Where-Object Name -match '^WinDivert')
    if($services.Count -ne 1){throw 'TRAFFIC_WINDIVERT_SERVICE_NOT_UNIQUE'}
    $service=$services[0]
    $path=([string]$service.PathName).Trim().Trim('"')
    if($path.StartsWith('\??\')){$path=$path.Substring(4)}
    if(-not [string]::Equals([IO.Path]::GetFullPath($path),[IO.Path]::GetFullPath($binding.driver),[StringComparison]::OrdinalIgnoreCase)){throw 'TRAFFIC_WINDIVERT_SERVICE_PATH_CHANGED'}
    Assert-BoundFile $path $binding.driver_sha256
    # Only restore the exact driver loaded from this attempt's bound files,
    # after its owned CLI exited cleanly and the observer found zero handles.
    # Do not delete/reconfigure services or stop foreign product processes.
    try {
        Stop-Service -Name $service.Name -ErrorAction Stop
        $remaining=Get-Service -Name $service.Name -ErrorAction SilentlyContinue
        if($remaining){$remaining.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10))}
    } catch {
        # The service may disappear while its already scheduled teardown wins
        # this race. Only a fresh complete loaded-driver observation can accept it.
        $settleUntil=[DateTime]::UtcNow.AddSeconds(5)
        do {
            $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
            if($loaded.query_complete -and $loaded.known_interception_driver_names_absent){break}
            Start-Sleep -Milliseconds 100
        } while([DateTime]::UtcNow -lt $settleUntil)
        if(-not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent){throw}
    }
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    }
}
$wfp=Get-WfpServiceState -Name ProxyBridgeDrv -AllowProductRuntime
$objects=Get-WfpObjectObservation -TimeoutMs 5000
$off=($wfp.state -in @('Stopped','MISSING')) -and $objects.query_complete -and $objects.no_known_objects_observed -and
    $loaded.query_complete -and $loaded.known_interception_driver_names_absent -and $processes.Count -eq 0
[ordered]@{off_verified=[bool]$off;service_state=$wfp.state;file_verified=$true;no_known_wfp_objects=$objects.no_known_objects_observed;
    loaded_query_complete=$loaded.query_complete;known_driver_names_absent=$loaded.known_interception_driver_names_absent;
    product_process_count=$processes.Count;scope='WinDivert-selected-file-owned-SCM-loaded-names-and-known-WFP-objects';loaded_binary_verified=$false}|ConvertTo-Json -Compress
if(-not $off){exit 2}
exit 0
