[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,
      [ValidateSet('Prepare','Build')][string]$Phase='Prepare')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$allowedRoot=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $OutputDirectory.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) {throw 'TARGET_OUTPUT_OUTSIDE_DIAGNOSTICS'}
$checkedPath=$OutputDirectory
while ($checkedPath) {
    if ((Test-Path -LiteralPath $checkedPath) -and ((Get-Item -LiteralPath $checkedPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'TARGET_REPARSE_PATH'}
    $checkedPath=[IO.Path]::GetDirectoryName($checkedPath)
}
$python=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    & $python -B (Join-Path $root 'src/pb_prepare_target_accept.py') --root $root --parent (Join-Path $root 'artifacts/diagnostics/tcp-redirect-context-preparation-20261006-114601-c11a4ded') --assets-kit (Join-Path $root 'artifacts/diagnostics/pb-kd-lookup-four-preparation-20261018-083735-2eb58055/kit') --output $OutputDirectory
    if ($LASTEXITCODE) {throw 'TARGET_PREPARE_FAILED'}
}
$receiptPath=Join-Path $OutputDirectory 'preparation.json'
$receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($receipt.method -ne 'target-accept-barrier-v1' -or $receipt.status -ne 'SOURCES_PREPARED_BUILD_PENDING') {throw 'TARGET_BUILD_STATE_INVALID'}
foreach ($entry in $receipt.source_after_sha256.PSObject.Properties) {
    $path=Join-Path $OutputDirectory ('source/'+$entry.Name)
    if ((Get-FileHash -LiteralPath $path).Hash -ine $entry.Value) {throw 'TARGET_SOURCE_CHANGED'}
}
foreach ($entry in $receipt.reused_binary_sha256.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('kit/'+$entry.Name))).Hash -ine $entry.Value) {throw 'TARGET_REUSED_BINARY_CHANGED'}
}
if ($Phase -eq 'Prepare') {return}
if ((Get-FileHash -LiteralPath (Join-Path $root 'src/diagnostics/pb_target_accept_gate.h')).Hash -ine
    (Get-FileHash -LiteralPath (Join-Path $OutputDirectory 'source/Windows/src/relay/pb_target_accept_gate.h')).Hash) {throw 'TARGET_TEST_HEADER_DIFFERS_FROM_CLONE'}
. (Join-Path $PSScriptRoot 'Enter-DevEnvironment.ps1')
function Invoke-TargetBuild([string]$Name,[string]$Executable,[string[]]$Arguments,[string]$Directory) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable
    $info.Arguments=($Arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
    $info.WorkingDirectory=$Directory;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $child=[Diagnostics.Process]::Start($info)
    $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
    try {
        if (-not $child.WaitForExit(240000)) {$child.Kill();$child.WaitForExit();throw 'TARGET_BUILD_TIMEOUT'}
        [IO.File]::WriteAllText((Join-Path $Directory ($Name+'.stdout.log')),$stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $Directory ($Name+'.stderr.log')),$stderr.GetAwaiter().GetResult())
        if ($child.ExitCode -ne 0) {throw ($Name+'_FAILED_'+$child.ExitCode)}
    } finally {$child.Dispose()}
}
$verification=Join-Path $OutputDirectory 'verification'
$null=New-Item -ItemType Directory -Path $verification
try {
    $fake=Join-Path $verification 'target-gate-test.exe'
    Invoke-TargetBuild 'fake-build' $receipt.compiler @('/nologo','/W4','/WX','/TC',('/Fe:'+$fake),('/Fo:'+(Join-Path $verification 'target-gate-test.obj')),(Join-Path $root 'tests/native/target_accept_gate_test.c')) $verification
    # Only a fake-API test executable: no socket, real event, sleep, device or driver APIs.
    Invoke-TargetBuild 'fake-run' $fake @() $verification
    Invoke-TargetBuild 'core-build' $receipt.compiler @($receipt.compiler_args) (Join-Path $OutputDirectory 'kit')
    $dumpbin=Join-Path (Split-Path -Parent $receipt.compiler) 'dumpbin.exe'
    $parentExports=& $dumpbin /nologo /exports (Join-Path $receipt.parent 'kit/ProxyBridgeCore.dll')
    if ($LASTEXITCODE) {throw 'TARGET_PARENT_EXPORT_QUERY_FAILED'}
    $newExports=& $dumpbin /nologo /exports (Join-Path $OutputDirectory 'kit/ProxyBridgeCore.dll')
    if ($LASTEXITCODE) {throw 'TARGET_EXPORT_QUERY_FAILED'}
    $pattern='^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(\S+)'
    $oldNames=@($parentExports | ForEach-Object {if ($_ -match $pattern) {$matches[1]}} | Sort-Object)
    $newNames=@($newExports | ForEach-Object {if ($_ -match $pattern) {$matches[1]}} | Sort-Object)
    if (-not $oldNames.Count -or ($oldNames -join ',') -cne ($newNames -join ',')) {throw 'TARGET_EXPORTS_DIFFER'}
    [ordered]@{exports_match=$true;export_count=$newNames.Count;fake_api_tests=10;product_started=$false;traffic_generated=$false;
        core_sha256=(Get-FileHash -LiteralPath (Join-Path $OutputDirectory 'kit/ProxyBridgeCore.dll')).Hash;
        runtime_pending=$true;driver_installed=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $verification 'build-result.json') -Encoding UTF8
    $receipt.status='DIAGNOSTIC_BUILD_PREPARED_NOT_RUNNABLE'
    $receipt | Add-Member -NotePropertyName core_sha256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $OutputDirectory 'kit/ProxyBridgeCore.dll')).Hash
} catch {$receipt.status='BUILD_FAILED';throw}
finally {$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding UTF8}
Write-Output ('TARGET_BUILD_VERIFIED_NO_RUN: '+$OutputDirectory)
