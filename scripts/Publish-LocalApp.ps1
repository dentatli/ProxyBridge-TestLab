[CmdletBinding()]
param([string]$Version='0.2.0-local-preview',[string]$OutputRoot='', [string]$PythonDirectory='')
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
Import-Module (Join-Path $root 'modules/LocalRuntime.psm1')
if(-not $PythonDirectory) {$PythonDirectory=Split-Path -Parent (Get-LocalPythonExecutable -Root $root)}

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
    Copy-Item -LiteralPath $source -Destination $target
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
    & dotnet publish (Join-Path $root 'ui/ProxyBridge.TestLab.Ui/ProxyBridge.TestLab.Ui.csproj') -c Release -r win-x64 --self-contained true --source https://api.nuget.org/v3/index.json --nologo -o (Join-Path $stage 'app')
    if($LASTEXITCODE -ne 0) {throw 'LOCAL_APP_PUBLISH_FAILED'}
    # Only tracked public configuration/modules are included. Never enumerate
    # or copy the research source tree, captures, kits, profiles or secrets.
    $tracked=@(& git -C $root ls-files -- modules config scenarios)
    if($LASTEXITCODE -ne 0 -or -not $tracked.Count) {throw 'RELEASE_PUBLIC_INVENTORY_FAILED'}
    foreach($relative in $tracked) {Copy-PublicFile $relative}
    foreach($relative in @(
        'Run-WfpMatrix.ps1','LICENSE','scripts/Export-UiCatalog.ps1','scripts/Inspect-ProductSelection.ps1',
        'scripts/Invoke-PlannedBenchmark.ps1','scripts/Invoke-BenchmarkControllerHost.ps1','scripts/Invoke-LocalTcpRtt.ps1',
        'scripts/Invoke-LocalTcpBenchmark.ps1','scripts/Invoke-LocalTcpConnections.ps1','scripts/Invoke-LocalTcpLoadedRtt.ps1',
        'scripts/Invoke-LocalUdpBenchmark.ps1','scripts/Invoke-WfpLocalRouteProbe.ps1','scripts/Invoke-WfpUnruledComparison.ps1',
        'packaging/Start-ProxyBridge-TestLab.ps1','packaging/Stop-ProxyBridge-TestLab.ps1','packaging/Repair-ProxyBridge-TestLab.ps1',
        'src/pb_service_query.cs','src/pb_loaded_drivers.cs','src/pb_net_client.c','src/pb_net_endpoint.py','src/pb_pc_sampler.py',
        'src/pb_controlled_tcp_proxy.py','src/pb_controlled_udp_proxy.py','src/pb_tcp_nodelay_diagnostic.py','src/pb_proactor_close_guard.py',
        'src/pb_tcp_benchmark_report.py','src/pb_tcp_rtt_report.py','src/pb_tcp_loaded_rtt_report.py','src/pb_tcp_connections_report.py',
        'src/pb_tcp_three_mode_report.py','src/pb_tcp_data_scope.py','src/pb_udp_benchmark_report.py','src/pb_unruled_comparison_report.py',
        'src/pb_terminal_decode.py','src/pb_workload.py',
        'bin/pb_net_client.exe','bin/pb_console_host.exe','bin/pb_wfp_state.exe','bin/tcp-rtt/pb_tcp_rtt_client.exe','bin/tcp-rtt/build-receipt.json',
        'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe','bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe','bin/tools/ctstraffic-2.0.3.9/LICENSE',
        'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl',
        'bin/tools/psutil-7.2.2/psutil-7.2.2-cp37-abi3-win_amd64.whl',
        'bin/tools/windivert-2.2.2/windivertctl.exe','bin/tools/windivert-2.2.2/WinDivert.dll','bin/tools/windivert-2.2.2/LICENSE'
    )) {Copy-PublicFile $relative}
    Copy-RuntimeTree (Join-Path $root 'bin/tools/psutil-7.2.2/packages') (Join-Path $stage 'bin/tools/psutil-7.2.2/packages')
    Copy-RuntimeTree (Join-Path $root 'bin/terminal-decoder/packages') (Join-Path $stage 'bin/terminal-decoder/packages')
    $pythonTarget=Join-Path $stage 'bin/runtime/python'
    $null=New-Item -ItemType Directory -Path $pythonTarget -Force
    foreach($name in @('python.exe','python3.dll','python312.dll','vcruntime140.dll','vcruntime140_1.dll','LICENSE.txt')) {
        $source=Join-Path $PythonDirectory $name;Assert-RegularPath $source
        Copy-Item -LiteralPath $source -Destination (Join-Path $pythonTarget $name)
    }
    foreach($name in @('Lib','DLLs')) {Copy-RuntimeTree (Join-Path $PythonDirectory $name) (Join-Path $pythonTarget $name)}
    [IO.File]::WriteAllText((Join-Path $stage 'Start.cmd'), '@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\Start-ProxyBridge-TestLab.ps1"'+"`r`n",[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION.txt'),$Version+"`r`n",[Text.UTF8Encoding]::new($false))
    $sourceCommit=(& git -C $root rev-parse HEAD).Trim()
    if($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[a-f0-9]{40}$') {throw 'RELEASE_SOURCE_REVISION_UNAVAILABLE'}
    $manifest=[ordered]@{schema_version=1;name='ProxyBridge TestLab';version=$Version;source_commit=$sourceCommit;platform='win-x64';scope='local';controller_self_contained=$true;local_python_included=$true;product_binaries_included=$false;runtime_validation='PENDING_ADMINISTRATOR_ACCEPTANCE'}
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
