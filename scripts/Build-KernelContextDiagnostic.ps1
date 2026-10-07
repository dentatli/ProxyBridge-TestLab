[CmdletBinding()]
param([string]$OutputDirectory='', [ValidateSet('Prepare','Build')][string]$Phase='Build')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not $OutputDirectory) {$OutputDirectory=Join-Path $root ('artifacts/diagnostics/tcp-redirect-context-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    & $python -B (Join-Path $root 'src/pb_prepare_kernel_context_diagnostic.py') --root $root --output $OutputDirectory
    if ($LASTEXITCODE -ne 0) {throw 'KERNEL_DIAGNOSTIC_PREPARATION_FAILED'}
}
$receiptPath=Join-Path $OutputDirectory 'preparation.json'
$receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($receipt.status -ne 'SOURCES_PREPARED_BUILD_PENDING' -or $receipt.method -ne 'redirect-kernel-context-v4' -or
    -not $receipt.diagnostic_only -or $receipt.performance_comparable -or -not $receipt.user_authorized_kernel_candidate) {throw 'KERNEL_DIAGNOSTIC_PREPARATION_INVALID'}
foreach ($property in $receipt.original_source_sha256.PSObject.Properties) {
    $expected=$property.Value
    if ($property.Name -eq $receipt.patched_file) {$expected=$receipt.patched_source_sha256}
    if ($property.Name -eq $receipt.kernel_patched_file) {$expected=$receipt.kernel_patched_source_sha256}
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('source/'+$property.Name))).Hash -ine $expected) {throw 'KERNEL_DIAGNOSTIC_SOURCE_CHANGED'}
}
foreach ($property in $receipt.added_sources.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('source/Windows/driver/src/'+$property.Name))).Hash -ine $property.Value) {throw 'KERNEL_DIAGNOSTIC_HEADER_CHANGED'}
}
if ($Phase -eq 'Prepare') {Write-Output $OutputDirectory;return}
function Invoke-IsolatedBuild([string]$Name,[string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable
    $info.Arguments=($Arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
    $info.WorkingDirectory=$WorkingDirectory;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $child=[Diagnostics.Process]::Start($info);$out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
    $timedOut=$false
    try {
        if (-not $child.WaitForExit(240000)) {$timedOut=$true;$child.Kill();$child.WaitForExit()}
        [IO.File]::WriteAllText((Join-Path $OutputDirectory ($Name+'.stdout.log')),$out.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $OutputDirectory ($Name+'.stderr.log')),$err.GetAwaiter().GetResult())
        if ($timedOut -or $child.ExitCode -ne 0) {throw ($Name+'_FAILED_exit'+$child.ExitCode+'_timeout'+$timedOut)}
    } finally {$child.Dispose()}
}
. (Join-Path $PSScriptRoot 'Enter-DevEnvironment.ps1')
$kit=Join-Path $OutputDirectory 'kit'
Invoke-IsolatedBuild 'core-build' $receipt.compiler @($receipt.compiler_args) $kit
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$msbuild=@(& $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe')[0]
if (-not $msbuild) {throw 'KERNEL_DIAGNOSTIC_MSBUILD_MISSING'}
$driverSource=Join-Path $OutputDirectory 'source/Windows/driver'
Invoke-IsolatedBuild 'kernel-build' $msbuild @((Join-Path $driverSource 'ProxyBridgeDrv.vcxproj'),'/t:Rebuild','/p:Configuration=Release','/p:Platform=x64','/p:SpectreMitigation=false','/v:minimal','/nologo') $driverSource
$driverOutput=Join-Path $driverSource 'x64/Release/ProxyBridgeDrv.sys'
if (-not (Test-Path -LiteralPath $driverOutput)) {throw 'KERNEL_DIAGNOSTIC_OUTPUT_MISSING'}
Copy-Item -LiteralPath $driverOutput -Destination (Join-Path $kit 'ProxyBridgeDrv.sys')
$driver=Join-Path $kit 'ProxyBridgeDrv.sys'
foreach ($file in @($driver,(Join-Path $kit 'ProxyBridgeCore.dll'))) {
    $pe=[IO.BinaryReader]::new([IO.File]::OpenRead($file))
    try {$pe.BaseStream.Position=0x3c;$offset=$pe.ReadInt32();$pe.BaseStream.Position=$offset+4;if ($pe.ReadUInt16() -ne 0x8664) {throw 'KERNEL_DIAGNOSTIC_X64_REQUIRED'}} finally {$pe.Dispose()}
}
$unsignedHash=(Get-FileHash -LiteralPath $driver).Hash.ToLowerInvariant()
$thumbprint='4544323109A45FC4761819E079BBDBD5E0BFE8D6'
$cert=Get-Item -LiteralPath ('Cert:/CurrentUser/My/'+$thumbprint)
if (-not $cert.HasPrivateKey -or $cert.NotAfter -le [DateTime]::Now -or $cert.NotBefore -gt [DateTime]::Now) {throw 'KERNEL_DIAGNOSTIC_EXISTING_CERTIFICATE_UNAVAILABLE'}
$signtool=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin/10.0.28000.0/x64/signtool.exe'
Invoke-IsolatedBuild 'kernel-sign' $signtool @('sign','/fd','SHA256','/sha1',$thumbprint,$driver) $kit
Invoke-IsolatedBuild 'kernel-sign-verify' $signtool @('verify','/pa','/v',$driver) $kit
$signature=Get-AuthenticodeSignature -LiteralPath $driver
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ine $thumbprint) {throw 'KERNEL_DIAGNOSTIC_SIGNATURE_INVALID'}
$base=[string]$receipt.base_kit
$envText=[IO.File]::ReadAllText((Join-Path $base 'product.env')).Replace($base,$kit)
foreach ($item in @(@('PB_EXPECTED_PROXYBRIDGE_CORE_SHA256','ProxyBridgeCore.dll'),@('PB_EXPECTED_DRIVER_SHA256','ProxyBridgeDrv.sys'))) {
    $hash=(Get-FileHash -LiteralPath (Join-Path $kit $item[1])).Hash.ToLowerInvariant()
    $envText=[regex]::Replace($envText,'(?m)^'+$item[0]+'=[^\r\n]*',$item[0]+'='+$hash)
}
$envText+="`nPB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=redirect-kernel-context-v4`n"
[IO.File]::WriteAllText((Join-Path $kit 'product.env'),$envText,[Text.UTF8Encoding]::new($false))
$components=@('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys') | ForEach-Object {
    $same=(Get-FileHash -LiteralPath (Join-Path $kit $_)).Hash -ieq (Get-FileHash -LiteralPath (Join-Path $base $_)).Hash
    if (($same -and $_ -ne 'ProxyBridge_CLI.exe') -or (-not $same -and $_ -eq 'ProxyBridge_CLI.exe')) {throw 'KERNEL_DIAGNOSTIC_COMPONENT_IDENTITY_INVALID'}
    [ordered]@{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $kit $_)).Hash.ToLowerInvariant();unchanged_from_baseline=$same}
}
$receipt.status='DIAGNOSTIC_BUILD_PREPARED'
$receipt | Add-Member components @($components)
$receipt | Add-Member signing ([ordered]@{unsigned_sha256=$unsignedHash;certificate_thumbprint=$thumbprint;authenticode_status='Valid';existing_certificate=$true;trust_changed=$false;testsigning_changed=$false;timestamp_requested=$false;installed=$false})
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Encoding UTF8
Write-Output ('Diagnostic kernel/Core built and signed; not installed: '+$kit)
