[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$driverDetails=@()
foreach ($driver in @(Get-CimInstance Win32_SystemDriver -Filter "Name LIKE '%ProxyBridge%' OR Name LIKE '%WFPSampler%'")) {
    $driverPath=$driver.PathName.Trim('"')
    if ($driverPath.StartsWith('\??\')) {$driverPath=$driverPath.Substring(4)}
    if ($driverPath.StartsWith('\SystemRoot\')) {$driverPath=Join-Path $env:windir $driverPath.Substring(12)}
    $signature=Get-AuthenticodeSignature -LiteralPath $driverPath
    $driverDetails+=[ordered]@{
        name=$driver.Name;state=$driver.State;start_mode=$driver.StartMode;path=$driverPath
        sha256=(Get-FileHash -LiteralPath $driverPath -Algorithm SHA256).Hash.ToLowerInvariant()
        signature_status=[string]$signature.Status
        signer_subject=$(if ($signature.SignerCertificate) {$signature.SignerCertificate.Subject} else {$null})
        signer_thumbprint=$(if ($signature.SignerCertificate) {$signature.SignerCertificate.Thumbprint} else {$null})
        signer_in_machine_root=$(if ($signature.SignerCertificate) {Test-Path ('Cert:\LocalMachine\Root\'+$signature.SignerCertificate.Thumbprint)} else {$false})
        signer_in_machine_publishers=$(if ($signature.SignerCertificate) {Test-Path ('Cert:\LocalMachine\TrustedPublisher\'+$signature.SignerCertificate.Thumbprint)} else {$false})
    }
}
$productProcesses=@(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -like '*ProxyBridge*' -or $_.ProcessName -like '*WFPSampler*'} |
    Select-Object ProcessName,Id,Path)
$hlkServices=@(Get-CimInstance Win32_Service -Filter "Name='WTTService' OR Name LIKE '%HLK%'" |
    Select-Object Name,State,StartMode)
$bootText=@(& "$env:windir\System32\bcdedit.exe" /enum '{current}' 2>&1)
$bootExit=$LASTEXITCODE
$selectedBootFlags=@($bootText | Where-Object {[string]$_ -match '^\s*(testsigning|debug|nointegritychecks)\s'})
[ordered]@{
    method='independent-wfp-prerequisites-v1'
    computer_name=$env:COMPUTERNAME
    drivers=$driverDetails
    product_processes=$productProcesses
    hlk_services=$hlkServices
    boot_read_exit_code=$bootExit
    selected_boot_flags=$selectedBootFlags
    # An absent line is left unclassified. No debugging keys or complete BCD dump.
    driver_verifier_change_performed=$false
    driver_change_performed=$false
    configuration_changed=$false
    product_started=$false
    traffic_generated=$false
} | ConvertTo-Json -Depth 7
