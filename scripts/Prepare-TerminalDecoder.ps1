[CmdletBinding()]
param([string]$PythonExecutable = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PythonExecutable)) {
    foreach ($relative in @('bin/dev-venv/Scripts/python.exe')) {
        $candidate = Join-Path $root $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $PythonExecutable = $candidate; break }
    }
}
if (-not (Test-Path -LiteralPath $PythonExecutable -PathType Leaf)) { throw 'TERMINAL_DECODER_PYTHON_REQUIRED' }
$destination = Join-Path $root 'bin/terminal-decoder'
$wheelhouse = Join-Path $destination 'wheelhouse'
$packages = Join-Path $destination 'packages'
$requirements = Join-Path $root 'config/terminal-decoder-requirements.txt'
$null = New-Item -ItemType Directory -Path $wheelhouse,$packages -Force
& $PythonExecutable -m pip download --only-binary=:all: --require-hashes --dest $wheelhouse -r $requirements
if ($LASTEXITCODE -ne 0) { throw 'TERMINAL_DECODER_DOWNLOAD_FAILED' }
& $PythonExecutable -m pip install --no-index --find-links $wheelhouse --require-hashes --target $packages --upgrade -r $requirements
if ($LASTEXITCODE -ne 0) { throw 'TERMINAL_DECODER_PACKAGE_PREPARATION_FAILED' }
Write-Output 'Terminal decoder packages prepared. Libraries and their licenses remain separate; no tests or product runtime started.'
