Set-StrictMode -Version Latest
function Get-LocalPythonExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    foreach ($candidate in @((Join-Path $Root 'bin/runtime/python/python.exe'),
        (Join-Path $Root 'bin/protocol-worker/runtime/python/python.exe'),
        (Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw 'LOCAL_PYTHON_MISSING'
}
Export-ModuleMember -Function Get-LocalPythonExecutable
