[CmdletBinding()]
param(
    [string]$CompilerPath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\pb_perf_client.c'
$binDirectory = Join-Path $root 'bin'
$output = Join-Path $binDirectory 'pb_perf_client.exe'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'PERFORMANCE_WORKER_SOURCE_MISSING'
}

if ($ValidateOnly) {
    [pscustomobject][ordered]@{
        status = 'VALIDATED'
        source_name = [IO.Path]::GetFileName($source)
        output_name = [IO.Path]::GetFileName($output)
        build_required = $true
    } | ConvertTo-Json -Compress
    return
}

function Resolve-PerformanceCompiler {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) { throw 'PERFORMANCE_WORKER_COMPILER_NOT_FOUND' }
        $resolved = (Resolve-Path -LiteralPath $ExplicitPath).Path
        $name = [IO.Path]::GetFileName($resolved)
        if ($name -ieq 'cl.exe') { return [pscustomobject]@{ Kind = 'MSVC'; Path = $resolved } }
        if ($name -ieq 'gcc.exe') { return [pscustomobject]@{ Kind = 'MinGW-w64'; Path = $resolved } }
        throw 'PERFORMANCE_WORKER_COMPILER_UNSUPPORTED'
    }

    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cl) { return [pscustomobject]@{ Kind = 'MSVC'; Path = $cl.Source } }
    $gcc = Get-Command gcc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gcc) { return [pscustomobject]@{ Kind = 'MinGW-w64'; Path = $gcc.Source } }
    if ($env:CC -and (Test-Path -LiteralPath $env:CC -PathType Leaf)) {
        return Resolve-PerformanceCompiler -ExplicitPath $env:CC
    }
    throw 'PERFORMANCE_WORKER_COMPILER_UNAVAILABLE'
}

New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
$compiler = Resolve-PerformanceCompiler -ExplicitPath $CompilerPath
if ($compiler.Kind -eq 'MSVC') {
    & $compiler.Path /nologo /W4 /WX /O2 /TC /D_WIN32_WINNT=0x0601 $source /Fe:$output
}
else {
    & $compiler.Path -std=c11 -O2 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0601 -o $output $source
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "PERFORMANCE_WORKER_BUILD_FAILED_$LASTEXITCODE"
}

$stream = [IO.File]::Open($output, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $reader = [IO.BinaryReader]::new($stream)
    $stream.Position = 0x3c
    $peOffset = $reader.ReadInt32()
    $stream.Position = $peOffset + 4
    $machine = $reader.ReadUInt16()
}
finally {
    $stream.Dispose()
}
if ($machine -ne 0x8664) {
    throw ('PERFORMANCE_WORKER_NON_X64_0x{0:X4}' -f $machine)
}

[pscustomobject][ordered]@{
    status = 'BUILT'
    compiler = $compiler.Kind
    machine = 'x64 (0x8664)'
    output = $output
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
} | ConvertTo-Json -Compress
