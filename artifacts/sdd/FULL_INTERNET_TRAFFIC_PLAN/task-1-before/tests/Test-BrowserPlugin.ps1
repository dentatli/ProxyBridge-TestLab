[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python -ErrorAction Stop).Source
$fixture = Join-Path $PSScriptRoot 'fixtures/browser/fake_browser.py'
$temp = New-TestDirectory
try {
    $profile = Join-Path $temp 'profile'
    $downloads = Join-Path $temp 'downloads'
    $expectedHash = '388845361f44c3de3ce6182455dc3ef7736448a68530cc0e9c43448560cd066c'
    $driver = Join-Path $temp 'run_browser_plugin.py'
    $driverText = @"
import json
import sys
from pathlib import Path
sys.path.insert(0, r'$($root.Replace('\','\\'))\\src\\protocol_worker')
from model import WorkerPlan
from plugins.browser import run_browser
plan = WorkerPlan(raw={
    'run_id': 'm15-browser-run', 'scenario_id': 'canary-browser-download', 'attempt_id': 'attempt-1', 'flow_id': 'flow-1',
    'plugin_id': 'browser-worker', 'protocol_family': 'browser-web', 'transport': 'TCP', 'operation_timeout_ms': 5000,
    'parameters': {
        'browser_executable': r'$($python.Replace('\','\\'))',
        'browser_arguments': [r'$($fixture.Replace('\','\\'))', '--testlab-download-content=browser-canary-payload'],
        'target_url': 'https://testlab.invalid/browser/download',
        'profile_dir': r'$($profile.Replace('\','\\'))',
        'download_dir': r'$($downloads.Replace('\','\\'))',
        'expected_download_sha256': '$expectedHash', 'expected_response_status': 200,
        'expected_negotiated_protocol': 'h2', 'actual_path_timeout_ms': 1000
    },
    'expected': {'outcome': 'response'}, 'capabilities': []
})
print(json.dumps(run_browser(plan), separators=(',', ':')))
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
    Assert-True $process.WaitForExit(10000) 'browser plugin driver must complete within the bounded timeout'
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    Assert-Equal 0 $process.ExitCode "browser plugin must run against the deterministic fake browser: $stderr"
    $records = @($stdout | ConvertFrom-Json)
    Assert-Equal 1 $records.Count 'browser plugin must emit one evidence record'
    $record = $records[0]
    Assert-Equal 'PASS' ([string]$record.result) 'matching DOM marker and download hash must pass'
    Assert-Equal 'PB_TESTLAB_BROWSER_READY' ([string]$record.dom_marker) 'browser DOM marker must be recorded'
    Assert-Equal $expectedHash ([string]$record.download_sha256) 'download hash must be independently validated'
    Assert-Equal ([System.IO.Path]::GetFullPath($python)) ([string]$record.browser_executable_observed) 'observed browser image must be the actual process image'
    Assert-True (@($record.browser_process_tree_pids).Count -ge 1) 'browser evidence must include the observed process tree'
    Assert-Equal 'Fake Chromium' ([string]$record.browser_identity) 'browser identity must come from the deterministic DOM marker'
    Assert-Equal '1.0.0' ([string]$record.browser_version) 'browser version must come from the deterministic DOM marker'
    Assert-Equal 'h2' ([string]$record.negotiated_protocol) 'controlled browser navigation must record negotiated protocol'
    Assert-Equal 200 ([int]$record.response_status) 'controlled browser navigation must record response status'
    Assert-Equal $expectedHash ([string]$record.content_sha256) 'controlled browser navigation must record content hash'
    Assert-True ([bool]$record.process_tree_cleaned) 'browser process tree must be verified clean before PASS'
    Assert-True (-not (Test-Path -LiteralPath $profile)) 'isolated browser profile must be removed after verified cleanup'
    Assert-True (-not (Test-Path -LiteralPath $downloads)) 'isolated download directory must be removed after verified cleanup'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: isolated browser worker core'
