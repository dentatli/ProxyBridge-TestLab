[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\ProtocolDependencies.psm1') -Force
$lockPath = Join-Path $root 'vendor\protocol-dependencies.lock.json'
$wheelhouse = Join-Path $root 'vendor\wheelhouse'
$lock = Import-ProtocolDependencyLock -Path $lockPath

$windows = @(Test-ProtocolDependencyWheelhouse -Lock $lock -WheelhouseRoot $wheelhouse -Platform win-x64)
$linux = @(Test-ProtocolDependencyWheelhouse -Lock $lock -WheelhouseRoot $wheelhouse -Platform linux-x64)
Assert-Equal @($lock.packages).Count $windows.Count 'Windows wheel set must have one locked wheel per package'
Assert-Equal @($lock.packages).Count $linux.Count 'Linux wheel set must have one locked wheel per package'

$tampered = $lock | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$tampered.artifacts[0].sha256 = '0' * 64
Assert-Throws { Test-ProtocolDependencyWheelhouse -Lock $tampered -WheelhouseRoot $wheelhouse -Platform win-x64 } 'PROTOCOL_DEPENDENCY_WHEEL_HASH_MISMATCH' 'tampered dependency hash must fail closed'

$temp = New-TestDirectory
try {
    $expanded = Expand-ProtocolDependencyWheelhouse -Lock $lock -WheelhouseRoot $wheelhouse -Platform win-x64 -Destination (Join-Path $temp 'vendor')
    Assert-Equal $windows.Count ([int]$expanded.wheel_count) 'every locked Windows wheel must be expanded'
    Assert-True ([int]$expanded.file_count -gt $windows.Count) 'expanded runtime must contain package files'
    Assert-True (Test-Path -LiteralPath (Join-Path $expanded.destination 'aioquic\__init__.py') -PathType Leaf) 'aioquic package must be present'
    Assert-True (Test-Path -LiteralPath (Join-Path $expanded.destination 'pylsqpack\__init__.py') -PathType Leaf) 'QPACK implementation must be present'
}
finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }

'PASS: locked offline protocol dependencies'
