param(
    [Parameter(Mandatory=$true)][string]$KitDirectory,
    [string]$ExpectedPreviousDriverSha256='29d2d9735ea5729b7eaf5b98ce9eced195ba252f5c71a348ec3742d85c4dc815'
)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PB-SUT'){throw 'TARGET_IDENTITY_DIFFERS'}
if($KitDirectory -notmatch '^C:\\PB-Independent-Wfp-[a-zA-Z0-9-]+$'){throw 'KIT_PATH_NOT_OWNED'}
if((Get-Service ProxyBridgeDrv).Status -ne 'Stopped'){throw 'PRODUCT_DRIVER_RUNNING'}
foreach($name in 'WFPSampler','WFPSamplerCallouts'){
    if((Get-Service $name).Status -ne 'Stopped'){throw 'SAMPLE_MUST_BE_STOPPED'}
}
$manifest=Get-Content "$KitDirectory\manifest.json" -Raw | ConvertFrom-Json
foreach($entry in $manifest.files){
    $path=Join-Path $KitDirectory $entry.name
    if((Get-FileHash $path).Hash.ToLowerInvariant() -ne $entry.sha256){throw 'KIT_HASH_DIFFERS'}
    if((Get-AuthenticodeSignature $path).Status -ne 'Valid'){throw 'KIT_SIGNATURE_INVALID'}
}
$driver=Get-CimInstance Win32_SystemDriver -Filter "Name='WFPSamplerCallouts'"
$previousPath=$driver.PathName -replace '^\\\?\?\\',''
if($previousPath -notmatch '^C:\\PB-Independent-Wfp-[a-zA-Z0-9-]+\\WFPSamplerCalloutDriver.sys$'){throw 'PREVIOUS_DRIVER_NOT_OWNED'}
if((Get-FileHash $previousPath).Hash.ToLowerInvariant() -ne $ExpectedPreviousDriverSha256){throw 'PREVIOUS_DRIVER_HASH_DIFFERS'}
[ordered]@{path=$previousPath;sha256=$ExpectedPreviousDriverSha256} | ConvertTo-Json | Set-Content "$KitDirectory\previous-driver.json" -Encoding UTF8
$null=& sc.exe config WFPSamplerCallouts binPath= "$KitDirectory\WFPSamplerCalloutDriver.sys"
if($LASTEXITCODE -ne 0){throw 'DRIVER_CONFIG_FAILED'}
Start-Service WFPSamplerCallouts
(Get-Service WFPSamplerCallouts).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
Start-Service WFPSampler
(Get-Service WFPSampler).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
[ordered]@{status='VARIANT_RUNNING';kit=$KitDirectory;driver_path=(Get-CimInstance Win32_SystemDriver -Filter "Name='WFPSamplerCallouts'").PathName;driver_sha256=(Get-FileHash "$KitDirectory\WFPSamplerCalloutDriver.sys").Hash.ToLowerInvariant();services=@(Get-Service WFPSampler,WFPSamplerCallouts,ProxyBridgeDrv,HLKsvc | Select-Object Name,Status)} | ConvertTo-Json -Depth 5
