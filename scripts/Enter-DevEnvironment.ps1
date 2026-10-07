# Dot-source this script to configure only the current PowerShell process.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$devVswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $devVswhere)) { throw 'Visual Studio Installer / vswhere not found.' }
$devVsRoot = & $devVswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $devVsRoot) { throw 'Install Visual Studio C++ x64 tools first.' }
Import-Module (Join-Path $devVsRoot 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $devVsRoot -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
$devDotnetRoot = Join-Path $env:ProgramFiles 'dotnet'
if (Test-Path (Join-Path $devDotnetRoot 'dotnet.exe')) { $env:PATH = $devDotnetRoot + ';' + $env:PATH }
$devPythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311'
if (Test-Path (Join-Path $devPythonRoot 'python.exe')) { $env:PATH = $devPythonRoot + ';' + $env:PATH }
$devVenvScripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\dev-venv\Scripts'
if (Test-Path (Join-Path $devVenvScripts 'python.exe')) { $env:PATH = $devVenvScripts + ';' + $env:PATH }
Write-Output 'Development shell ready (MSVC x64). No tests or traffic started.'
