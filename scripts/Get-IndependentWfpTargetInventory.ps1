[CmdletBinding()]
param()

# Local inventory only. Does not configure remoting, drivers, debugging or boot options.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$os=Get-CimInstance Win32_OperatingSystem
$version=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$services=@(Get-CimInstance Win32_Service -Filter "Name='sshd' OR Name='WinRM'" |
    Select-Object Name,State,StartMode)
$drivers=@(Get-CimInstance Win32_SystemDriver -Filter "Name LIKE '%WFPSampler%' OR Name LIKE '%ProxyBridge%'" |
    Select-Object Name,State,StartMode,PathName)
$secureBoot=$null
$secureBootReadError=$null
try {
    $secureBoot=Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled
} catch {$secureBootReadError=$_.Exception.Message}
$ubr=$null
if ($version.PSObject.Properties['UBR']) {$ubr=$version.UBR}
$displayVersion=$null
if ($version.PSObject.Properties['DisplayVersion']) {$displayVersion=$version.DisplayVersion}
[ordered]@{
    method='independent-wfp-target-inventory-v1'
    collected_at_utc=[DateTime]::UtcNow.ToString('o')
    computer_name=$env:COMPUTERNAME
    os=[ordered]@{
        caption=$os.Caption
        version=$os.Version
        build=$os.BuildNumber
        ubr=$ubr
        display_version=$displayVersion
        architecture=$os.OSArchitecture
        boot_time_utc=$os.LastBootUpTime.ToUniversalTime().ToString('o')
    }
    free_memory_bytes=([uint64]$os.FreePhysicalMemory * 1024)
    elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    remoting_services=$services
    matching_driver_services=$drivers
    secure_boot_registry_value=$secureBoot
    secure_boot_read_error=$secureBootReadError
    read_only=$true
    product_started=$false
    traffic_generated=$false
    configuration_changed=$false
} | ConvertTo-Json -Depth 6
