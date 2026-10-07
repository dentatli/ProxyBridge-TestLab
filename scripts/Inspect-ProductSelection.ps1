[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallationDirectory,
    [Parameter(Mandatory)][ValidateSet('driver','v4.0.0')][string]$Contract,
    [string]$DriverPath=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
# Use this host's Utility module: a .NET child may inherit PowerShell 7 module paths.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ProductBuild.psm1')
Import-Module (Join-Path $root 'modules/Env.psm1')

function Assert-LocalSelectionPath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path -match '[\x00-\x1f]') { throw 'LOCAL_ABSOLUTE_PATH_REQUIRED' }
    $full=[IO.Path]::GetFullPath($Path)
    $current=$full
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'SELECTION_REPARSE_POINT_NOT_SUPPORTED' }
        }
        $current=[IO.Path]::GetDirectoryName($current)
    }
    return $full
}

$folder=Assert-LocalSelectionPath $InstallationDirectory
if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'INSTALLATION_DIRECTORY_MISSING' }
if (-not $DriverPath) { $DriverPath=Join-Path $folder 'ProxyBridgeDrv.sys' }
$DriverPath=Assert-LocalSelectionPath $DriverPath
$environment=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$environment['PB_PROXYBRIDGE_CLI_EXE']=Join-Path $folder 'ProxyBridge_CLI.exe'
$environment['PB_DRIVER_PATH']=$DriverPath
$environment['PB_PROXYBRIDGE_CLI_VARIANT']='upstream'
# No expected hashes are invented: an observed fingerprint is not provenance.
$files=@($environment['PB_PROXYBRIDGE_CLI_EXE'],(Join-Path $folder 'ProxyBridgeCore.dll'))
if ($Contract -eq 'driver') { $files+= $DriverPath }
else { $files+=@((Join-Path $folder 'WinDivert.dll'),(Join-Path $folder 'WinDivert64.sys')) }
foreach ($file in $files) {
    $null=Assert-LocalSelectionPath $file
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        if ((Get-Item -LiteralPath $file).Length -gt 64MB) { throw 'SELECTION_COMPONENT_SIZE_LIMIT' }
    }
}
$identity=Get-ProductBuildIdentity -Environment $environment -Contract $Contract
$recognized=$false
$kitName=$(if ($Contract -eq 'driver') {'driver-63be0eb-testlab-cli'} else {'v4.0.0-release-testlab-cli'})
$kitPath=Join-Path $root ('artifacts/product-builds/'+$kitName+'/product.env')
if (Test-Path -LiteralPath $kitPath -PathType Leaf) {
    $known=Import-DotEnv -Path $kitPath
    $keys=@{cli='PB_EXPECTED_PROXYBRIDGE_CLI_SHA256';core='PB_EXPECTED_PROXYBRIDGE_CORE_SHA256';driver='PB_EXPECTED_DRIVER_SHA256';'windivert-dll'='PB_EXPECTED_WINDIVERT_DLL_SHA256';'windivert-driver'='PB_EXPECTED_WINDIVERT_DRIVER_SHA256'}
    $recognized=$identity.files_observed
    foreach ($component in $identity.components) {
        $key=$keys[$component.id]
        if (-not $known.ContainsKey($key) -or $component.sha256 -ine $known[$key]) { $recognized=$false }
    }
}
$olderVersion=$false
foreach ($component in $identity.components) {
    if ($component.id -in @('cli','core')) {
        foreach ($text in @($component.file_version,$component.product_version)) {
            if ($text -match '^\s*(\d+)\.(\d+)(?:\.(\d+))?') {
                if ([int]$Matches[1] -lt 4) { $olderVersion=$true }
            }
        }
    }
}
$status=$(if ($olderVersion) {'UNSUPPORTED_BEFORE_4_0_0'} elseif (@($identity.components | Where-Object status -eq 'UNREADABLE').Count -gt 0) {'FILES_UNREADABLE'} elseif (-not $identity.files_observed) {'FILES_INCOMPLETE'} elseif ($recognized) {'KNOWN_BENCHMARK_FILES'} else {'FILES_OBSERVED_COMPATIBILITY_PENDING'})
[ordered]@{
    schema_version=1;status=$status;observed_at_utc=$identity.observed_at_utc
    declared_contract=$Contract;product_label=$(if ($Contract -eq 'v4.0.0') {'4.0.0'} else {'driver'})
    files_observed=$identity.files_observed;recognized_benchmark_files=$recognized
    supported_version_verified=$recognized;source_commit_verified=$false;runtime_ready=$false
    product_started=$false;traffic_generated=$false;driver_state_observed=$false
    scope='files-on-disk';components=$identity.components;bundle_sha256=$identity.bundle_sha256
} | ConvertTo-Json -Depth 12 -Compress
