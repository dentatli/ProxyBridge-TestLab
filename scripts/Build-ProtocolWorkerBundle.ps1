[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PythonRuntimeRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$BundleName = 'protocol-worker-runtime'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'modules\ProtocolDependencies.psm1') -Force
$sourceRoot = [System.IO.Path]::GetFullPath($PythonRuntimeRoot)
$outputRootFull = [System.IO.Path]::GetFullPath($OutputRoot)
if ($BundleName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'PROTOCOL_WORKER_BUNDLE_NAME_INVALID' }
$destination = Join-Path $outputRootFull $BundleName
if (Test-Path -LiteralPath $destination) { throw 'PROTOCOL_WORKER_BUNDLE_DESTINATION_EXISTS' }
$sourcePython = Join-Path $sourceRoot 'python.exe'
if (-not (Test-Path -LiteralPath $sourcePython -PathType Leaf)) { throw 'PROTOCOL_WORKER_SOURCE_PYTHON_MISSING' }

$versionOutput = & $sourcePython -I -B -c "import struct,sys; print('%d.%d|%d' % (sys.version_info[0],sys.version_info[1],struct.calcsize('P')*8))"
if ($LASTEXITCODE -ne 0 -or [string]$versionOutput -notmatch '^(\d+)\.(\d+)\|(\d+)$') { throw 'PROTOCOL_WORKER_SOURCE_PYTHON_QUERY_FAILED' }
$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$architecture = [int]$Matches[3]
if ($major -ne 3 -or $minor -lt 10 -or $minor -gt 14) { throw 'PROTOCOL_WORKER_SOURCE_PYTHON_VERSION_UNSUPPORTED' }
if ($architecture -ne 64) { throw 'PROTOCOL_WORKER_SOURCE_PYTHON_ARCHITECTURE_UNSUPPORTED' }

$null = New-Item -ItemType Directory -Path $outputRootFull -Force
$staging = Join-Path $outputRootFull ('.protocol-worker-stage-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $staging

function Copy-BundleFile([string]$Source, [string]$RelativeTarget) {
    $item = Get-Item -LiteralPath $Source
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "PROTOCOL_WORKER_BUNDLE_REPARSE_POINT_REFUSED: $Source" }
    $target = Join-Path $staging $RelativeTarget
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    Copy-Item -LiteralPath $item.FullName -Destination $target
}

function Copy-BundleTree([string]$SourceDirectory, [string]$RelativeTargetRoot, [string[]]$ExcludedSegments, [string[]]$ExcludedExtensions) {
    $rootItem = Get-Item -LiteralPath $SourceDirectory
    if ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "PROTOCOL_WORKER_BUNDLE_REPARSE_POINT_REFUSED: $SourceDirectory" }
    $prefix = $rootItem.FullName.TrimEnd('\') + '\'
    foreach ($file in @(Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -File | Sort-Object FullName)) {
        if ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "PROTOCOL_WORKER_BUNDLE_REPARSE_POINT_REFUSED: $($file.FullName)" }
        $relative = $file.FullName.Substring($prefix.Length)
        $segments = @($relative.Split('\'))
        if (@($segments | Where-Object { $ExcludedSegments -contains $_ }).Count -gt 0) { continue }
        if ($ExcludedExtensions -contains $file.Extension.ToLowerInvariant()) { continue }
        if ($file.BaseName -match '_d$') { continue }
        Copy-BundleFile $file.FullName (Join-Path $RelativeTargetRoot $relative)
    }
}

try {
    foreach ($name in @('python.exe','python3.dll',("python{0}{1}.dll" -f $major,$minor),'vcruntime140.dll','vcruntime140_1.dll','LICENSE.txt')) {
        $source = Join-Path $sourceRoot $name
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-BundleFile $source (Join-Path 'runtime\python' $name) }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $staging ("runtime\python\python{0}{1}.dll" -f $major,$minor)))) { throw 'PROTOCOL_WORKER_BUNDLE_RUNTIME_DLL_MISSING' }
    Copy-BundleTree (Join-Path $sourceRoot 'DLLs') 'runtime\python\DLLs' @('__pycache__') @('.pdb','.pyc','.pyo')
    Copy-BundleTree (Join-Path $sourceRoot 'Lib') 'runtime\python\Lib' @('__pycache__','site-packages','test','tests','idlelib','tkinter','turtledemo') @('.pdb','.pyc','.pyo')
    Copy-BundleTree (Join-Path $repositoryRoot 'src\protocol_worker') 'worker' @('__pycache__') @('.pdb','.pyc','.pyo')
    foreach ($relative in @('config\protocol-worker-runtime.json','config\protocol-evidence-contract.json')) { Copy-BundleFile (Join-Path $repositoryRoot $relative) $relative }
    $dependencyLockPath = Join-Path $repositoryRoot 'vendor\protocol-dependencies.lock.json'
    $dependencyLock = Import-ProtocolDependencyLock -Path $dependencyLockPath
    $null = Expand-ProtocolDependencyWheelhouse -Lock $dependencyLock -WheelhouseRoot (Join-Path $repositoryRoot 'vendor\wheelhouse') `
        -Platform win-x64 -Destination (Join-Path $staging 'worker\_vendor')
    Copy-BundleFile $dependencyLockPath 'config\protocol-dependencies.lock.json'

    $verification = Join-Path $staging '.verification'
    $null = New-Item -ItemType Directory -Path $verification
    $planPath = Join-Path $verification 'plan.json'
    $outputPath = Join-Path $verification 'evidence.jsonl'
    $plan = [pscustomobject][ordered]@{
        schema_version=1;run_id='bundle-selftest';scenario_id='protocol-worker-selftest';attempt_id='attempt-1';flow_id='flow-1'
        plugin_id='contract-selftest';protocol_family='native-tcp';transport='NONE';operation_timeout_ms=5000
        parameters=[pscustomobject]@{mode='offline'};expected=[pscustomobject]@{result='PASS'};capabilities=@()
    }
    [System.IO.File]::WriteAllText($planPath, (($plan | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    $bundledPython = Join-Path $staging 'runtime\python\python.exe'
    $entrypoint = Join-Path $staging 'worker\pb_protocol_worker.py'
    $manifest = Join-Path $staging 'worker\plugins\manifest.json'
    $selfTestOutput = & $bundledPython -I -B $entrypoint --plan $planPath --output-jsonl $outputPath --manifest $manifest 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]($selfTestOutput -join '') -ne 'PROTOCOL_WORKER_OK records=1') { throw 'PROTOCOL_WORKER_BUNDLE_SELF_TEST_FAILED' }
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'PROTOCOL_WORKER_BUNDLE_SELF_TEST_EVIDENCE_MISSING' }
    [System.IO.Directory]::Delete($verification, $true)

    $bundleManifest = [pscustomobject][ordered]@{
        schema_version=1;runtime_id='proxybridge-protocol-worker';python_version=("{0}.{1}" -f $major,$minor);architecture='x64'
        entrypoint='worker/pb_protocol_worker.py';plugin_manifest='worker/plugins/manifest.json';self_test_passed=$true
        dependency_source='locked-offline-wheelhouse';dependency_set=[string]$dependencyLock.dependency_set
        dependency_lock='config/protocol-dependencies.lock.json';network_installation_allowed=$false
    }
    [System.IO.File]::WriteAllText((Join-Path $staging 'BUNDLE-MANIFEST.json'), (($bundleManifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    $sumLines = foreach ($file in @(Get-ChildItem -LiteralPath $staging -Recurse -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($staging.Length + 1).Replace('\','/')
        "$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
    }
    [System.IO.File]::WriteAllText((Join-Path $staging 'SHA256SUMS.txt'), (($sumLines -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    [System.IO.Directory]::Move($staging, $destination)
    [pscustomobject][ordered]@{ bundle_path=$destination; python_version=("{0}.{1}" -f $major,$minor); architecture='x64'; self_test_passed=$true; file_count=@(Get-ChildItem -LiteralPath $destination -Recurse -File).Count }
}
finally {
    if (Test-Path -LiteralPath $staging) {
        $resolvedStaging = [System.IO.Path]::GetFullPath($staging)
        $safePrefix = $outputRootFull.TrimEnd('\') + '\.protocol-worker-stage-'
        if (-not $resolvedStaging.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'PROTOCOL_WORKER_STAGE_DELETE_REFUSED' }
        [System.IO.Directory]::Delete($resolvedStaging, $true)
    }
}
