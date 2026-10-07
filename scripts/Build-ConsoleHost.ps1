[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'bin'
$null = New-Item -ItemType Directory -Path $bin -Force
$compiler = (Get-Command cl.exe -ErrorAction Stop).Source
Push-Location $bin
try {
    & $compiler /nologo /W4 /WX /O2 /MT /TC /D_WIN32_WINNT=0x0A00 (Join-Path $root 'src/pb_console_host.c') /Fe:pb_console_host.exe
    if ($LASTEXITCODE -ne 0) { throw "CONSOLE_HOST_BUILD_FAILED: $LASTEXITCODE" }
    $stream = [IO.File]::OpenRead((Join-Path $bin 'pb_console_host.exe'))
    try {
        $reader = [IO.BinaryReader]::new($stream)
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        if ($reader.ReadUInt16() -ne 0x8664) { throw 'CONSOLE_HOST_X64_REQUIRED' }
    } finally { $stream.Dispose() }
    Write-Output 'Console host compiled (x64). No process or traffic started.'
} finally { Pop-Location }
