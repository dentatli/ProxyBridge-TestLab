Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'InterceptionState.psm1')

# Opt-in lifecycle for the installed root-enumerated product package. Never
# changes package, trust or BCD; both the devnode and service file must match.
function Set-VerifiedPnpDriverState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][string]$DriverPath,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$Sha256,
        [Parameter(Mandatory)][ValidateSet('Running','Stopped')][string]$State,
        [switch]$AllowProductRuntime
    )
    if (-not $AllowProductRuntime) { throw 'PRODUCT_RUNTIME_NOT_ALLOWED' }
    if ($InstanceId -ine 'ROOT\INTERCEPTSUITE_PROXYBRIDGE\0000') { throw 'PNP_PRODUCT_INSTANCE_INVALID' }
    $store = [regex]::Escape((Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'))
    if ($DriverPath -notmatch ('^' + $store + '\\proxybridgedrv\.inf_amd64_[a-f0-9]+\\ProxyBridgeDrv\.sys$')) { throw 'PNP_DRIVERSTORE_PATH_INVALID' }
    $service = Get-WfpServiceState -Name ProxyBridgeDrv -AllowProductRuntime
    if (-not $service.exists -or $service.service_type -ne 1 -or $service.state -notin @('Running','Stopped')) { throw 'PNP_SERVICE_UNSETTLED' }
    if (-not [string]::Equals((Resolve-PnpServicePath $service.path), $DriverPath, [StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $DriverPath).Hash -ine $Sha256) { throw 'PNP_DRIVER_IDENTITY_MISMATCH' }
    if ((Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction Stop).Data -ine 'ProxyBridgeDrv') { throw 'PNP_DEVICE_SERVICE_MISMATCH' }
    if ((Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName DEVPKEY_Device_DriverInfPath -ErrorAction Stop).Data -notmatch '^oem[0-9]+\.inf$') { throw 'PNP_PUBLISHED_INF_NOT_OBSERVED' }
    if (@(Get-Process ProxyBridge,ProxyBridge_CLI -ErrorAction SilentlyContinue).Count) { throw 'PNP_PRODUCT_PROCESS_REMAINS' }
    Set-Service ProxyBridgeDrv -StartupType $(if ($State -eq 'Running') { 'Manual' } else { 'Disabled' })
    $output = & pnputil.exe /restart-device $InstanceId 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('PNP_RESTART_FAILED: ' + ($output -join ' ')) }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $after = Get-WfpServiceState -Name ProxyBridgeDrv -AllowProductRuntime
        $problem = (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction Stop).Data
        if ($after.state -eq $State -and $problem -eq $(if ($State -eq 'Running') { 0 } else { 32 })) { return }
        Start-Sleep -Milliseconds 100
    } while ($timer.ElapsedMilliseconds -lt 10000)
    throw 'PNP_REQUESTED_STATE_NOT_OBSERVED'
}

function Resolve-PnpServicePath([string]$Value) {
    $path = $Value.Trim('"')
    if ($path.StartsWith('\??\')) { $path = $path.Substring(4) }
    if ($path.StartsWith('\SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) { $path = Join-Path $env:SystemRoot $path.Substring(12) }
    return [IO.Path]::GetFullPath($path)
}

Export-ModuleMember -Function Set-VerifiedPnpDriverState
