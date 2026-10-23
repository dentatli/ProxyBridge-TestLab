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
if (-not $DriverPath) {
    $DriverPath=Join-Path $folder 'ProxyBridgeDrv.sys'
    if ($Contract -eq 'driver' -and -not (Test-Path -LiteralPath $DriverPath -PathType Leaf)) {
        # Read installation configuration only; do not query/start the service.
        $registered=Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ProxyBridgeDrv' -Name ImagePath -ErrorAction SilentlyContinue
        if ($registered) {
            $DriverPath=([string]$registered).Trim().Trim('"')
            if ($DriverPath.StartsWith('\??\')) { $DriverPath=$DriverPath.Substring(4) }
            if ($DriverPath.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)) { $DriverPath=Join-Path $env:SystemRoot $DriverPath.Substring(12) }
            elseif ($DriverPath.StartsWith('%SystemRoot%\',[StringComparison]::OrdinalIgnoreCase)) { $DriverPath=Join-Path $env:SystemRoot $DriverPath.Substring(13) }
            elseif ($DriverPath.StartsWith('System32\',[StringComparison]::OrdinalIgnoreCase)) { $DriverPath=Join-Path $env:SystemRoot $DriverPath }
        }
    }
}
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
$cliOutputContract='upstream'
$kitName=$(if ($Contract -eq 'driver') {'driver-63be0eb-testlab-cli'} else {'v4.0.0-release-testlab-cli'})
$kitPath=Join-Path $root ('artifacts/product-builds/'+$kitName+'/product.env')
if (Test-Path -LiteralPath $kitPath -PathType Leaf) {
    $known=Import-DotEnv -Path $kitPath
    $cliComponent=@($identity.components | Where-Object id -eq 'cli')
    if ($cliComponent.Count -eq 1 -and $known.ContainsKey('PB_EXPECTED_PROXYBRIDGE_CLI_SHA256') -and
        $cliComponent[0].sha256 -ieq $known['PB_EXPECTED_PROXYBRIDGE_CLI_SHA256']) { $cliOutputContract='testlab-unbuffered-v1' }
    $keys=@{cli='PB_EXPECTED_PROXYBRIDGE_CLI_SHA256';core='PB_EXPECTED_PROXYBRIDGE_CORE_SHA256';driver='PB_EXPECTED_DRIVER_SHA256';'windivert-dll'='PB_EXPECTED_WINDIVERT_DLL_SHA256';'windivert-driver'='PB_EXPECTED_WINDIVERT_DRIVER_SHA256'}
    $recognized=$identity.files_observed
    foreach ($component in $identity.components) {
        $key=$keys[$component.id]
        if (-not $known.ContainsKey($key) -or $component.sha256 -ine $known[$key]) { $recognized=$false }
    }
}
$olderVersion=$false
$versions=[Collections.Generic.List[version]]::new()
foreach ($component in $identity.components) {
    if ($component.id -in @('cli','core')) {
        foreach ($text in @($component.file_version,$component.product_version)) {
            if ($text -match '^\s*(\d+)\.(\d+)(?:\.(\d+))?') {
                $patch=if($Matches[3]){[int]$Matches[3]}else{0}
                $parsed=[version]::new([int]$Matches[1],[int]$Matches[2],$patch)
                $versions.Add($parsed)
                if ($parsed -lt [version]'4.0.0') { $olderVersion=$true }
            }
        }
    }
}
$detectedVersion=if($versions.Count){($versions|Sort-Object|Select-Object -First 1).ToString()}else{''}
$versionEvidence=if($detectedVersion){'file-version-metadata'}else{'unavailable'}
if($Contract -eq 'v4.0.0' -and -not $detectedVersion){
    $adapters=Get-Content -LiteralPath (Join-Path $root 'config/product-cli-adapters.json') -Raw | ConvertFrom-Json
    if($adapters.schema_version -ne 1 -or $adapters.minimum_version -ne '4.0.0'){throw 'PRODUCT_ADAPTER_CATALOG_INVALID'}
    $cliHash=($identity.components|Where-Object id -eq 'cli').sha256
    $coreHash=($identity.components|Where-Object id -eq 'core').sha256
    $pair=@($adapters.known_cli_core_pairs|Where-Object {$_.cli_sha256 -ceq $cliHash -and $_.core_sha256 -ceq $coreHash})
    if($pair.Count -eq 1){$detectedVersion=[string]$pair[0].version;$versionEvidence='official-release-component-hashes'}
}
$adapter=if($olderVersion){$null}elseif($Contract -eq 'driver'){'wfp-cli-v1'}elseif(-not $detectedVersion){$null}elseif([version]$detectedVersion -lt [version]'4.1.0'){'windivert-4.0-cli-v1'}else{'windivert-4.1-cli-v1'}
$status=$(if ($olderVersion) {'UNSUPPORTED_BEFORE_4_0_0'} elseif (@($identity.components | Where-Object status -eq 'UNREADABLE').Count -gt 0) {'FILES_UNREADABLE'} elseif (-not $identity.files_observed) {'FILES_INCOMPLETE'} elseif ($recognized) {'KNOWN_BENCHMARK_FILES'} else {'FILES_OBSERVED_COMPATIBILITY_PENDING'})
[ordered]@{
    schema_version=1;status=$status;observed_at_utc=$identity.observed_at_utc
    declared_contract=$Contract;product_label=$(if ($Contract -eq 'v4.0.0') {'WinDivert'} else {'Driver WFP'})
    product_version=$detectedVersion;adapter_id=$adapter;minimum_version='4.0.0';version_evidence=$versionEvidence;version_metadata_supported=($versions.Count -gt 0 -and -not $olderVersion)
    files_observed=$identity.files_observed;recognized_benchmark_files=$recognized
    cli_output_contract=$cliOutputContract
    supported_version_verified=$recognized;source_commit_verified=$false;runtime_ready=$false
    product_started=$false;traffic_generated=$false;driver_state_observed=$false
    scope='files-on-disk';components=$identity.components;bundle_sha256=$identity.bundle_sha256
} | ConvertTo-Json -Depth 12 -Compress
