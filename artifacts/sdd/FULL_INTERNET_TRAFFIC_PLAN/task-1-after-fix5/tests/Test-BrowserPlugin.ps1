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
    $cleanupErrors = [System.Collections.Generic.List[string]]::new()
    $driverInitiallyExited = $false
    try { $driverInitiallyExited = $Process.HasExited } catch { $cleanupErrors.Add('driver initial status') }
    if ($driverInitiallyExited) { return }
    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $taskkill
    $startInfo.Arguments = "/PID $($Process.Id) /T /F"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $killer = $null
    $taskkillTimedOut = $false
    try {
        $killer = if ($null -ne $StartTaskkill) { & $StartTaskkill $startInfo } else { [System.Diagnostics.Process]::Start($startInfo) }
    }
    catch {
        $cleanupErrors.Add('taskkill start')
    }
    if ($null -ne $killer) {
        try {
            if (-not $killer.WaitForExit($TaskkillTimeoutMs)) { $taskkillTimedOut = $true }
        }
        catch {
            $cleanupErrors.Add('taskkill wait')
        }
        $killerExited = $false
        try { $killerExited = $killer.HasExited } catch { $cleanupErrors.Add('taskkill status') }
        if (-not $killerExited) {
            try { $killer.Kill() } catch { $cleanupErrors.Add('taskkill kill') }
        }
    }

    $driverExitedBeforeFallback = $false
    try { $driverExitedBeforeFallback = $Process.HasExited } catch { $cleanupErrors.Add('driver fallback status') }
    if (-not $driverExitedBeforeFallback) {
        try { $Process.Kill() } catch { $cleanupErrors.Add('driver fallback kill') }
    }

    $driverVerifiedExited = $false
    try { $driverVerifiedExited = $Process.WaitForExit($DriverTimeoutMs) } catch { $cleanupErrors.Add('driver final wait') }
    try {
        if (-not $Process.HasExited) { $driverVerifiedExited = $false }
    }
    catch {
        $cleanupErrors.Add('driver final status')
    }
    if (-not $driverVerifiedExited) {
        throw 'ASSERTION FAILED: driver-tree cleanup did not terminate the driver'
    }
    if ($cleanupErrors.Count -gt 0) {
        throw 'ASSERTION FAILED: driver-tree cleanup operation failed'
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
import ctypes
import json
import os
import sys
sys.path.insert(0, r'$($root.Replace('\','\\'))\\src\\protocol_worker')
from model import WorkerContractError, WorkerPlan
import plugins.browser as browser

def duplicate_process_handle(handle):
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    get_current_process = kernel32.GetCurrentProcess
    get_current_process.restype = ctypes.c_void_p
    duplicate_handle = kernel32.DuplicateHandle
    duplicate_handle.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    duplicate_handle.restype = ctypes.c_bool
    current = get_current_process()
    duplicate = ctypes.c_void_p()
    if not duplicate_handle(current, handle, current, ctypes.byref(duplicate), 0, False, 2):
        raise OSError('fixture DuplicateHandle failure')
    return int(duplicate.value)

def exact_process_handle_state(handle, terminate=False):
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    terminate_process = kernel32.TerminateProcess
    terminate_process.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    terminate_process.restype = ctypes.c_bool
    wait_for_single_object = kernel32.WaitForSingleObject
    wait_for_single_object.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    wait_for_single_object.restype = ctypes.c_uint32
    get_exit_code = kernel32.GetExitCodeProcess
    get_exit_code.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    get_exit_code.restype = ctypes.c_bool
    if terminate:
        terminate_process(handle, 1)
    wait_state = wait_for_single_object(handle, 2000 if terminate else 0)
    exit_code = ctypes.c_uint32()
    exited = wait_state == 0 and bool(get_exit_code(handle, ctypes.byref(exit_code))) and exit_code.value != 259
    return exited

def close_exact_handle(handle):
    close_handle = ctypes.WinDLL('kernel32', use_last_error=True).CloseHandle
    close_handle.argtypes = [ctypes.c_void_p]
    close_handle.restype = ctypes.c_bool
    return bool(close_handle(handle))

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
elif '$Mode' in ('reader-open-failure', 'reader-job-containment', 'reader-stream-close-exception'):
    created_pids = []
    retained_process_handles = []
    assigned_pids = []
    expected_thread_handles = []
    expected_process_handles = []
    close_attempts = []
    failed_stream_retained = []
    original_assign = browser._BrowserJob.assign
    original_open_reader = browser._SuspendedBrowserProcess._open_reader
    original_close_handle = browser._SuspendedBrowserProcess._close_handle
    original_process_close = browser._SuspendedBrowserProcess.close

    def tracked_assign(self, pid):
        result = original_assign(self, pid)
        assigned_pids.append(pid)
        return result

    def tracked_close_handle(self, handle):
        close_attempts.append(handle)
        return original_close_handle(self, handle)

    def tracked_process_close(self):
        try:
            return original_process_close(self)
        finally:
            failed_stream_retained.append(self.stdout is not None)

    class CloseExceptionStream:
        def __init__(self, stream):
            self._stream = stream

        def close(self):
            self._stream.close()
            raise RuntimeError('fixture stdout close exception')

        def __getattr__(self, name):
            return getattr(self._stream, name)

    browser._BrowserJob.assign = tracked_assign
    browser._SuspendedBrowserProcess._close_handle = tracked_close_handle
    browser._SuspendedBrowserProcess.close = tracked_process_close
    reader_calls = [0]

    def reader_failure(self, handle):
        reader_calls[0] += 1
        if not created_pids:
            created_pids.append(self.pid)
            retained_process_handles.append(duplicate_process_handle(self._process_handle))
            expected_thread_handles.append(self._thread_handle)
            expected_process_handles.append(self._process_handle)
        if '$Mode' == 'reader-job-containment':
            self._kernel32.TerminateProcess = lambda process_handle, exit_code: False
            self._kernel32.WaitForSingleObject = lambda process_handle, timeout_ms: 258
        elif '$Mode' == 'reader-stream-close-exception' and reader_calls[0] == 1:
            return CloseExceptionStream(original_open_reader(self, handle))
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
except BaseException as exc:
    result = {'error': str(exc), 'error_type': type(exc).__name__, 'error_cause': str(exc.__cause__) if exc.__cause__ else ''}
    if '$Mode' == 'ownership-race':
        result['ownership_race_preserved'] = os.path.isdir(r'$($profile.Replace('\','\\'))')
    if '$Mode' in ('reader-open-failure', 'reader-job-containment', 'reader-stream-close-exception'):
        result['created_pid'] = created_pids[0] if created_pids else 0
        retained = retained_process_handles[0] if retained_process_handles else 0
        result['created_root_alive_before_test_cleanup'] = bool(retained and not exact_process_handle_state(retained))
        result['created_root_cleaned_by_test'] = bool(retained and (exact_process_handle_state(retained) or exact_process_handle_state(retained, terminate=True)))
        result['retained_process_handle_closed'] = bool(retained and close_exact_handle(retained))
        result['job_assigned_before_reader_failure'] = bool(created_pids and created_pids[0] in assigned_pids)
        result['thread_close_attempted'] = bool(expected_thread_handles and expected_thread_handles[0] in close_attempts)
        result['process_close_attempted'] = bool(expected_process_handles and expected_process_handles[0] in close_attempts)
        result['failed_stream_retained'] = bool(failed_stream_retained and failed_stream_retained[-1])
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
    $readerJobContainment = Invoke-BrowserFixtureCase -Mode 'reader-job-containment'
    $readerStreamCloseFailure = Invoke-BrowserFixtureCase -Mode 'reader-stream-close-exception'
    Assert-True ([int]$readerOpenFailure.created_pid -gt 0) 'reader-open regression must record the created suspended root PID'
    Assert-True ([bool]$readerJobContainment.job_assigned_before_reader_failure) "persistent TerminateProcess/Wait failure must occur only after Job assignment; root_alive=$([bool]$readerJobContainment.created_root_alive_before_test_cleanup); later_thread_close=$([bool]$readerStreamCloseFailure.thread_close_attempted); later_process_close=$([bool]$readerStreamCloseFailure.process_close_attempted); cleanup_error=$([string]$readerStreamCloseFailure.error)"
    Assert-True (-not [bool]$readerJobContainment.created_root_alive_before_test_cleanup) 'Job containment must remove the exact suspended root despite persistent old-path TerminateProcess/Wait failure'
    Assert-True ([bool]$readerJobContainment.created_root_cleaned_by_test) 'persistent-failure regression cleanup must leave no fixture root behind'
    Assert-True ([bool]$readerJobContainment.retained_process_handle_closed) 'persistent-failure regression must close its duplicate exact process handle'
    Assert-Equal 'BROWSER_SUSPENDED_LAUNCH_FAILED' ([string]$readerJobContainment.error) 'post-assignment reader failure must preserve the stable launch error after verified containment'
    Assert-True ($null -eq $readerJobContainment.PSObject.Properties['record']) 'persistent TerminateProcess/Wait failure must never emit PASS evidence'
    Assert-True (-not [bool]$readerOpenFailure.created_root_alive_before_test_cleanup) 'reader-open failure must terminate the created suspended root before returning control'
    Assert-True ([bool]$readerOpenFailure.created_root_cleaned_by_test) 'reader-open regression cleanup must leave no fixture root behind'
    Assert-True ([bool]$readerOpenFailure.retained_process_handle_closed) 'reader-open regression must close its duplicate exact process handle'
    Assert-True ([bool]$readerOpenFailure.job_assigned_before_reader_failure) 'ordinary reader-open failure must occur only after Job assignment'
    Assert-Equal 'BROWSER_SUSPENDED_LAUNCH_FAILED' ([string]$readerOpenFailure.error) 'reader-open failure must use the stable launch error'
    Assert-True ($null -eq $readerOpenFailure.PSObject.Properties['record']) 'reader-open failure must never emit PASS evidence'
    Assert-True ([bool]$readerStreamCloseFailure.job_assigned_before_reader_failure) 'partial reader setup must occur only after Job assignment'
    Assert-True (-not [bool]$readerStreamCloseFailure.created_root_alive_before_test_cleanup) 'partial reader setup failure must leave the exact suspended root contained'
    Assert-True ([bool]$readerStreamCloseFailure.thread_close_attempted) 'stdout close exception must not skip the later primary-thread handle close'
    Assert-True ([bool]$readerStreamCloseFailure.process_close_attempted) 'stdout close exception must not skip the later process handle close'
    Assert-True ([bool]$readerStreamCloseFailure.failed_stream_retained) 'failed stdout close must retain the stream reference for fail-closed ownership'
    Assert-Equal 'BROWSER_TREE_CLEANUP_FAILED' ([string]$readerStreamCloseFailure.error) 'stream close failure must win as the stable cleanup error'
    Assert-True ($null -eq $readerStreamCloseFailure.PSObject.Properties['record']) 'stream close failure must never emit PASS evidence'
    Assert-True ([bool]$readerStreamCloseFailure.created_root_cleaned_by_test) 'stream-close regression cleanup must leave no fixture root behind'
    Assert-True ([bool]$readerStreamCloseFailure.retained_process_handle_closed) 'stream-close regression must close its duplicate exact process handle'
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
    $exceptionDriver = [System.Diagnostics.Process]::Start($driverInfo)
    try {
        $throwingKiller = [pscustomobject]@{}
        $throwingKiller | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($timeoutMs) throw 'fixture taskkill WaitForExit exception' }
        $throwingKiller | Add-Member -MemberType ScriptProperty -Name HasExited -Value { throw 'fixture taskkill HasExited exception' }
        $throwingKiller | Add-Member -MemberType ScriptMethod -Name Kill -Value { throw 'fixture taskkill Kill exception' }
        $cleanupExceptionThrown = $false
        try {
            Stop-TestDriverTree -Process $exceptionDriver -DriverTimeoutMs 1000 -StartTaskkill { param($ignoredStartInfo) return $throwingKiller }
        }
        catch {
            Assert-Equal 'ASSERTION FAILED: driver-tree cleanup operation failed' $_.Exception.Message 'taskkill exceptions must be reported only after exact-driver fallback and final verification'
            $cleanupExceptionThrown = $true
        }
        Assert-True $cleanupExceptionThrown 'forced taskkill exception must be reported'
        Assert-True $exceptionDriver.HasExited 'taskkill exception fallback must terminate and verify the exact driver before throwing'
    }
    finally {
        if (-not $exceptionDriver.HasExited) { $exceptionDriver.Kill() }
    }
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: isolated browser worker core'
