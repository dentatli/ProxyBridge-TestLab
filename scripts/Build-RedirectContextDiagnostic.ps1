[CmdletBinding()]
param([string]$OutputDirectory='', [string]$PythonPath='', [switch]$ExtendedQueries, [switch]$AvailabilityProbes,
    [ValidateSet('Prepare','Build')][string]$Phase='Build')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
$root=Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $root ('artifacts/diagnostics/tcp-redirect-context-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)) }
if (-not $PythonPath) { $PythonPath=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
if ($ExtendedQueries -and $AvailabilityProbes) {throw 'DIAGNOSTIC_BUILD_OPTIONS_CONFLICT'}
$expectedMethod=$(if ($AvailabilityProbes) {'redirect-context-probes-v3'} elseif ($ExtendedQueries) {'redirect-context-followup-v2'} else {'redirect-context-logging-v1'})
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    $entry=$(if ($AvailabilityProbes) {'pb_prepare_redirect_context_probes.py'} elseif ($ExtendedQueries) {'pb_prepare_redirect_context_extended.py'} else {'pb_prepare_redirect_context_diagnostic.py'})
    & $PythonPath -B (Join-Path $root ('src/'+$entry)) --root $root --output $OutputDirectory
    if ($LASTEXITCODE -ne 0) { throw 'REDIRECT_DIAGNOSTIC_SOURCE_PREPARATION_FAILED' }
} elseif ($Phase -eq 'Prepare') {throw 'DIAGNOSTIC_OUTPUT_MUST_BE_FRESH'}
$receiptPath=Join-Path $OutputDirectory 'preparation.json'
$receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($receipt.status -ne 'SOURCES_PREPARED_BUILD_PENDING' -or $receipt.method -ne $expectedMethod -or -not $receipt.diagnostic_only -or $receipt.performance_comparable -or
    $receipt.source_commit -ne '63be0ebf9bec92bfba95ef3d6729c375aa9af84e') {throw 'REDIRECT_DIAGNOSTIC_PREPARATION_INVALID'}
if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('source/'+$receipt.patched_file))).Hash -ine $receipt.patched_source_sha256) {throw 'REDIRECT_DIAGNOSTIC_SOURCE_CHANGED'}
foreach ($property in $receipt.original_source_sha256.PSObject.Properties) {
    if ($property.Name -ne $receipt.patched_file -and (Get-FileHash -LiteralPath (Join-Path $OutputDirectory ('source/'+$property.Name))).Hash -ine $property.Value) {throw 'REDIRECT_DIAGNOSTIC_SOURCE_CHANGED'}
}
if ($Phase -eq 'Prepare') {Write-Output ('Diagnostic sources prepared; Core build pending: '+$OutputDirectory);return}
$kit=Join-Path $OutputDirectory 'kit'
. (Join-Path $PSScriptRoot 'Enter-DevEnvironment.ps1')
$arguments=@($receipt.compiler_args)
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=$receipt.compiler
$info.Arguments=($arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
$info.WorkingDirectory=$kit
$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$child=[Diagnostics.Process]::Start($info)
$stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
try {
    if (-not $child.WaitForExit(240000)) { $child.Kill();$child.WaitForExit();throw 'REDIRECT_DIAGNOSTIC_BUILD_TIMEOUT' }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'core-build.stdout.log'),$stdout.GetAwaiter().GetResult())
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'core-build.stderr.log'),$stderr.GetAwaiter().GetResult())
    if ($child.ExitCode -ne 0) { throw ('REDIRECT_DIAGNOSTIC_BUILD_FAILED_'+$child.ExitCode) }
} finally { $child.Dispose() }
$core=Join-Path $kit 'ProxyBridgeCore.dll'
$pe=[IO.BinaryReader]::new([IO.File]::OpenRead($core))
try { $pe.BaseStream.Position=0x3c;$offset=$pe.ReadInt32();$pe.BaseStream.Position=$offset+4;if ($pe.ReadUInt16() -ne 0x8664) {throw 'REDIRECT_DIAGNOSTIC_X64_REQUIRED'} } finally {$pe.Dispose()}
$base=[string]$receipt.base_kit
$envText=[IO.File]::ReadAllText((Join-Path $base 'product.env')).Replace($base,$kit)
$coreHash=(Get-FileHash -LiteralPath $core).Hash.ToLowerInvariant()
$envText=[regex]::Replace($envText,'(?m)^PB_EXPECTED_PROXYBRIDGE_CORE_SHA256=[^\r\n]*','PB_EXPECTED_PROXYBRIDGE_CORE_SHA256='+$coreHash)
$envText+="`nPB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=$expectedMethod`n"
[IO.File]::WriteAllText((Join-Path $kit 'product.env'),$envText,[Text.UTF8Encoding]::new($false))
$components=@('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys') | ForEach-Object {
    $name=$_;$file=Join-Path $kit $name
    [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant();unchanged_from_baseline=($name -ne 'ProxyBridgeCore.dll')}
}
foreach ($component in $components) {
    if ($component.unchanged_from_baseline -and $component.sha256 -ne (Get-FileHash -LiteralPath (Join-Path $base $component.name)).Hash.ToLowerInvariant()) {throw 'REDIRECT_DIAGNOSTIC_BASE_COMPONENT_CHANGED'}
}
$receipt.status='DIAGNOSTIC_BUILD_PREPARED'
$receipt | Add-Member -NotePropertyName components -NotePropertyValue @($components)
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Encoding UTF8
if ($ExtendedQueries -or $AvailabilityProbes) {
    & (Join-Path $PSScriptRoot 'Invoke-TcpRedirectContextDiagnostic.ps1') -DiagnosticDirectory $OutputDirectory -Phase Prepare
}
Write-Output ('Diagnostic Core prepared / Диагностический Core подготовлен: '+$kit+'. Product not started; not a performance baseline.')
