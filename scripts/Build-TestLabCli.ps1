[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('driver','v4.0.0')][string]$Contract)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $root 'artifacts/product-builds'
if ($Contract -eq 'driver') {
    $commit = '63be0ebf9bec92bfba95ef3d6729c375aa9af84e'
    $sourceHash = '679464cb81e236f2119af913206d8e8a78a5eac3a50864069851441f486c9d2d'
    $baseName = 'driver-63be0eb'
} else {
    $commit = '22e53445e44481fad0f63c2a088aa91c0deda3af'
    $sourceHash = '0d117b6a7be27625607b3df6b3e3ed3396e93fd9dfdde1480fb6417aa8c7c593'
    $baseName = 'v4.0.0-release'
}
$sourceRoot = Join-Path $buildRoot ('ProxyBridge-' + $commit)
$sourcePath = Join-Path $sourceRoot 'Windows/cli/main.c'
$basePath = Join-Path $buildRoot $baseName
$output = Join-Path $buildRoot ($baseName + '-testlab-cli')
if (Test-Path -LiteralPath $output) { throw 'TESTLAB_CLI_OUTPUT_EXISTS: preserve the identified build.' }
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine $sourceHash) { throw 'TESTLAB_CLI_SOURCE_CHANGED' }
$baseReceipt = Get-Content -LiteralPath (Join-Path $basePath 'build-receipt.json') -Raw | ConvertFrom-Json
foreach ($component in $baseReceipt.components) {
    if ((Get-FileHash -LiteralPath (Join-Path $basePath $component.name) -Algorithm SHA256).Hash -ine $component.sha256) { throw 'TESTLAB_CLI_BASE_COMPONENT_CHANGED' }
}
. (Join-Path $PSScriptRoot 'Enter-DevEnvironment.ps1')

# Patch only a copy. Profile parsing, rule assignment, Core and driver are upstream.
$text = [IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n")
function Replace-OneCliFragment([string]$Before, [string]$After) {
    $Before = $Before.Replace("`r`n", "`n")
    $After = $After.Replace("`r`n", "`n")
    if ([regex]::Matches($script:text, [regex]::Escape($Before)).Count -ne 1) { throw 'TESTLAB_CLI_PATCH_CONTEXT_CHANGED' }
    $script:text = $script:text.Replace($Before, $After)
}
Replace-OneCliFragment '#include <windows.h>' "#include <windows.h>`n#include <shellapi.h>"
Replace-OneCliFragment "int main(int argc, char* argv[])`n{" @'
int main(int argc, char* argv[])
{
    /* TestLab: deliver callback lines/startup directly to redirected pipes. */
    if (setvbuf(stdout, NULL, _IONBF, 0) != 0 || setvbuf(stderr, NULL, _IONBF, 0) != 0)
        return 2;
'@
Replace-OneCliFragment @'
        if (InterlockedExchange(&g_running, 0))
        {
            printf("\nStopping ProxyBridge...\n");
            if (g_Stop) g_Stop();
        }
'@ @'
        /* TestLab: request shutdown; the main thread owns Stop and teardown. */
        InterlockedExchange(&g_running, 0);
'@
Replace-OneCliFragment @'
    printf("ProxyBridge stopped.\n\n");
    FreeLibrary(g_hDll);
    return 0;
'@ @'
    printf("\nStopping ProxyBridge...\n");
    BOOL stop_ok = g_Stop != NULL && g_Stop();
    if (stop_ok) printf("ProxyBridge stopped.\n\n");
    else fprintf(stderr, "ERROR: ProxyBridge_Stop failed.\n");
    /* Stop's internal timeouts do not prove all workers joined. Keep the DLL
       loaded until process exit rather than unloading beneath a worker. */
    return stop_ok && !ferror(stdout) && !ferror(stderr) ? 0 : 2;
'@
$null = New-Item -ItemType Directory -Path $output
$patchedPath = Join-Path $output 'main.testlab.c'
[IO.File]::WriteAllText($patchedPath, $text, [Text.UTF8Encoding]::new($false))
$argsCli = @('/nologo','/O2','/Ot','/GL','/Gy','/W4','/WX','/D_WINSOCK_DEPRECATED_NO_WARNINGS','/D_WIN32_WINNT=0x0601','/DNDEBUG','/arch:SSE2','/fp:fast','/GS','/guard:cf','/Qpar',$patchedPath,'/link','/LTCG','/OPT:REF','/OPT:ICF','/RELEASE','/DYNAMICBASE','/NXCOMPAT','/SUBSYSTEM:CONSOLE','winhttp.lib','shell32.lib','advapi32.lib','/OUT:ProxyBridge_CLI.exe')
$compiler = (Get-Command cl.exe -ErrorAction Stop).Source
Push-Location $output
try {
    & $compiler @argsCli *> cli-build.log
    if ($LASTEXITCODE -ne 0) { throw "TESTLAB_CLI_BUILD_FAILED: $LASTEXITCODE (see cli-build.log)" }
} finally { Pop-Location }
$pe = [IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $output 'ProxyBridge_CLI.exe')))
try {
    $pe.BaseStream.Position = 0x3c
    $offset = $pe.ReadInt32()
    $pe.BaseStream.Position = $offset + 4
    if ($pe.ReadUInt16() -ne 0x8664) { throw 'TESTLAB_CLI_X64_REQUIRED' }
} finally { $pe.Dispose() }
foreach ($component in $baseReceipt.components) {
    if ($component.name -eq 'ProxyBridge_CLI.exe') { continue }
    Copy-Item -LiteralPath (Join-Path $basePath $component.name) -Destination $output
    if ((Get-FileHash -LiteralPath (Join-Path $output $component.name)).Hash -ine $component.sha256) { throw 'TESTLAB_CLI_COPY_MISMATCH' }
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'LICENSE') -Destination (Join-Path $output 'LICENSE')
# Keep the base kit's redistribution notices (including WinDivert when present).
Get-ChildItem -LiteralPath $basePath -File | Where-Object { $_.Name -match '(?i)license|copying|notice' } | ForEach-Object {
    if ($_.Name -ne 'LICENSE') { Copy-Item -LiteralPath $_.FullName -Destination $output }
}
$cliHash = (Get-FileHash -LiteralPath (Join-Path $output 'ProxyBridge_CLI.exe')).Hash.ToLowerInvariant()
$envText = [IO.File]::ReadAllText((Join-Path $basePath 'product.env')).Replace($basePath, $output)
$envText = [regex]::Replace($envText, '(?m)^PB_EXPECTED_PROXYBRIDGE_CLI_SHA256=[^\r\n]*', 'PB_EXPECTED_PROXYBRIDGE_CLI_SHA256=' + $cliHash)
$envText += "`nPB_PROXYBRIDGE_CLI_VARIANT=testlab-unbuffered-v1`n"
[IO.File]::WriteAllText((Join-Path $output 'product.env'), $envText, [Text.UTF8Encoding]::new($false))
$inventory = foreach ($component in $baseReceipt.components) {
    $file = Get-Item -LiteralPath (Join-Path $output $component.name)
    [pscustomobject]@{ name=$file.Name; size=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant(); unchanged_from_base=($component.name -ne 'ProxyBridge_CLI.exe') }
}
[ordered]@{
    schema_version=1; prepared_at_utc=[DateTime]::UtcNow.ToString('o'); contract=$Contract
    cli_variant='testlab-unbuffered-v1'; cli_source_commit=$commit; upstream_cli_source_sha256=$sourceHash
    patched_cli_source_sha256=(Get-FileHash -LiteralPath $patchedPath).Hash.ToLowerInvariant()
    base_receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $basePath 'build-receipt.json')).Hash.ToLowerInvariant()
    compiler=$compiler; compiler_args=$argsCli; components=@($inventory)
    changes=@('unbuffered stdout/stderr','Stop owned by main thread','retain DLL until process exit','declare ShellExecuteA through shellapi.h')
    source_event_stream_complete=$false; product_executed=$false; driver_installed_or_loaded=$false
    route_verified=$false; benchmark_ready=$false
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'build-receipt.json') -Encoding UTF8
Write-Output "TestLab CLI kit prepared: $output. No product or driver executed."
