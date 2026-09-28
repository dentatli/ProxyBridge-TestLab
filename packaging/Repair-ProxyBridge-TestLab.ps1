[CmdletBinding()]
param([switch]$RepairDataAcl)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$sumsPath = Join-Path $packageRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { throw 'PACKAGE_CHECKSUMS_NOT_FOUND' }

$verified = 0
$expectedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($line in [System.IO.File]::ReadAllLines($sumsPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9._/ -]+)$') { throw 'PACKAGE_CHECKSUM_LINE_INVALID' }
    $relative = $Matches[2]
    if (-not $expectedFiles.Add($relative.Replace('\','/'))) { throw "PACKAGE_CHECKSUM_DUPLICATE: $relative" }
    $path = [System.IO.Path]::GetFullPath((Join-Path $packageRoot $relative.Replace('/', '\')))
    $prefix = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\') + '\'
    if (-not $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'PACKAGE_CHECKSUM_PATH_INVALID' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "PACKAGE_FILE_MISSING: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Matches[1]) { throw "PACKAGE_HASH_MISMATCH: $relative" }
    $verified++
}

$actualFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$pending = [System.Collections.Generic.Stack[string]]::new()
$pending.Push([System.IO.Path]::GetFullPath($packageRoot))
while ($pending.Count -gt 0) {
    $directoryPath = $pending.Pop()
    foreach ($item in @(Get-ChildItem -LiteralPath $directoryPath -Force)) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "PACKAGE_REPARSE_POINT_REFUSED: $($item.FullName)" }
        if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
        if ([string]::Equals($item.FullName, $sumsPath, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $item.FullName.Substring($packageRoot.TrimEnd('\').Length + 1).Replace('\','/')
        $null = $actualFiles.Add($relative)
    }
}
foreach ($relative in $actualFiles) {
    if (-not $expectedFiles.Contains($relative)) { throw "PACKAGE_UNEXPECTED_FILE: $relative" }
}
if ($actualFiles.Count -ne $expectedFiles.Count) { throw 'PACKAGE_INVENTORY_MISMATCH' }

if ($RepairDataAcl) {
    $dataRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'ProxyBridge-TestLab'
    $directory = New-Item -ItemType Directory -Path $dataRoot -Force
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $security = [System.Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    foreach($sid in @($identity,$system)){$security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
    $directory.SetAccessControl($security)
}

"PACKAGE_VERIFIED=$verified"
