[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$publisher = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Publish-LocalRelease.ps1') -Raw
$start = Get-Content -LiteralPath (Join-Path $repoRoot 'packaging\Start-ProxyBridge-TestLab.ps1') -Raw
$stop = Get-Content -LiteralPath (Join-Path $repoRoot 'packaging\Stop-ProxyBridge-TestLab.ps1') -Raw
$repair = Get-Content -LiteralPath (Join-Path $repoRoot 'packaging\Repair-ProxyBridge-TestLab.ps1') -Raw
$uninstall = Get-Content -LiteralPath (Join-Path $repoRoot 'packaging\Uninstall-ProxyBridge-TestLabData.ps1') -Raw
$transport = Get-Content -LiteralPath (Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui\Services\ServerTransport.cs') -Raw

Assert-True ($publisher -match '--self-contained true' -and $publisher -match '-r win-x64') 'publisher must create a self-contained win-x64 controller'
Assert-True ($publisher -match 'https://api\.nuget\.org/v3/index\.json') 'self-contained runtime packs must use the explicit official NuGet source'
Assert-True ($publisher -match 'RELEASE_DESTINATION_ALREADY_EXISTS') 'publisher must refuse an existing release destination'
Assert-True ($publisher -match 'CLIENT_BINARY_REQUIRED' -and $publisher -match 'AllowMissingClient') 'publisher must require the traffic client unless an interface-only package is explicit'
Assert-True ($publisher -match "'bin\\protocol-worker'" -and $publisher -match 'Assert-ProtocolWorkerBundle') 'release must include the verified bundled protocol runtime'
Assert-True ($publisher -match 'PROTOCOL_RUNTIME_HASH_MISMATCH' -and $publisher -match 'protocol_worker_integrity_verified=\$true') 'release must fail closed on protocol runtime drift and declare verified inclusion'
Assert-True ($publisher -match "exclusions=@\('\.env','credentials','generated profiles','evidence','\.git','product binaries'\)") 'release manifest must list private/runtime exclusions'
Assert-True ($publisher -notmatch 'Copy-Item.+repositoryRoot.+Recurse') 'publisher must not recursively copy the repository root'
Assert-True ($publisher -match '__pycache__' -and $publisher -match '\.pyc' -and $publisher -match 'RELEASE_REPARSE_POINT_REFUSED') 'publisher must reject caches and reparse-point inputs'

Assert-True ($start -match "http://127\.0\.0\.1:5178/" -and $start -notmatch '0\.0\.0\.0') 'launcher health checks must remain loopback-only'
Assert-True ($start -match 'ProxyBridge\.TestLab\.Ui\.exe' -and $start -match 'WindowStyle Hidden') 'launcher must start only the packaged hidden controller'
Assert-True ($stop -match 'MainModule\.FileName' -and $stop -match 'OrdinalIgnoreCase') 'stop script must verify the observed executable path'
Assert-True ($repair -match 'SHA256SUMS\.txt' -and $repair -match 'PACKAGE_HASH_MISMATCH') 'repair must verify the complete package checksum manifest'
Assert-True ($repair -match 'PACKAGE_UNEXPECTED_FILE' -and $repair -match 'PACKAGE_REPARSE_POINT_REFUSED') 'repair must reject unlisted files and reparse points'
Assert-True ($repair -match 'SetAccessRuleProtection') 'optional data repair must restore an explicit protected ACL'
Assert-True ($uninstall -match 'CONFIRM_REMOVAL_REQUIRED') 'data removal must require explicit confirmation'
Assert-True ($uninstall -match 'DATA_ROOT_REFUSED' -and $uninstall -match 'DATA_ROOT_REPARSE_POINT_REFUSED') 'data removal must reject broad and reparse-point targets'

Assert-True ($transport -match '/opt/proxybridge-testlab/versions/' -and $transport -match 'ln -sfn.+current\.new') 'server upgrades must activate a versioned endpoint atomically'
Assert-True ($transport -match 'trap rollback EXIT' -and $transport -match 'ROLLBACK_ATTEMPTED') 'server mutation must retain an explicit rollback path'

foreach ($document in @('OPERATOR_GUIDE.md','SECURITY.md','RELEASE.md')) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot "docs\$document") -PathType Leaf) "release document missing: $document"
}

'PASS: release packaging and recovery contracts'
