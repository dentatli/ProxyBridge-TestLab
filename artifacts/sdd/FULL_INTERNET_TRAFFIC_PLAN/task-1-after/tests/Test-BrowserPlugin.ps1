[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python -ErrorAction Stop).Source
$fixture = Join-Path $PSScriptRoot 'fixtures/browser/fake_browser.py'
$temp = New-TestDirectory
$expectedContentHash = '388845361f44c3de3ce6182455dc3ef7736448a68530cc0e9c43448560cd066c'
$expectedImageHash = (Get-FileHash -LiteralPath $python -Algorithm SHA256).Hash.ToLowerInvariant()

function Invoke-BrowserFixtureCase {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [string[]]$BrowserArguments = @(),
        [string]$ExpectedError = ''
    )
    $profile = Join-Path $temp ("profile-" + $Mode)
    $downloads = Join-Path $temp ("downloads-" + $Mode)
    $driver = Join-Path $temp ("run_browser_" + $Mode + '.py')
    $argumentsJson = ConvertTo-Json -InputObject (@($fixture) + @($BrowserArguments)) -Compress
    $driverText = @"
import json
import os
import sys
sys.path.insert(0, r'$($root.Replace('\','\\'))\\src\\protocol_worker')
from model import WorkerContractError, WorkerPlan
import plugins.browser as browser
plan = WorkerPlan(raw={
    'run_id': 'm15-browser-run', 'scenario_id': 'canary-browser-download', 'attempt_id': 'attempt-1', 'flow_id': 'flow-1',
    'plugin_id': 'browser-worker', 'protocol_family': 'browser-web', 'transport': 'TCP', 'operation_timeout_ms': 1000,
    'parameters': {
        'browser_executable': r'$($python.Replace('\','\\'))',
        'expected_browser_sha256': '$expectedImageHash',
        'expected_browser_identity': 'Fixture Chromium', 'expected_browser_version': '123.0.0.0',
        'browser_arguments': $argumentsJson,
        'target_url': 'https://testlab.invalid/browser/download',
        'profile_dir': r'$($profile.Replace('\','\\'))', 'download_dir': r'$($downloads.Replace('\','\\'))',
        'expected_content_sha256': '$expectedContentHash', 'expected_response_status': 200,
        'expected_negotiated_protocol': 'h2', 'virtual_time_budget_ms': 250, 'actual_path_timeout_ms': 100
    },
    'expected': {'outcome': 'response'}, 'capabilities': []
})
os.environ['PB_BROWSER_FIXTURE_MODE'] = '$Mode'
if '$Mode' in ('path-query-timeout', 'exit-before-path'):
    browser._query_process_image = lambda pid: (_ for _ in ()).throw(WorkerContractError('BROWSER_OBSERVED_PATH_UNAVAILABLE'))
elif '$Mode' == 'path-mismatch':
    browser._query_process_image = lambda pid: r'C:\\fixture\\wrong-browser.exe'
elif '$Mode' == 'cleanup-failure':
    browser._terminate_tree = lambda root_pid, known_pids: False
try:
    print(json.dumps({'record': browser.run_browser(plan)}, separators=(',', ':')))
except WorkerContractError as exc:
    print(json.dumps({'error': str(exc)}, separators=(',', ':')))
"@
    Write-TestUtf8NoBom $driver $driverText
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $python
    $processInfo.Arguments = '"' + $driver.Replace('"', '\"') + '"'
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($processInfo)
    Assert-True $process.WaitForExit(10000) "browser fixture $Mode must complete within the bounded timeout"
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    Assert-Equal 0 $process.ExitCode "browser fixture $Mode driver must complete: $stderr"
    $result = $stdout | ConvertFrom-Json
    if ($ExpectedError) {
        Assert-Equal $ExpectedError ([string]$result.error) "browser fixture $Mode must fail closed"
        Assert-True ($null -eq $result.PSObject.Properties['record']) "browser fixture $Mode must never emit PASS evidence"
    }
    return $result
}

try {
    $success = Invoke-BrowserFixtureCase -Mode 'success'
    $successError = if ($null -ne $success.PSObject.Properties['error']) { [string]$success.error } else { '' }
    Assert-True ($null -ne $success.PSObject.Properties['record']) "supported Chromium-only fixture must produce evidence instead of rejecting fake-only switches: $successError"
    $records = @($success.record)
    Assert-Equal 1 $records.Count 'real Chromium-style dumped DOM must produce one evidence record'
    $record = $records[0]
    Assert-Equal 'PASS' ([string]$record.result) 'matching dumped DOM marker must pass'
    Assert-Equal 'Fixture Chromium' ([string]$record.browser_identity) 'controller-provided browser identity must be recorded'
    Assert-Equal '123.0.0.0' ([string]$record.browser_version) 'controller-provided browser version must be recorded'
    Assert-Equal $expectedImageHash ([string]$record.browser_image_sha256) 'exact prelaunch browser image hash must be recorded'
    Assert-Equal ([System.IO.Path]::GetFullPath($python)) ([string]$record.browser_executable_observed) 'observed browser image must come from the process query'
    Assert-Equal 'PATH_OBTAINED' ([string]$record.actual_path_probe_status) 'actual path probe must report success separately'
    Assert-True ([int]$record.actual_path_probe_attempts -ge 1) 'actual path probe must retain attempt count'
    Assert-True ([int]$record.actual_path_probe_elapsed_ms -ge 0) 'actual path probe must retain elapsed time'
    Assert-Equal 'h2' ([string]$record.negotiated_protocol) 'controlled navigation must record browser-observed protocol'
    Assert-Equal 200 ([int]$record.response_status) 'controlled navigation must record response status'
    Assert-Equal $expectedContentHash ([string]$record.content_sha256) 'controlled navigation must record deterministic content hash'
    Assert-True ([bool]$record.process_tree_cleaned) 'browser process tree must be verified clean before PASS'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $temp 'profile-success'))) 'isolated browser profile must be removed after verified cleanup'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $temp 'downloads-success'))) 'isolated download directory must be removed after verified cleanup'

    Invoke-BrowserFixtureCase -Mode 'success' -BrowserArguments @('--testlab-unsupported') -ExpectedError 'BROWSER_ARGUMENT_FORBIDDEN' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'malformed-marker' -ExpectedError 'BROWSER_DOM_MARKER_INVALID' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'multiple-markers' -ExpectedError 'BROWSER_DOM_MARKER_INVALID' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'wrong-content-hash' -ExpectedError 'BROWSER_CONTENT_HASH_MISMATCH' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'path-query-timeout' -ExpectedError 'BROWSER_OBSERVED_PATH_QUERY_TIMEOUT' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'exit-before-path' -ExpectedError 'BROWSER_EXITED_BEFORE_PATH_OBSERVABLE' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'path-mismatch' -ExpectedError 'BROWSER_OBSERVED_PATH_MISMATCH' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'cleanup-failure' -ExpectedError 'BROWSER_TREE_CLEANUP_FAILED' | Out-Null
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: isolated browser worker core'
