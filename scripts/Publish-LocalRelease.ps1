[CmdletBinding()]
param(
    [string]$Version = '0.1.0-rc1',
    [string]$OutputRoot,
    [string]$ClientExecutablePath,
    [switch]$AllowMissingClient,
    [switch]$CreateZip
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?$') { throw 'RELEASE_VERSION_INVALID' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repositoryRoot 'artifacts\releases' }
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$packageName = "ProxyBridge-TestLab-$Version-win-x64"
$destination = Join-Path $OutputRoot $packageName
if (Test-Path -LiteralPath $destination) { throw 'RELEASE_DESTINATION_ALREADY_EXISTS' }
if ([string]::IsNullOrWhiteSpace($ClientExecutablePath)) { $ClientExecutablePath = Join-Path $repositoryRoot 'bin\pb_net_client.exe' }

$dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet -PathType Leaf)) { throw 'DOTNET_SDK_NOT_FOUND' }
$runtimePackSource = 'https://api.nuget.org/v3/index.json'
$null = New-Item -ItemType Directory -Path $OutputRoot -Force
$staging = Join-Path $OutputRoot ('.stage-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $staging

function Copy-PublicTree([string]$RelativePath) {
    $source = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) { throw "RELEASE_SOURCE_MISSING: $RelativePath" }
    $item = Get-Item -LiteralPath $source
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "RELEASE_REPARSE_POINT_REFUSED: $RelativePath" }
    if (-not $item.PSIsContainer) {
        $target = Join-Path $staging $RelativePath
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        Copy-Item -LiteralPath $item.FullName -Destination $target
        return
    }

    $sourcePrefix = $item.FullName.TrimEnd('\') + '\'
    foreach ($file in @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File)) {
        if ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "RELEASE_REPARSE_POINT_REFUSED: $($file.FullName)" }
        $inside = $file.FullName.Substring($sourcePrefix.Length)
        $segments = $inside.Split('\')
        if ($segments -contains '__pycache__' -or $segments -contains '.pytest_cache' -or $file.Extension -in @('.pyc','.pyo')) { continue }
        $target = Join-Path (Join-Path $staging $RelativePath) $inside
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}

function Assert-ProtocolWorkerBundle {
    $bundleRoot = Join-Path $repositoryRoot 'bin\protocol-worker'
    $required = @(
        'runtime/python/python.exe',
        'worker/pb_protocol_worker.py',
        'worker/plugins/manifest.json',
        'config/protocol-evidence-contract.json',
        'BUNDLE-MANIFEST.json'
    )
    $sumsPath = Join-Path $bundleRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { throw 'PROTOCOL_RUNTIME_SUMS_MISSING' }
    $bytes = [System.IO.File]::ReadAllBytes($sumsPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'PROTOCOL_RUNTIME_SUMS_BOM_FORBIDDEN' }
    $rootPrefix = [System.IO.Path]::GetFullPath($bundleRoot).TrimEnd('\') + '\'
    $declared = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in @([System.Text.Encoding]::UTF8.GetString($bytes) -split "`r?`n" | Where-Object { $_.Length -gt 0 })) {
        if ($line -notmatch '^([A-Fa-f0-9]{64})  ([^\\]+)$') { throw 'PROTOCOL_RUNTIME_SUMS_FORMAT_INVALID' }
        $relative = [string]$Matches[2]
        if ([System.IO.Path]::IsPathRooted($relative) -or @($relative -split '/').Where({ $_ -in @('', '.', '..') }).Count -gt 0 -or -not $declared.Add($relative)) {
            throw 'PROTOCOL_RUNTIME_SUMS_PATH_INVALID'
        }
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $bundleRoot $relative.Replace('/', '\')))
        if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
            ((Get-Item -LiteralPath $candidate).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw 'PROTOCOL_RUNTIME_FILE_INVALID'
        }
        if (-not [string]::Equals((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash, [string]$Matches[1], [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'PROTOCOL_RUNTIME_HASH_MISMATCH'
        }
    }
    foreach ($relative in $required) {
        if (-not $declared.Contains($relative)) { throw 'PROTOCOL_RUNTIME_REQUIRED_FILE_UNDECLARED' }
    }
}

try {
    $appTarget = Join-Path $staging 'app'
    & $dotnet publish (Join-Path $repositoryRoot 'ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj') -c Release -r win-x64 --self-contained true --source $runtimePackSource --nologo -o $appTarget
    if ($LASTEXITCODE -ne 0) { throw "RELEASE_PUBLISH_FAILED exit=$LASTEXITCODE" }

    Assert-ProtocolWorkerBundle
    foreach($path in @('README.md','Run-WfpMatrix.ps1','modules','config','scenarios','src','docs','scripts\Export-UiCatalog.ps1','scripts\Build-Harness.ps1','tests\fixtures','packaging','bin\protocol-worker')) { Copy-PublicTree $path }
    $clientIncluded = Test-Path -LiteralPath $ClientExecutablePath -PathType Leaf
    if (-not $clientIncluded -and -not $AllowMissingClient) { throw 'CLIENT_BINARY_REQUIRED' }
    if ($clientIncluded) {
        $binTarget = Join-Path $staging 'bin'
        $null = New-Item -ItemType Directory -Path $binTarget -Force
        Copy-Item -LiteralPath $ClientExecutablePath -Destination (Join-Path $binTarget 'pb_net_client.exe')
    }
    [System.IO.File]::WriteAllText((Join-Path $staging 'VERSION.txt'), $Version + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

    $manifest = [pscustomobject][ordered]@{
        schema_version=1;name='ProxyBridge TestLab';version=$Version;platform='win-x64';controller_self_contained=$true
        client_included=$clientIncluded;bundled_client_ready=$clientIncluded;protocol_worker_included=$true;protocol_worker_integrity_verified=$true
        real_runtime_prerequisites='configured and verified in the UI'
        supported_server=@('Debian','Ubuntu');service_manager='systemd';ssh_authentication='private-key-only'
        exclusions=@('.env','credentials','generated profiles','evidence','.git','product binaries')
    }
    [System.IO.File]::WriteAllText((Join-Path $staging 'MANIFEST.json'), (($manifest|ConvertTo-Json -Depth 10) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    $sumLines = foreach($file in @(Get-ChildItem -LiteralPath $staging -Recurse -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object FullName)){
        $relative=$file.FullName.Substring($staging.Length+1).Replace('\','/')
        "$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
    }
    [System.IO.File]::WriteAllText((Join-Path $staging 'SHA256SUMS.txt'), (($sumLines -join [Environment]::NewLine)+[Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    [System.IO.Directory]::Move($staging,$destination)
    if($CreateZip){
        $zipPath=Join-Path $OutputRoot ($packageName+'.zip')
        if(Test-Path -LiteralPath $zipPath){throw 'RELEASE_ZIP_ALREADY_EXISTS'}
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($destination,$zipPath,[System.IO.Compression.CompressionLevel]::Optimal,$false)
    }
    [pscustomobject]@{package_path=$destination;zip_path=$(if($CreateZip){$zipPath}else{''});client_included=$clientIncluded;version=$Version}
}
finally {
    if(Test-Path -LiteralPath $staging){[System.IO.Directory]::Delete($staging,$true)}
}
