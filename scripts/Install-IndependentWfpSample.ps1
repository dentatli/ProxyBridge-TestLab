# Explicitly authorized independent diagnostic installation on PB-SUT.
# Windows 10+ non-PnP KMDF supports SCM installation, without INF/coinstaller.
param([string]$KitDirectory='C:\PB-Independent-Wfp-20261021-r1')
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PB-SUT'){throw 'TARGET_IDENTITY_DIFFERS'}
$kit=$KitDirectory
$manifest=Get-Content -LiteralPath "$kit\manifest.json" -Raw | ConvertFrom-Json
foreach($file in $manifest.files){
    if((Get-FileHash -LiteralPath (Join-Path $kit $file.name)).Hash.ToLowerInvariant() -ne $file.sha256){throw 'KIT_HASH_DIFFERS'}
}
$signature=Get-AuthenticodeSignature -LiteralPath "$kit\WFPSamplerCalloutDriver.sys"
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne '4544323109A45FC4761819E079BBDBD5E0BFE8D6'){throw 'SIGNATURE_DIFFERS'}
if(Get-Service WFPSampler -ErrorAction SilentlyContinue){throw 'SAMPLE_USER_SERVICE_ALREADY_EXISTS'}
$existingDriver=Get-CimInstance Win32_SystemDriver -Filter "Name='WFPSamplerCallouts'"
if($existingDriver){
    $existingPath=$existingDriver.PathName -replace '^\\\?\?\\',''
    if($existingPath -notin @('C:\PB-Independent-Wfp-20261021-r1\WFPSamplerCalloutDriver.sys','C:\PB-Independent-Wfp-20261021-r2\WFPSamplerCalloutDriver.sys')){throw 'EXISTING_DRIVER_NOT_OWNED'}
    if((Get-FileHash $existingPath).Hash -ne (Get-FileHash "$kit\WFPSamplerCalloutDriver.sys").Hash){throw 'EXISTING_DRIVER_HASH_DIFFERS'}
}
$before=@(Get-CimInstance Win32_SystemDriver -Filter "Name='ProxyBridgeDrv'" | Select-Object Name,State,StartMode,PathName)
$hlkBefore=@(Get-Service HLKsvc -ErrorAction SilentlyContinue | Select-Object Name,Status)
if(Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -like '*ProxyBridge*'){throw 'PRODUCT_PROCESS_STILL_RUNNING'}
if(-not(Test-Path -LiteralPath "$kit\product-before.json")){
    $before | ConvertTo-Json | Set-Content "$kit\product-before.json" -Encoding UTF8
}
if((Get-Service ProxyBridgeDrv -ErrorAction SilentlyContinue).Status -eq 'Running'){
    Stop-Service ProxyBridgeDrv -ErrorAction Stop
    (Get-Service ProxyBridgeDrv).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(15))
}
if(-not $existingDriver){
    $driverOutput=@(& sc.exe create WFPSamplerCallouts type= kernel start= demand error= normal binPath= "$kit\WFPSamplerCalloutDriver.sys" depend= Tcpip 2>&1)
    if($LASTEXITCODE -ne 0){throw "DRIVER_SERVICE_CREATE_FAILED:$($driverOutput -join ' ')"}
}
if((Get-Service WFPSamplerCallouts).Status -ne 'Running'){Start-Service WFPSamplerCallouts}
(Get-Service WFPSamplerCallouts).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
$serviceProcess=Start-Process -FilePath "$kit\WFPSamplerService.exe" -ArgumentList '-i' -WindowStyle Hidden -PassThru -RedirectStandardOutput "$kit\service-install.stdout.txt" -RedirectStandardError "$kit\service-install.stderr.txt"
if(-not $serviceProcess.WaitForExit(15000)){throw 'SAMPLE_SERVICE_INSTALL_TIMEOUT'}
# The official -i path enters StartServiceCtrlDispatcher after installation;
# inspect the actual installed service even if its console exit is 1063.
$service=Get-Service WFPSampler -ErrorAction Stop
$config=@(& sc.exe config WFPSampler start= demand 2>&1)
if($LASTEXITCODE -ne 0){throw 'SAMPLE_SERVICE_CONFIG_FAILED'}
Start-Service WFPSampler
(Get-Service WFPSampler).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
[ordered]@{status='INSTALLED';computer=$env:COMPUTERNAME;kit=$kit;service_install_exit=$serviceProcess.ExitCode;
    services=@(Get-CimInstance Win32_Service -Filter "Name='WFPSampler'" | Select-Object Name,State,StartMode,PathName);
    drivers=@(Get-CimInstance Win32_SystemDriver -Filter "Name='WFPSamplerCallouts' OR Name='ProxyBridgeDrv'" | Select-Object Name,State,StartMode,PathName);
    hlk_before=$hlkBefore;hlk_after=@(Get-Service HLKsvc -ErrorAction SilentlyContinue | Select-Object Name,Status);
    safe_boot_keys_created_by_official_service_installer=$true;trust_changed=$false;bcd_changed=$false;traffic_generated=$false
} | ConvertTo-Json -Depth 6
