[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[ValidateSet('Prepare','Build')][string]$Phase='Prepare',
    [string]$KernelPreparation='C:\src\ProxyBridge-TestLab\artifacts\diagnostics\tcp-redirect-context-preparation-20261005-185952-9c036895')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    & $python -B (Join-Path $root 'src/pb_prepare_kernel_timing_diagnostic.py') --root $root --output $OutputDirectory --kernel-preparation $KernelPreparation
    if ($LASTEXITCODE -ne 0) {throw 'KERNEL_TIMING_PREPARATION_FAILED'}
}
$receipt=Get-Content -LiteralPath (Join-Path $OutputDirectory 'preparation.json') -Raw | ConvertFrom-Json
if ($receipt.status -ne 'SOURCES_PREPARED_BUILD_PENDING' -or $receipt.method -ne 'redirect-kernel-context-v4' -or
    $receipt.timing_policy.method -ne 'accept-query-qpc-v1' -or -not $receipt.timing_policy.original_single_query_preserved -or
    -not $receipt.timing_policy.logging_after_original_query -or $receipt.timing_policy.payload_recorded) {throw 'KERNEL_TIMING_POLICY_INVALID'}
foreach ($property in $receipt.original_source_sha256.PSObject.Properties) {
    $expected=$property.Value
    if ($property.Name -eq $receipt.kernel_patched_file) {$expected=$receipt.kernel_patched_source_sha256}
    if ($receipt.timing_patched_files.PSObject.Properties[$property.Name]) {$expected=$receipt.timing_patched_files.PSObject.Properties[$property.Name].Value}
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('source/'+$property.Name))).Hash -ine $expected) {throw 'KERNEL_TIMING_SOURCE_CHANGED'}
}
foreach ($property in $receipt.added_sources.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('source/Windows/driver/src/'+$property.Name))).Hash -ine $property.Value) {throw 'KERNEL_TIMING_KERNEL_HEADER_CHANGED'}
}
$kit=Join-Path $OutputDirectory 'kit';$driver=Join-Path $kit 'ProxyBridgeDrv.sys'
if ((Get-FileHash -LiteralPath $driver).Hash -ine $receipt.reused_kernel_sha256) {throw 'KERNEL_TIMING_REUSED_SYS_CHANGED'}
if ($Phase -eq 'Prepare') {Write-Output $OutputDirectory;return}
. (Join-Path $PSScriptRoot 'Enter-DevEnvironment.ps1')
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$receipt.compiler
$info.Arguments=($receipt.compiler_args | ForEach-Object {'"'+$_+'"'}) -join ' '
$info.WorkingDirectory=$kit;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$child=[Diagnostics.Process]::Start($info);$out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
try {
    if (-not $child.WaitForExit(240000)) {$child.Kill();$child.WaitForExit();throw 'KERNEL_TIMING_CORE_BUILD_TIMEOUT'}
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'timing-core-build.stdout.log'),$out.GetAwaiter().GetResult())
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'timing-core-build.stderr.log'),$err.GetAwaiter().GetResult())
    if ($child.ExitCode -ne 0) {throw ('KERNEL_TIMING_CORE_BUILD_FAILED: '+$child.ExitCode)}
} finally {$child.Dispose()}
$signature=Get-AuthenticodeSignature -LiteralPath $driver
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ine $receipt.signing.certificate_thumbprint) {throw 'KERNEL_TIMING_REUSED_SIGNATURE_INVALID'}
$base=[string]$receipt.base_kit
$envText=[IO.File]::ReadAllText((Join-Path $base 'product.env')).Replace($base,$kit)
foreach ($item in @(@('PB_EXPECTED_PROXYBRIDGE_CORE_SHA256','ProxyBridgeCore.dll'),@('PB_EXPECTED_DRIVER_SHA256','ProxyBridgeDrv.sys'))) {
    $hash=(Get-FileHash -LiteralPath (Join-Path $kit $item[1])).Hash.ToLowerInvariant()
    $envText=[regex]::Replace($envText,'(?m)^'+$item[0]+'=[^\r\n]*',$item[0]+'='+$hash)
}
$envText+="`nPB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=redirect-kernel-context-v4`n"
[IO.File]::WriteAllText((Join-Path $kit 'product.env'),$envText,[Text.UTF8Encoding]::new($false))
$receipt.status='DIAGNOSTIC_BUILD_PREPARED'
$components=@('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys') | ForEach-Object {
    [ordered]@{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $kit $_)).Hash.ToLowerInvariant();unchanged_from_baseline=((Get-FileHash -LiteralPath (Join-Path $kit $_)).Hash -ieq (Get-FileHash -LiteralPath (Join-Path $base $_)).Hash)}
}
$receipt | Add-Member components @($components)
$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Encoding UTF8
Write-Output ('Timing Core built; signed kernel reused unchanged; not installed: '+$kit)
