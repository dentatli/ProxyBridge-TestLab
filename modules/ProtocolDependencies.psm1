Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-ProtocolDependencyLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'PROTOCOL_DEPENDENCY_LOCK_MISSING' }
    try { $lock = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'PROTOCOL_DEPENDENCY_LOCK_INVALID' }
    if ([int]$lock.schema_version -ne 1 -or [string]$lock.dependency_set -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$' -or
        [bool]$lock.network_installation_allowed) { throw 'PROTOCOL_DEPENDENCY_LOCK_CONTRACT_INVALID' }
    $packageNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($package in @($lock.packages)) {
        if ([string]$package.name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or
            [string]$package.version -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$' -or
            [string]::IsNullOrWhiteSpace([string]$package.license) -or -not $packageNames.Add([string]$package.name)) {
            throw 'PROTOCOL_DEPENDENCY_PACKAGE_INVALID'
        }
    }
    if ($packageNames.Count -eq 0) { throw 'PROTOCOL_DEPENDENCY_PACKAGE_EMPTY' }
    $artifactKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($artifact in @($lock.artifacts)) {
        if (@('win-x64','linux-x64') -notcontains [string]$artifact.platform -or
            [string]$artifact.file -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*\.whl$' -or
            [string]$artifact.sha256 -notmatch '^[a-f0-9]{64}$' -or [long]$artifact.bytes -lt 1 -or
            -not $artifactKeys.Add("$($artifact.platform)/$($artifact.file)")) {
            throw 'PROTOCOL_DEPENDENCY_ARTIFACT_INVALID'
        }
    }
    foreach ($platform in @('win-x64','linux-x64')) {
        if (@($lock.artifacts | Where-Object platform -eq $platform).Count -ne $packageNames.Count) {
            throw 'PROTOCOL_DEPENDENCY_PLATFORM_SET_INCOMPLETE'
        }
    }
    return $lock
}

function Test-ProtocolDependencyWheelhouse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$WheelhouseRoot,
        [Parameter(Mandatory)][ValidateSet('win-x64','linux-x64')][string]$Platform
    )

    $platformRoot = [System.IO.Path]::GetFullPath((Join-Path $WheelhouseRoot $Platform))
    if (-not (Test-Path -LiteralPath $platformRoot -PathType Container) -or
        ((Get-Item -LiteralPath $platformRoot).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw 'PROTOCOL_DEPENDENCY_WHEELHOUSE_INVALID'
    }
    $rootPrefix = $platformRoot.TrimEnd('\') + '\'
    $expected = @($Lock.artifacts | Where-Object platform -eq $Platform | Sort-Object file)
    $actualNames = @(Get-ChildItem -LiteralPath $platformRoot -File | Sort-Object Name | ForEach-Object Name)
    if (@($expected).Count -ne $actualNames.Count -or
        @(Compare-Object -ReferenceObject @($expected | ForEach-Object file) -DifferenceObject $actualNames).Count -ne 0) {
        throw 'PROTOCOL_DEPENDENCY_WHEELHOUSE_SET_MISMATCH'
    }
    $verified = [System.Collections.Generic.List[object]]::new()
    foreach ($artifact in $expected) {
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $platformRoot ([string]$artifact.file)))
        if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
            ((Get-Item -LiteralPath $candidate).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw 'PROTOCOL_DEPENDENCY_WHEEL_INVALID'
        }
        $item = Get-Item -LiteralPath $candidate
        if ([long]$item.Length -ne [long]$artifact.bytes) { throw 'PROTOCOL_DEPENDENCY_WHEEL_SIZE_MISMATCH' }
        $actualHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
        if (-not [string]::Equals($actualHash, [string]$artifact.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'PROTOCOL_DEPENDENCY_WHEEL_HASH_MISMATCH'
        }
        $verified.Add([pscustomobject]@{ platform=$Platform; file=[string]$artifact.file; path=$candidate })
    }
    return $verified.ToArray()
}

function Expand-ProtocolDependencyWheelhouse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$WheelhouseRoot,
        [Parameter(Mandatory)][ValidateSet('win-x64','linux-x64')][string]$Platform,
        [Parameter(Mandatory)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression
    $wheels = @(Test-ProtocolDependencyWheelhouse -Lock $Lock -WheelhouseRoot $WheelhouseRoot -Platform $Platform)
    $targetRoot = [System.IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $targetRoot) { throw 'PROTOCOL_DEPENDENCY_DESTINATION_EXISTS' }
    $null = New-Item -ItemType Directory -Path $targetRoot
    $targetPrefix = $targetRoot.TrimEnd('\') + '\'
    $written = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $totalBytes = 0L
    try {
        foreach ($wheel in $wheels) {
            $stream = [System.IO.File]::OpenRead([string]$wheel.path)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
                try {
                    foreach ($entry in $archive.Entries) {
                        $relative = [string]$entry.FullName
                        $segments = @($relative -split '/')
                        $unixMode = ([int64]$entry.ExternalAttributes -shr 16) -band 0xF000
                        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('\') -or $relative.StartsWith('/') -or
                            @($segments | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0 -or $unixMode -eq 0xA000 -or
                            $relative.EndsWith('.pth', [System.StringComparison]::OrdinalIgnoreCase) -or
                            $relative.EndsWith('.pyc', [System.StringComparison]::OrdinalIgnoreCase) -or
                            $relative.EndsWith('.pyo', [System.StringComparison]::OrdinalIgnoreCase)) {
                            throw 'PROTOCOL_DEPENDENCY_WHEEL_ENTRY_INVALID'
                        }
                        if ($relative.EndsWith('/')) { continue }
                        if ([long]$entry.Length -lt 0 -or [long]$entry.Length -gt 64MB) { throw 'PROTOCOL_DEPENDENCY_WHEEL_ENTRY_SIZE_INVALID' }
                        $totalBytes += [long]$entry.Length
                        if ($totalBytes -gt 256MB) { throw 'PROTOCOL_DEPENDENCY_EXPANDED_SIZE_LIMIT' }
                        $candidate = [System.IO.Path]::GetFullPath((Join-Path $targetRoot ($relative.Replace('/', '\'))))
                        if (-not $candidate.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not $written.Add($candidate)) {
                            throw 'PROTOCOL_DEPENDENCY_WHEEL_ENTRY_COLLISION'
                        }
                        $parent = Split-Path -Parent $candidate
                        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
                        $input = $entry.Open()
                        try {
                            $output = [System.IO.File]::Open($candidate, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                            try { $input.CopyTo($output) } finally { $output.Dispose() }
                        }
                        finally { $input.Dispose() }
                    }
                }
                finally { $archive.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        return [pscustomobject]@{ platform=$Platform; wheel_count=$wheels.Count; file_count=$written.Count; expanded_bytes=$totalBytes; destination=$targetRoot }
    }
    catch {
        if (Test-Path -LiteralPath $targetRoot) { [System.IO.Directory]::Delete($targetRoot, $true) }
        throw
    }
}

Export-ModuleMember -Function Import-ProtocolDependencyLock, Test-ProtocolDependencyWheelhouse, Expand-ProtocolDependencyWheelhouse
