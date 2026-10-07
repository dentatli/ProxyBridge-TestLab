Set-StrictMode -Version Latest

function Test-ProductBuildAbsolutePath {
    param([string]$Path)
    # IsPathRooted alone also accepts C:relative and \current-drive-relative.
    return -not [string]::IsNullOrWhiteSpace($Path) -and $Path -match '^(?:[a-zA-Z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+(?:[\\/]|$))'
}

# Inventory files on disk without loading the DLL or executing the product.
# Matching configured hashes establishes file identity, not source provenance.
function Get-ProductBuildIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [ValidateSet('driver','v4.0.0')][string]$Contract = 'driver'
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $components = [System.Collections.Generic.List[object]]::new()
    $cliPath = ''
    if ($Environment.ContainsKey('PB_PROXYBRIDGE_CLI_EXE')) { $cliPath = [string]$Environment['PB_PROXYBRIDGE_CLI_EXE'] }
    if (-not (Test-ProductBuildAbsolutePath $cliPath)) {
        throw 'PRODUCT_BUILD_CLI_ABSOLUTE_PATH_REQUIRED'
    }
    $cliPath = [System.IO.Path]::GetFullPath($cliPath)
    $directory = [System.IO.Path]::GetDirectoryName($cliPath)
    $definitions = @(
        @('cli', $cliPath, 'PB_EXPECTED_PROXYBRIDGE_CLI_SHA256'),
        @('core', (Join-Path $directory 'ProxyBridgeCore.dll'), 'PB_EXPECTED_PROXYBRIDGE_CORE_SHA256')
    )
    if ($Contract -eq 'driver') {
        $driverPath = ''
        if ($Environment.ContainsKey('PB_DRIVER_PATH')) { $driverPath = [string]$Environment['PB_DRIVER_PATH'] }
        $definitions += ,@('driver', $driverPath, 'PB_EXPECTED_DRIVER_SHA256')
    }
    else {
        $definitions += ,@('windivert-dll', (Join-Path $directory 'WinDivert.dll'), 'PB_EXPECTED_WINDIVERT_DLL_SHA256')
        $definitions += ,@('windivert-driver', (Join-Path $directory 'WinDivert64.sys'), 'PB_EXPECTED_WINDIVERT_DRIVER_SHA256')
    }
    if ($Environment.ContainsKey('PB_PROXYBRIDGE_EXE') -and -not [string]::IsNullOrWhiteSpace([string]$Environment['PB_PROXYBRIDGE_EXE'])) {
        $guiPath = [string]$Environment['PB_PROXYBRIDGE_EXE']
        $definitions += ,@('gui', $guiPath, 'PB_EXPECTED_PROXYBRIDGE_EXE_SHA256')
        if (Test-ProductBuildAbsolutePath $guiPath) {
            $guiDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($guiPath))
            if (-not [string]::Equals($directory, $guiDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
                $issues.Add('PRODUCT_BUILD_GUI_CLI_DIRECTORY_MISMATCH')
            }
        }
    }

    foreach ($definition in $definitions) {
        $id = [string]$definition[0]
        $path = [string]$definition[1]
        $hashKey = [string]$definition[2]
        $expected = ''
        if ($Environment.ContainsKey($hashKey)) { $expected = [string]$Environment[$hashKey] }
        $component = [pscustomobject][ordered]@{
            id=$id; file_name=''; sha256=''; expected_sha256=''; size_bytes=$null
            file_version=''; product_version=''; version_metadata_status='NOT_READ'; status='NOT_READ'
        }
        if ($expected -match '^[A-Fa-f0-9]{64}$') { $component.expected_sha256 = $expected.ToLowerInvariant() }
        try {
            if (-not (Test-ProductBuildAbsolutePath $path)) {
                $component.status = 'INVALID_PATH'
            }
            elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $component.status = 'MISSING' }
            else {
                $file = Get-Item -LiteralPath $path -ErrorAction Stop
                $component.file_name = $file.Name
                $component.size_bytes = $file.Length
                $component.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $component.status = $(if (-not $component.expected_sha256) { 'EXPECTED_HASH_MISSING_OR_INVALID' }
                    elseif ($component.sha256 -ne $component.expected_sha256) { 'HASH_MISMATCH' } else { 'HASH_MATCH' })
                try {
                    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
                    $component.file_version = [string]$version.FileVersion
                    $component.product_version = [string]$version.ProductVersion
                    $component.version_metadata_status = $(if ($component.file_version -or $component.product_version) { 'OBSERVED' } else { 'ABSENT' })
                }
                catch { $component.version_metadata_status = 'UNREADABLE' }
            }
        }
        catch { $component.status = 'UNREADABLE' }
        if ($component.status -ne 'HASH_MATCH') { $issues.Add("PRODUCT_BUILD_$($id.ToUpperInvariant().Replace('-', '_'))_$($component.status)") }
        $components.Add($component)
    }

    $sourceCommit = ''
    if ($Environment.ContainsKey('PB_PROXYBRIDGE_SOURCE_COMMIT')) {
        $sourceCommit = [string]$Environment['PB_PROXYBRIDGE_SOURCE_COMMIT']
        if ($sourceCommit -and $sourceCommit -notmatch '^[a-fA-F0-9]{40}$') {
            $issues.Add('PRODUCT_BUILD_SOURCE_COMMIT_INVALID')
            $sourceCommit = ''
        }
    }
    $cliVariant = 'upstream'
    if ($Environment.ContainsKey('PB_PROXYBRIDGE_CLI_VARIANT')) { $cliVariant = [string]$Environment['PB_PROXYBRIDGE_CLI_VARIANT'] }
    if ($cliVariant -notin @('upstream','testlab-unbuffered-v1')) { $issues.Add('PRODUCT_BUILD_CLI_VARIANT_INVALID') }
    $complete = @($components | Where-Object { -not $_.sha256 }).Count -eq 0
    $fingerprint = ''
    if ($complete) {
        $canonical = (@($components | Sort-Object id | ForEach-Object { "$($_.id):$($_.sha256)" }) -join "`n") + "`n"
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try { $fingerprint = ([System.BitConverter]::ToString($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '').ToLowerInvariant() }
        finally { $hasher.Dispose() }
    }
    return [pscustomobject][ordered]@{
        schema_version=1; observed_at_utc=[DateTime]::UtcNow.ToString('o'); scope='files-on-disk'
        selected_contract=$Contract.ToLowerInvariant(); contract_verified=$false
        status=$(if ($issues.Count -eq 0) { 'FILES_VERIFIED' } else { 'FILES_NOT_VERIFIED' })
        files_observed=$complete; files_verified=($issues.Count -eq 0)
        bundle_sha256=$fingerprint; components=$components.ToArray(); issues=$issues.ToArray()
        declared_source_commit=$sourceCommit.ToLowerInvariant(); source_commit_verified=$false
        declared_cli_variant=$cliVariant; cli_variant_verified=$false; source_event_stream_complete=$false
        loaded_modules_verified=$false; route_verified=$false
    }
}

Export-ModuleMember -Function Get-ProductBuildIdentity
