[CmdletBinding()]
param(
    [string]$CompilerPath,
    [string]$OutputPath=''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\pb_net_client.c'
$binDirectory = Join-Path $root 'bin'
$output = Join-Path $binDirectory 'pb_net_client.exe'
if ($OutputPath) {
    $output = [IO.Path]::GetFullPath($OutputPath)
    $binDirectory = Split-Path -Parent $output
}

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Source file not found: $source"
}
New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null

function Resolve-Compiler {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        $resolved = (Resolve-Path -LiteralPath $ExplicitPath).Path
        return [pscustomobject]@{ Kind = if ([IO.Path]::GetFileName($resolved) -ieq 'cl.exe') { 'MSVC' } else { 'MinGW-w64' }; Path = $resolved }
    }
    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cl) { return [pscustomobject]@{ Kind = 'MSVC'; Path = $cl.Source } }
    $gcc = Get-Command gcc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gcc) { return [pscustomobject]@{ Kind = 'MinGW-w64'; Path = $gcc.Source } }
    if ($env:CC -and (Test-Path -LiteralPath $env:CC -PathType Leaf)) {
        $resolved = (Resolve-Path -LiteralPath $env:CC).Path
        return [pscustomobject]@{ Kind = if ([IO.Path]::GetFileName($resolved) -ieq 'cl.exe') { 'MSVC' } else { 'MinGW-w64' }; Path = $resolved }
    }
    throw 'No x64 compiler found. Put cl.exe or MinGW-w64 gcc.exe in PATH, set CC, or pass -CompilerPath.'
}

$compiler = Resolve-Compiler -ExplicitPath $CompilerPath
$objectOutput = Join-Path $binDirectory 'pb_net_client.obj'
if ($compiler.Kind -eq 'MSVC') {
    & $compiler.Path /nologo /W4 /WX /O2 /TC /D_WIN32_WINNT=0x0601 $source /Fo:$objectOutput /Fe:$output /link ws2_32.lib bcrypt.lib
} else {
    & $compiler.Path -std=c11 -O2 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0601 -o $output $source -lws2_32 -lbcrypt
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "Harness build failed with exit code $LASTEXITCODE"
}

$stream = [IO.File]::Open($output, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $reader = [IO.BinaryReader]::new($stream)
    $stream.Position = 0x3c
    $peOffset = $reader.ReadInt32()
    $stream.Position = $peOffset + 4
    $machine = $reader.ReadUInt16()
} finally {
    $stream.Dispose()
}
if ($machine -ne 0x8664) {
    throw ('Compiler produced non-x64 PE machine 0x{0:X4}' -f $machine)
}

$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
[pscustomobject]@{
    Compiler = $compiler.Kind
    CompilerPath = $compiler.Path
    Machine = 'x64 (0x8664)'
    Output = $output
    SHA256 = $hash
} | ConvertTo-Json -Compress
