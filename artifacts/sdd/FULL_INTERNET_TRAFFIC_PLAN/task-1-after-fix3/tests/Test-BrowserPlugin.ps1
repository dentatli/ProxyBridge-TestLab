[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python -ErrorAction Stop).Source
$fixture = Join-Path $PSScriptRoot 'fixtures/browser/fake_browser.py'
$temp = New-TestDirectory
$fixtureBrowser = Join-Path $temp 'fixture-chromium.exe'
$expectedContentHash = '388845361f44c3de3ce6182455dc3ef7736448a68530cc0e9c43448560cd066c'
$fixtureSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
public static class FixtureChromium {
    private static int Reject() { return 21; }
    public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--fixture-child-sleep") { Thread.Sleep(1000); return 0; }
        string mode = Environment.GetEnvironmentVariable("PB_BROWSER_FIXTURE_MODE") ?? "success";
        string[] fixedArgs = { "--headless=new", "--disable-background-networking", "--disable-sync", "--no-first-run", "--no-default-browser-check", "--dump-dom" };
        if (args.Length != fixedArgs.Length + 3 || fixedArgs.Any(value => args.Count(item => item == value) != 1)) return Reject();
        string[] budget = args.Where(value => value.StartsWith("--virtual-time-budget=", StringComparison.Ordinal)).ToArray();
        int budgetValue;
        if (budget.Length != 1 || !Int32.TryParse(budget[0].Substring("--virtual-time-budget=".Length), out budgetValue) || budgetValue <= 0 || budgetValue > 1000) return Reject();
        string[] profiles = args.Where(value => value.StartsWith("--user-data-dir=", StringComparison.Ordinal)).ToArray();
        if (profiles.Length != 1) return Reject();
        string profile = profiles[0].Substring("--user-data-dir=".Length);
        if (!Directory.Exists(profile) || Directory.EnumerateFileSystemEntries(profile).Any()) return Reject();
        if (new DirectoryInfo(Environment.CurrentDirectory).Name != "downloads-" + mode) return Reject();
        if (args.Count(value => value.StartsWith("http://", StringComparison.Ordinal) || value.StartsWith("https://", StringComparison.Ordinal)) != 1 || args.Last() != "https://testlab.invalid/browser/download") return Reject();
        if (args.Any(value => value.StartsWith("--testlab-", StringComparison.Ordinal))) return 20;
        string markerJson = "{\"dom_marker\":\"PB_TESTLAB_BROWSER_READY\",\"negotiated_protocol\":\"h2\",\"response_status\":200,\"content_sha256\":\"388845361f44c3de3ce6182455dc3ef7736448a68530cc0e9c43448560cd066c\"}";
        if (mode == "malformed-marker") markerJson = "not-json";
        if (mode == "wrong-content-hash") markerJson = "{\"dom_marker\":\"PB_TESTLAB_BROWSER_READY\",\"negotiated_protocol\":\"h2\",\"response_status\":200,\"content_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\"}";
        string script = "<script id=\"proxybridge-testlab-browser-result\" type=\"application/json\">" + markerJson + "</script>";
        Console.WriteLine("<html><body>" + script + (mode == "multiple-markers" ? script : "") + "</body></html>");
        Console.Out.Flush();
        if (mode == "late-child") {
            Process.Start(new ProcessStartInfo { FileName = Process.GetCurrentProcess().MainModule.FileName, Arguments = "--fixture-child-sleep", UseShellExecute = false, CreateNoWindow = true });
            Thread.Sleep(200);
            return 0;
        }
        if (mode == "exit-before-path") return 0;
        Thread.Sleep(200);
        return 0;
    }
}
"@
Add-Type -TypeDefinition $fixtureSource -OutputAssembly $fixtureBrowser -OutputType ConsoleApplication
$expectedImageHash = (Get-FileHash -LiteralPath $fixtureBrowser -Algorithm SHA256).Hash.ToLowerInvariant()

function Stop-TestDriverTree {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [int]$TaskkillTimeoutMs = 5000,
        [int]$DriverTimeoutMs = 5000,
        [scriptblock]$StartTaskkill = $null
    )
    if ($Process.HasExited) { return }
    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $taskkill
    $startInfo.Arguments = "/PID $($Process.Id) /T /F"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $killer = if ($null -ne $StartTaskkill) { & $StartTaskkill $startInfo } else { [System.Diagnostics.Process]::Start($startInfo) }
    $taskkillTimedOut = $false
    try {
        if (-not $killer.WaitForExit($TaskkillTimeoutMs)) {
            $taskkillTimedOut = $true
        }
    }
    finally {
        if (-not $killer.HasExited) { $killer.Kill() }
        if ($taskkillTimedOut -and -not $Process.HasExited) { $Process.Kill() }
    }
    if (-not $Process.WaitForExit($DriverTimeoutMs)) {
        try { $Process.Kill() } finally { throw 'ASSERTION FAILED: driver-tree cleanup did not terminate the driver' }
    }
    if ($taskkillTimedOut) {
        throw 'ASSERTION FAILED: driver-tree cleanup timed out'
    }
}

function Invoke-BrowserFixtureCase {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [string[]]$BrowserArguments = @(),
        [string]$ExpectedError = ''
    )
    $profile = Join-Path $temp ("profile-" + $Mode)
    $downloads = Join-Path $temp ("downloads-" + $Mode)
    $driver = Join-Path $temp ("run_browser_" + $Mode + '.py')
    $argumentsJson = ConvertTo-Json -InputObject @($BrowserArguments) -Compress
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
        'browser_executable': r'$($fixtureBrowser.Replace('\','\\'))',
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
elif '$Mode' == 'job-close-failure':
    browser._BrowserJob.close = lambda self: False
elif '$Mode' == 'job-query-failure':
    browser._BrowserJob.process_ids = lambda self: (_ for _ in ()).throw(WorkerContractError('BROWSER_JOB_QUERY_FAILED'))
elif '$Mode' == 'job-assign-failure':
    browser._BrowserJob.assign = lambda self, pid: (_ for _ in ()).throw(WorkerContractError('BROWSER_JOB_ASSIGN_FAILED'))
elif '$Mode' == 'resume-failure':
    browser._SuspendedBrowserProcess.resume = lambda self: (_ for _ in ()).throw(WorkerContractError('BROWSER_RESUME_FAILED'))
elif '$Mode' == 'ownership-race':
    original_create = browser._create_isolated_directories
    def ownership_race(profile, downloads):
        profile.mkdir(parents=True, exist_ok=False)
        return original_create(profile, downloads)
    browser._create_isolated_directories = ownership_race
elif '$Mode' == 'reader-open-failure':
    created_pids = []
    def reader_failure(self, handle):
        created_pids.append(self.pid)
        raise OSError('fixture reader open failure')
    browser._SuspendedBrowserProcess._open_reader = reader_failure
elif '$Mode' in ('stderr-pipe-failure', 'nul-input-failure'):
    acquired_handles = []
    closed_handles = []
    original_create_pipe = browser._SuspendedBrowserProcess._create_pipe
    original_close_handle = browser._SuspendedBrowserProcess._close_handle
    def tracked_create_pipe(self):
        pair = original_create_pipe(self)
        acquired_handles.extend(pair)
        return pair
    def tracked_close_handle(self, handle):
        if handle in acquired_handles:
            closed_handles.append(handle)
        return original_close_handle(self, handle)
    browser._SuspendedBrowserProcess._create_pipe = tracked_create_pipe
    browser._SuspendedBrowserProcess._close_handle = tracked_close_handle
    if '$Mode' == 'stderr-pipe-failure':
        create_calls = [0]
        def fail_stderr_pipe(self):
            create_calls[0] += 1
            if create_calls[0] == 2:
                raise WorkerContractError('BROWSER_SUSPENDED_LAUNCH_FAILED')
            return tracked_create_pipe(self)
        browser._SuspendedBrowserProcess._create_pipe = fail_stderr_pipe
    else:
        def fail_null_input(self):
            raise WorkerContractError('BROWSER_SUSPENDED_LAUNCH_FAILED')
        browser._SuspendedBrowserProcess._open_null_input = fail_null_input
try:
    print(json.dumps({'record': browser.run_browser(plan)}, separators=(',', ':')))
except WorkerContractError as exc:
    result = {'error': str(exc)}
    if '$Mode' == 'ownership-race':
        result['ownership_race_preserved'] = os.path.isdir(r'$($profile.Replace('\','\\'))')
    if '$Mode' == 'reader-open-failure':
        result['created_pid'] = created_pids[0] if created_pids else 0
        result['created_root_alive_before_test_cleanup'] = bool(created_pids and browser._process_running(created_pids[0]))
        result['created_root_cleaned_by_test'] = bool(created_pids and browser._terminate_tree(created_pids[0], [created_pids[0]]))
    if '$Mode' in ('stderr-pipe-failure', 'nul-input-failure'):
        result['resource_handles_closed'] = bool(acquired_handles) and set(acquired_handles).issubset(closed_handles)
    print(json.dumps(result, separators=(',', ':')))
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
    $completed = $process.WaitForExit(10000)
    if (-not $completed) {
        try { Stop-TestDriverTree -Process $process } finally { throw "ASSERTION FAILED: browser fixture $Mode timed out after driver-tree cleanup" }
    }
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    Assert-Equal 0 $process.ExitCode "browser fixture $Mode driver must complete: $stderr"
    $result = $stdout | ConvertFrom-Json
    if ($ExpectedError) {
        $actualError = if ($null -ne $result.PSObject.Properties['error']) { [string]$result.error } else { '' }
        Assert-Equal $ExpectedError $actualError "browser fixture $Mode must fail closed"
        Assert-True ($null -eq $result.PSObject.Properties['record']) "browser fixture $Mode must never emit PASS evidence"
    }
    return $result
}

try {
    $success = Invoke-BrowserFixtureCase -Mode 'late-child'
    $successError = if ($null -ne $success.PSObject.Properties['error']) { [string]$success.error } else { '' }
    Assert-True ($null -ne $success.PSObject.Properties['record']) "supported Chromium-only fixture must produce evidence instead of rejecting fake-only switches: $successError"
    $records = @($success.record)
    Assert-Equal 1 $records.Count 'real Chromium-style dumped DOM must produce one evidence record'
    $record = $records[0]
    Assert-Equal 'PASS' ([string]$record.result) 'matching dumped DOM marker must pass'
    Assert-Equal 'Fixture Chromium' ([string]$record.browser_identity) 'controller-provided browser identity must be recorded'
    Assert-Equal '123.0.0.0' ([string]$record.browser_version) 'controller-provided browser version must be recorded'
    Assert-Equal $expectedImageHash ([string]$record.browser_image_sha256) 'exact prelaunch browser image hash must be recorded'
    Assert-Equal ([System.IO.Path]::GetFullPath($fixtureBrowser)) ([string]$record.browser_executable_observed) 'observed browser image must come from the process query'
    Assert-Equal 'PATH_OBTAINED' ([string]$record.actual_path_probe_status) 'actual path probe must report success separately'
    Assert-True ([int]$record.actual_path_probe_attempts -ge 1) 'actual path probe must retain attempt count'
    Assert-True ([int]$record.actual_path_probe_elapsed_ms -ge 0) 'actual path probe must retain elapsed time'
    Assert-Equal 'h2' ([string]$record.negotiated_protocol) 'controlled navigation must record browser-observed protocol'
    Assert-Equal 200 ([int]$record.response_status) 'controlled navigation must record response status'
    Assert-Equal $expectedContentHash ([string]$record.content_sha256) 'controlled navigation must record deterministic content hash'
    Assert-True ([bool]$record.process_tree_cleaned) 'browser process tree must be verified clean before PASS'
    Assert-True (@($record.browser_process_tree_pids).Count -ge 2) 'late browser child must be contained, observed and cleaned before PASS'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $temp 'profile-late-child'))) 'isolated browser profile must be removed after verified cleanup'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $temp 'downloads-late-child'))) 'isolated download directory must be removed after verified cleanup'

    Invoke-BrowserFixtureCase -Mode 'success' -BrowserArguments @('--testlab-unsupported') -ExpectedError 'BROWSER_ARGUMENT_FORBIDDEN' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'success' -BrowserArguments @('https://untrusted.invalid/') -ExpectedError 'BROWSER_ARGUMENT_FORBIDDEN' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'success' -BrowserArguments @('--headless=old') -ExpectedError 'BROWSER_ARGUMENT_FORBIDDEN' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'success' -BrowserArguments @('--user-data-dir=C:\\untrusted') -ExpectedError 'BROWSER_ARGUMENT_FORBIDDEN' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'malformed-marker' -ExpectedError 'BROWSER_DOM_MARKER_INVALID' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'multiple-markers' -ExpectedError 'BROWSER_DOM_MARKER_INVALID' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'wrong-content-hash' -ExpectedError 'BROWSER_CONTENT_HASH_MISMATCH' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'path-query-timeout' -ExpectedError 'BROWSER_OBSERVED_PATH_QUERY_TIMEOUT' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'exit-before-path' -ExpectedError 'BROWSER_EXITED_BEFORE_PATH_OBSERVABLE' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'path-mismatch' -ExpectedError 'BROWSER_OBSERVED_PATH_MISMATCH' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'cleanup-failure' -ExpectedError 'BROWSER_TREE_CLEANUP_FAILED' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'job-close-failure' -ExpectedError 'BROWSER_TREE_CLEANUP_FAILED' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'job-query-failure' -ExpectedError 'BROWSER_TREE_CLEANUP_FAILED' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'job-assign-failure' -ExpectedError 'BROWSER_JOB_ASSIGN_FAILED' | Out-Null
    Invoke-BrowserFixtureCase -Mode 'resume-failure' -ExpectedError 'BROWSER_RESUME_FAILED' | Out-Null
    $ownershipRace = Invoke-BrowserFixtureCase -Mode 'ownership-race' -ExpectedError 'BROWSER_ISOLATION_SETUP_FAILED'
    Assert-True ([bool]$ownershipRace.ownership_race_preserved) 'worker must not remove a directory won by another actor during setup'
    $readerOpenFailure = Invoke-BrowserFixtureCase -Mode 'reader-open-failure'
    Assert-True ([int]$readerOpenFailure.created_pid -gt 0) 'reader-open regression must record the created suspended root PID'
    Assert-True (-not [bool]$readerOpenFailure.created_root_alive_before_test_cleanup) 'reader-open failure must terminate the created suspended root before returning control'
    Assert-True ([bool]$readerOpenFailure.created_root_cleaned_by_test) 'reader-open regression cleanup must leave no fixture root behind'
    Assert-Equal 'BROWSER_SUSPENDED_LAUNCH_FAILED' ([string]$readerOpenFailure.error) 'reader-open failure must use the stable launch error'
    Assert-True ($null -eq $readerOpenFailure.PSObject.Properties['record']) 'reader-open failure must never emit PASS evidence'
    $stderrPipeFailure = Invoke-BrowserFixtureCase -Mode 'stderr-pipe-failure' -ExpectedError 'BROWSER_SUSPENDED_LAUNCH_FAILED'
    Assert-True ([bool]$stderrPipeFailure.resource_handles_closed) 'stderr-pipe acquisition failure must close every previously acquired pipe handle'
    $nulInputFailure = Invoke-BrowserFixtureCase -Mode 'nul-input-failure' -ExpectedError 'BROWSER_SUSPENDED_LAUNCH_FAILED'
    Assert-True ([bool]$nulInputFailure.resource_handles_closed) 'NUL-input acquisition failure must close every previously acquired pipe handle'
    $driverInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $driverInfo.FileName = $python
    $driverInfo.Arguments = '-c "import time; time.sleep(10)"'
    $driverInfo.UseShellExecute = $false
    $driverInfo.CreateNoWindow = $true
    $driver = [System.Diagnostics.Process]::Start($driverInfo)
    try {
        $timeoutThrown = $false
        try {
            Stop-TestDriverTree -Process $driver -TaskkillTimeoutMs 50 -DriverTimeoutMs 1000 -StartTaskkill {
                param($ignoredStartInfo)
                $fakeKillerInfo = [System.Diagnostics.ProcessStartInfo]::new()
                $fakeKillerInfo.FileName = $python
                $fakeKillerInfo.Arguments = '-c "import time; time.sleep(10)"'
                $fakeKillerInfo.UseShellExecute = $false
                $fakeKillerInfo.CreateNoWindow = $true
                return [System.Diagnostics.Process]::Start($fakeKillerInfo)
            }
        }
        catch {
            Assert-Equal 'ASSERTION FAILED: driver-tree cleanup timed out' $_.Exception.Message 'taskkill timeout must be reported only after the exact driver fallback'
            $timeoutThrown = $true
        }
        Assert-True $timeoutThrown 'forced taskkill timeout must be reported'
        Assert-True $driver.HasExited 'taskkill timeout fallback must terminate the exact driver before throwing'
    }
    finally {
        if (-not $driver.HasExited) { $driver.Kill() }
    }
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: isolated browser worker core'
