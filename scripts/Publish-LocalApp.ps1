[CmdletBinding()]
param([string]$Version='0.3.0-local-preview.58',[string]$OutputRoot='', [string]$PythonDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?$') {throw 'RELEASE_VERSION_INVALID'}
if (-not $OutputRoot) {$OutputRoot=Join-Path $root 'artifacts/releases'}
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$prefix=$output+'\'
$destination=Join-Path $output ('ProxyBridge-TestLab-'+$Version+'-win-x64')
$stage=Join-Path $output ('.stage-local-'+[guid]::NewGuid().ToString('N'))
foreach($path in @($stage,$destination)) {
    if (-not [IO.Path]::GetFullPath($path).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {throw 'RELEASE_PATH_OUTSIDE_OUTPUT'}
}
if(Test-Path -LiteralPath $destination) {throw 'RELEASE_DESTINATION_ALREADY_EXISTS'}

if(-not $PythonDirectory) {$PythonDirectory=Join-Path $env:LOCALAPPDATA 'Programs/Python/Python311'}
$python=Join-Path $PythonDirectory 'python.exe'
if(-not(Test-Path -LiteralPath $python)) {throw 'RELEASE_PYTHON_311_REQUIRED'}
$abi=& $python -B -c 'import sys; print(sys.version_info.major,sys.version_info.minor,sep=chr(46))'
if($LASTEXITCODE -ne 0 -or $abi -ne '3.11') {throw 'RELEASE_PYTHON_311_REQUIRED'}

function Assert-RegularPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while($current) {
        if((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'RELEASE_REPARSE_POINT_REFUSED'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Copy-PublicFile([string]$Relative) {
    if([IO.Path]::IsPathRooted($Relative) -or @($Relative -split '[\\/]' | Where-Object {$_ -in @('..','.','')}).Count) {throw 'RELEASE_SOURCE_PATH_INVALID'}
    $source=Join-Path $root $Relative
    Assert-RegularPath $source
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)) {throw "RELEASE_REQUIRED_FILE_MISSING: $Relative"}
    $target=Join-Path $stage $Relative
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
    [IO.File]::Copy(('\\?\'+[IO.Path]::GetFullPath($source)),('\\?\'+[IO.Path]::GetFullPath($target)))
}
function Copy-RuntimeTree([string]$Source,[string]$Target) {
    Assert-RegularPath $Source
    $null=New-Item -ItemType Directory -Path $Target -Force
    foreach($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
        if($item.Name -in @('__pycache__','.pytest_cache','site-packages','test','tests')) {continue}
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'RELEASE_REPARSE_POINT_REFUSED'}
        $to=Join-Path $Target $item.Name
        if($item.PSIsContainer) {Copy-RuntimeTree $item.FullName $to}
        elseif($item.Extension -notin @('.pyc','.pyo','.obj','.zip')) {Copy-Item -LiteralPath $item.FullName -Destination $to}
    }
}

$null=New-Item -ItemType Directory -Path $stage -Force
try {
    & (Join-Path $root 'scripts/Build-CoreHost.ps1')
    if($LASTEXITCODE -ne 0) {throw 'CORE_HOST_BUILD_FAILED'}
    & dotnet publish (Join-Path $root 'ui/ProxyBridge.TestLab.Ui/ProxyBridge.TestLab.Ui.csproj') -c Release -r win-x64 --self-contained true --source https://api.nuget.org/v3/index.json --nologo -o (Join-Path $stage 'app')
    if($LASTEXITCODE -ne 0) {throw 'LOCAL_APP_PUBLISH_FAILED'}
    $engineTarget=Join-Path $stage 'bin/runtime/traffic-engine'
    & dotnet publish (Join-Path $root 'src/ProxyBridge.TestLab.TrafficEngine/ProxyBridge.TestLab.TrafficEngine.csproj') -c Release -r win-x64 --self-contained true --source https://api.nuget.org/v3/index.json --nologo -o $engineTarget
    if($LASTEXITCODE -ne 0) {throw 'TRAFFIC_ENGINE_PUBLISH_FAILED'}
    foreach($alias in @('pb_testlab_origin.exe','pb_testlab_worker.exe')) {
        Copy-Item -LiteralPath (Join-Path $engineTarget 'ProxyBridge.TestLab.TrafficEngine.exe') -Destination (Join-Path $engineTarget $alias)
    }
    # Only tracked public configuration/modules are included. Never enumerate
    # or copy the research source tree, captures, kits, profiles or secrets.
    $tracked=@(& git -C $root ls-files -- modules config scenarios src/trafficlab vendor)
    if($LASTEXITCODE -ne 0 -or -not $tracked.Count) {throw 'RELEASE_PUBLIC_INVENTORY_FAILED'}
    foreach($relative in $tracked) {Copy-PublicFile $relative}
    foreach($relative in @(
        'Run-WfpMatrix.ps1','LICENSE','scripts/Export-UiCatalog.ps1','scripts/Inspect-ProductSelection.ps1',
        'scripts/Invoke-TrafficLabRun.ps1','scripts/Assert-TrafficLabIdle.ps1','scripts/Assert-WinDivertTrafficIdle.ps1','scripts/Set-TrafficWfpDevice.ps1','scripts/Initialize-LocalFirewall.ps1',
        'bin/tools/windivert-2.2.2/windivertctl.exe','bin/tools/windivert-2.2.2/WinDivert.dll','bin/tools/windivert-2.2.2/LICENSE',
        'packaging/Start-ProxyBridge-TestLab.ps1','packaging/Stop-ProxyBridge-TestLab.ps1','packaging/Repair-ProxyBridge-TestLab.ps1',
        'src/pb_service_query.cs','src/pb_loaded_drivers.cs','src/pb_core_host.c','bin/pb_core_host.exe','bin/pb_console_host.exe','bin/pb_wfp_state.exe'
    )) {Copy-PublicFile $relative}
    [IO.File]::Copy((Join-Path $root 'packaging/LOCAL-README.md'),(Join-Path $stage 'README.md'))
    $pythonTarget=Join-Path $stage 'bin/runtime/python'
    $null=New-Item -ItemType Directory -Path $pythonTarget -Force
    foreach($name in @('python.exe','python3.dll','python311.dll','vcruntime140.dll','vcruntime140_1.dll','LICENSE.txt')) {
        $source=Join-Path $PythonDirectory $name;Assert-RegularPath $source
        Copy-Item -LiteralPath $source -Destination (Join-Path $pythonTarget $name)
    }
    foreach($name in @('Lib','DLLs')) {Copy-RuntimeTree (Join-Path $PythonDirectory $name) (Join-Path $pythonTarget $name)}
    [IO.File]::WriteAllText((Join-Path $stage 'Start.cmd'), '@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\Start-ProxyBridge-TestLab.ps1"'+"`r`n",[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION.txt'),$Version+"`r`n",[Text.UTF8Encoding]::new($false))
    $sourceCommit=(& git -C $root rev-parse HEAD).Trim()
    if($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[a-f0-9]{40}$') {throw 'RELEASE_SOURCE_REVISION_UNAVAILABLE'}
    $manifest=[ordered]@{schema_version=1;name='ProxyBridge TestLab';version=$Version;source_commit=$sourceCommit;platform='win-x64';scope='local';controller_self_contained=$true;local_python_included=$true;transport_engine='csharp-transport-v1';transport_self_contained=$true;product_binaries_included=$false;runtime_validation='NOT_RUN_ON_THIS_REVISION';catalog_scenarios=51;ui_checks=10;baseline_commit='d5b51f3'}
    [IO.File]::WriteAllText((Join-Path $stage 'MANIFEST.json'),($manifest|ConvertTo-Json)+"`r`n",[Text.UTF8Encoding]::new($false))
    $sums=@(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
        (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()+'  '+$_.FullName.Substring($stage.Length+1).Replace('\','/')
    })
    [IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS.txt'),($sums -join "`r`n")+"`r`n",[Text.UTF8Encoding]::new($false))
    [IO.Directory]::Move($stage,$destination)
    [pscustomobject]@{package_path=$destination;version=$Version;scope='local';runtime_verified=$false}
}
finally {
    # Both paths were resolved and checked against the explicitly selected output root above.
    if(Test-Path -LiteralPath $stage) {Remove-Item -LiteralPath $stage -Recurse -Force}
}
