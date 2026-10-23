[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$null = New-Item -ItemType Directory -Path (Join-Path $root 'bin') -Force
Push-Location (Join-Path $root 'bin')
try {
    # GetProcAddress casts are the documented dynamic C ABI, selected explicitly below.
    & (Get-Command cl.exe -ErrorAction Stop).Source /nologo /W4 /WX /wd4191 /O2 /MT /TC /D_WIN32_WINNT=0x0A00 (Join-Path $root 'src/pb_core_host.c') /Fe:pb_core_host.exe
    if ($LASTEXITCODE -ne 0) { throw "CORE_HOST_BUILD_FAILED: $LASTEXITCODE" }
} finally { Pop-Location }
