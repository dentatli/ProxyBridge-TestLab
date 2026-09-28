Set-StrictMode -Version Latest

function Initialize-ProcessSessionType {
    if ($null -ne ('ProxyBridge.TestLab.SafeProcessSession' -as [type])) { return }

    $source = @'
using System;
using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace ProxyBridge.TestLab
{
    public sealed class SafeProcessSession : IDisposable
    {
        private readonly Process process;
        private readonly StringBuilder stdout = new StringBuilder();
        private readonly StringBuilder stderr = new StringBuilder();
        private readonly object stdoutLock = new object();
        private readonly object stderrLock = new object();
        private bool disposed;

        private SafeProcessSession(Process process)
        {
            this.process = process;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args)
            {
                if (args.Data == null) return;
                lock (stdoutLock) stdout.AppendLine(args.Data);
            };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args)
            {
                if (args.Data == null) return;
                lock (stderrLock) stderr.AppendLine(args.Data);
            };
        }

        public static SafeProcessSession Start(string fileName, string arguments)
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = fileName;
            info.Arguments = arguments ?? String.Empty;
            info.UseShellExecute = false;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.CreateNoWindow = true;

            Process process = new Process();
            process.StartInfo = info;
            process.EnableRaisingEvents = true;
            SafeProcessSession session = new SafeProcessSession(process);
            if (!process.Start())
            {
                session.Dispose();
                throw new InvalidOperationException("PROCESS_START_RETURNED_FALSE");
            }
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            return session;
        }

        public int Pid { get { return process.Id; } }

        public string QueryActualPath()
        {
            try { return process.MainModule.FileName; }
            catch { return String.Empty; }
        }

        public bool IsRunning
        {
            get
            {
                try { return !process.HasExited; }
                catch { return false; }
            }
        }

        public bool WaitForExit(int timeoutMs)
        {
            bool completed = process.WaitForExit(Math.Max(1, timeoutMs));
            if (completed) process.WaitForExit();
            return completed;
        }

        public bool WaitForReadiness(string outputRegex, int timeoutMs, int stableMs)
        {
            Stopwatch timer = Stopwatch.StartNew();
            while (timer.ElapsedMilliseconds < Math.Max(1, timeoutMs))
            {
                if (!IsRunning) return false;
                if (!String.IsNullOrWhiteSpace(outputRegex))
                {
                    string captured = Stdout + Environment.NewLine + Stderr;
                    if (Regex.IsMatch(captured, outputRegex, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) return true;
                }
                else if (stableMs > 0 && timer.ElapsedMilliseconds >= stableMs) return true;
                Thread.Sleep(25);
            }
            return false;
        }

        public bool GracefulStop(int timeoutMs)
        {
            if (!IsRunning) return true;
            try
            {
                process.CloseMainWindow();
                return WaitForExit(timeoutMs);
            }
            catch { return false; }
        }

        public void Kill()
        {
            if (!IsRunning) return;
            process.Kill();
            process.WaitForExit();
        }

        public int ExitCode
        {
            get
            {
                if (IsRunning) return -1;
                try { return process.ExitCode; }
                catch { return -1; }
            }
        }

        public string Stdout
        {
            get { lock (stdoutLock) return stdout.ToString(); }
        }

        public string Stderr
        {
            get { lock (stderrLock) return stderr.ToString(); }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            process.Dispose();
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp
}

function ConvertTo-WindowsProcessArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            $null = $builder.Append(('\' * (($backslashes * 2) + 1)))
            $null = $builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { $null = $builder.Append(('\' * $backslashes)); $backslashes = 0 }
        $null = $builder.Append($character)
    }
    if ($backslashes -gt 0) { $null = $builder.Append(('\' * ($backslashes * 2))) }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Join-ProcessArguments {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$Arguments)
    return (@($Arguments | ForEach-Object { ConvertTo-WindowsProcessArgument -Value ([string]$_) }) -join ' ')
}

function New-SystemProcessAdapter {
    [CmdletBinding()]
    param()

    Initialize-ProcessSessionType
    $adapter = [pscustomobject]@{ is_mock = $false }

    $adapter | Add-Member -NotePropertyName GetWatchdogTimeout -NotePropertyValue {
        param($plan)
        $timeout = $(if ($null -ne $plan.PSObject.Properties['process_timeout_ms']) { [long]$plan.process_timeout_ms } elseif ($null -ne $plan.PSObject.Properties['timeout_ms']) { [long]$plan.timeout_ms } else { 0 })
        if ($timeout -lt 1 -or $timeout -gt [int]::MaxValue) { throw 'PROCESS_TIMEOUT_INVALID' }
        return [int]$timeout
    }
    $adapter | Add-Member -NotePropertyName VerifyExecutable -NotePropertyValue {
        param($path, $expectedSha256)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return [pscustomobject]@{ path_verified=$false; hash_verified=$false; status='PATH_MISSING' }
        }
        if ([string]$expectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            return [pscustomobject]@{ path_verified=$true; hash_verified=$false; status='EXPECTED_HASH_INVALID' }
        }
        try { $actualSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        catch { return [pscustomobject]@{ path_verified=$true; hash_verified=$false; status='HASH_QUERY_FAILED' } }
        $hashVerified = [string]::Equals([string]$expectedSha256, [string]$actualSha256, [System.StringComparison]::OrdinalIgnoreCase)
        return [pscustomobject]@{ path_verified=$true; hash_verified=$hashVerified; status=$(if ($hashVerified) { 'VERIFIED' } else { 'HASH_MISMATCH' }) }
    }
    $adapter | Add-Member -NotePropertyName StartProcess -NotePropertyValue {
        param($plan)
        $argumentText = Join-ProcessArguments -Arguments @($plan.arguments)
        $session = [ProxyBridge.TestLab.SafeProcessSession]::Start([string]$plan.executable, $argumentText)
        return [pscustomobject]@{
            pid = $session.Pid
            actual_path = ''
            session = $session
            timed_out = $false
            actual_path_probe_status = 'NOT_STARTED'
            actual_path_probe_attempts = 0
            actual_path_probe_elapsed_ms = 0
        }
    }
    $adapter | Add-Member -NotePropertyName ProbeActualPath -NotePropertyValue {
        param($process, $timeoutMs, $intervalMs)
        $timeout = [Math]::Max(1, [int]$timeoutMs)
        $interval = [Math]::Max(25, [Math]::Min(50, [int]$intervalMs))
        $attempts = 0
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            if (-not $process.session.IsRunning) {
                return [pscustomobject]@{ status='PROCESS_EXITED'; attempts=$attempts; elapsed_ms=[int]$timer.ElapsedMilliseconds; actual_path='' }
            }

            $attempts++
            $actualPath = [string]$process.session.QueryActualPath()
            if (-not [string]::IsNullOrWhiteSpace($actualPath)) {
                $process.actual_path = $actualPath
                return [pscustomobject]@{ status='PATH_OBTAINED'; attempts=$attempts; elapsed_ms=[int]$timer.ElapsedMilliseconds; actual_path=$actualPath }
            }
            if (-not $process.session.IsRunning) {
                return [pscustomobject]@{ status='PROCESS_EXITED'; attempts=$attempts; elapsed_ms=[int]$timer.ElapsedMilliseconds; actual_path='' }
            }
            if ($timer.ElapsedMilliseconds -ge $timeout) {
                return [pscustomobject]@{ status='QUERY_TIMEOUT'; attempts=$attempts; elapsed_ms=[int]$timer.ElapsedMilliseconds; actual_path='' }
            }

            $remaining = $timeout - [int]$timer.ElapsedMilliseconds
            [System.Threading.Thread]::Sleep([Math]::Max(1, [Math]::Min($interval, $remaining)))
        }
    }
    $adapter | Add-Member -NotePropertyName WaitForReadiness -NotePropertyValue {
        param($process, $regex, $timeoutMs, $stableMs)
        return $process.session.WaitForReadiness([string]$regex, [int]$timeoutMs, [int]$stableMs)
    }
    $adapter | Add-Member -NotePropertyName StopProcess -NotePropertyValue {
        param($process, $timeoutMs)
        return $process.session.GracefulStop([int]$timeoutMs)
    }
    $adapter | Add-Member -NotePropertyName KillProcess -NotePropertyValue {
        param($process)
        $process.session.Kill()
    }
    $adapter | Add-Member -NotePropertyName IsRunning -NotePropertyValue {
        param($process)
        return $process.session.IsRunning
    }
    $adapter | Add-Member -NotePropertyName GetProcessResult -NotePropertyValue {
        param($process)
        return [pscustomobject]@{
            exit_code = $process.session.ExitCode
            timed_out = [bool]$process.timed_out
            pid = [int]$process.pid
            actual_path = [string]$process.actual_path
            actual_path_probe_status = [string]$process.actual_path_probe_status
            actual_path_probe_attempts = [int]$process.actual_path_probe_attempts
            actual_path_probe_elapsed_ms = [int]$process.actual_path_probe_elapsed_ms
            stdout = [string]$process.session.Stdout
            stderr = [string]$process.session.Stderr
        }
    }
    $adapter | Add-Member -NotePropertyName DisposeProcess -NotePropertyValue {
        param($process)
        if ($null -ne $process -and $null -ne $process.session) { $process.session.Dispose() }
    }
    $adapter | Add-Member -NotePropertyName Invoke -NotePropertyValue ({
        param($plan)
        $process = $null
        try {
            $process = & $adapter.StartProcess $plan
            $watchdog = [System.Diagnostics.Stopwatch]::StartNew()
            $processTimeoutMs = & $adapter.GetWatchdogTimeout $plan
            $probeTimeoutMs = $(if ($null -ne $plan.PSObject.Properties['actual_path_timeout_ms']) { [int]$plan.actual_path_timeout_ms } else { 2000 })
            $pathProbe = & $adapter.ProbeActualPath $process $probeTimeoutMs 25
            $process.actual_path = [string]$pathProbe.actual_path
            $process.actual_path_probe_status = [string]$pathProbe.status
            $process.actual_path_probe_attempts = [int]$pathProbe.attempts
            $process.actual_path_probe_elapsed_ms = [int]$pathProbe.elapsed_ms
            $remainingMs = $processTimeoutMs - [int]$watchdog.ElapsedMilliseconds
            $completed = $(if (-not $process.session.IsRunning) { $process.session.WaitForExit(1) } elseif ($remainingMs -gt 0) { $process.session.WaitForExit($remainingMs) } else { $false })
            if (-not $completed) {
                $process.timed_out = $true
                & $adapter.KillProcess $process
            }
            return & $adapter.GetProcessResult $process
        }
        finally {
            if ($null -ne $process) { & $adapter.DisposeProcess $process }
        }
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName InvokeConcurrent -NotePropertyValue ({
        param($plans)
        $sessions = [System.Collections.Generic.List[object]]::new()
        $results = [System.Collections.Generic.List[object]]::new()
        $watchdog = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            foreach ($plan in @($plans)) {
                $sessions.Add([pscustomobject]@{ plan=$plan; process=(& $adapter.StartProcess $plan) })
            }
            foreach ($item in $sessions) {
                $probeTimeoutMs = $(if ($null -ne $item.plan.PSObject.Properties['actual_path_timeout_ms']) { [int]$item.plan.actual_path_timeout_ms } else { 2000 })
                $pathProbe = & $adapter.ProbeActualPath $item.process $probeTimeoutMs 25
                $item.process.actual_path = [string]$pathProbe.actual_path
                $item.process.actual_path_probe_status = [string]$pathProbe.status
                $item.process.actual_path_probe_attempts = [int]$pathProbe.attempts
                $item.process.actual_path_probe_elapsed_ms = [int]$pathProbe.elapsed_ms
            }
            $deadlineMs = [int](($sessions | ForEach-Object { [int](& $adapter.GetWatchdogTimeout $_.plan) } | Measure-Object -Maximum).Maximum)
            foreach ($item in $sessions) {
                $remainingMs = [int]$deadlineMs - [int]$watchdog.ElapsedMilliseconds
                $completed = $(if (-not $item.process.session.IsRunning) { $item.process.session.WaitForExit(1) } elseif ($remainingMs -gt 0) { $item.process.session.WaitForExit($remainingMs) } else { $false })
                if (-not $completed) {
                    $item.process.timed_out = $true
                    & $adapter.KillProcess $item.process
                }
                $results.Add((& $adapter.GetProcessResult $item.process))
            }
            return $results.ToArray()
        }
        finally {
            foreach ($item in $sessions) {
                try { if (& $adapter.IsRunning $item.process) { & $adapter.KillProcess $item.process } } catch {}
                & $adapter.DisposeProcess $item.process
            }
        }
    }.GetNewClosure())
    return $adapter
}

function New-MockProcessAdapter {
    [CmdletBinding()]
    param(
        [object[]]$InvokeResults = @(),
        [bool]$Ready = $true,
        [bool]$StableReady = $true,
        [bool]$GracefulStop = $true,
        [string]$ActualPath = 'fixture-process.exe',
        [AllowNull()][object[]]$ActualPathProbeSequence = $null,
        [bool]$PrelaunchPathVerified = $true,
        [bool]$PrelaunchHashVerified = $true,
        [AllowNull()][object[]]$InvokeDurationsMs = $null,
        [string]$LifecycleStdout = '',
        [string]$LifecycleStderr = ''
    )

    $probeSequence = $(if ($PSBoundParameters.ContainsKey('ActualPathProbeSequence')) { @($ActualPathProbeSequence) } else { @($ActualPath) })

    $state = [pscustomobject]@{
        running = $false
        start_count = 0
        stop_count = 0
        kill_count = 0
        dispose_count = 0
        invoke_count = 0
        watchdog_kill_count = 0
        prelaunch_verify_count = 0
        invoked_plans = [System.Collections.Generic.List[object]]::new()
        results = @($InvokeResults)
        invoke_durations_ms = $(if ($null -eq $InvokeDurationsMs) { $null } else { @($InvokeDurationsMs) })
        watchdog_timeouts_ms = [System.Collections.Generic.List[int]]::new()
        ready = $Ready
        stable_ready = $StableReady
        graceful_stop = $GracefulStop
        actual_path = $ActualPath
        actual_path_probe_sequence = @($probeSequence)
        actual_path_probe_index = 0
        prelaunch_path_verified = $PrelaunchPathVerified
        prelaunch_hash_verified = $PrelaunchHashVerified
        stdout = $LifecycleStdout
        stderr = $LifecycleStderr
    }
    $adapter = [pscustomobject]@{ is_mock = $true; state = $state }

    $adapter | Add-Member -NotePropertyName GetWatchdogTimeout -NotePropertyValue {
        param($plan)
        $timeout = $(if ($null -ne $plan.PSObject.Properties['process_timeout_ms']) { [long]$plan.process_timeout_ms } elseif ($null -ne $plan.PSObject.Properties['timeout_ms']) { [long]$plan.timeout_ms } else { 0 })
        if ($timeout -lt 1 -or $timeout -gt [int]::MaxValue) { throw 'PROCESS_TIMEOUT_INVALID' }
        return [int]$timeout
    }
    $adapter | Add-Member -NotePropertyName VerifyExecutable -NotePropertyValue ({
        param($path, $expectedSha256)
        $state.prelaunch_verify_count++
        $status = $(if (-not $state.prelaunch_path_verified) { 'PATH_MISSING' } elseif (-not $state.prelaunch_hash_verified) { 'HASH_MISMATCH' } else { 'VERIFIED' })
        return [pscustomobject]@{ path_verified=[bool]$state.prelaunch_path_verified; hash_verified=[bool]$state.prelaunch_hash_verified; status=$status }
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName StartProcess -NotePropertyValue ({
        param($plan)
        $state.start_count++
        $state.running = $true
        return [pscustomobject]@{ pid = 4242; actual_path = ''; timed_out = $false }
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName ProbeActualPath -NotePropertyValue ({
        param($process, $timeoutMs, $intervalMs)
        $timeout = [Math]::Max(1, [int]$timeoutMs)
        $interval = [Math]::Max(25, [Math]::Min(50, [int]$intervalMs))
        $attempts = 0
        $elapsed = 0
        while ($true) {
            if (-not $state.running) {
                return [pscustomobject]@{ status='PROCESS_EXITED'; attempts=$attempts; elapsed_ms=$elapsed; actual_path='' }
            }

            $attempts++
            $probeValue = ''
            if ($state.actual_path_probe_index -lt @($state.actual_path_probe_sequence).Count) {
                $probeValue = [string]$state.actual_path_probe_sequence[$state.actual_path_probe_index]
                $state.actual_path_probe_index++
            }
            if ($probeValue -eq '__PROCESS_EXITED__') {
                $state.running = $false
                return [pscustomobject]@{ status='PROCESS_EXITED'; attempts=$attempts; elapsed_ms=$elapsed; actual_path='' }
            }
            if (-not [string]::IsNullOrWhiteSpace($probeValue)) {
                $process.actual_path = $probeValue
                return [pscustomobject]@{ status='PATH_OBTAINED'; attempts=$attempts; elapsed_ms=$elapsed; actual_path=$probeValue }
            }
            if ($elapsed -ge $timeout) {
                return [pscustomobject]@{ status='QUERY_TIMEOUT'; attempts=$attempts; elapsed_ms=$elapsed; actual_path='' }
            }
            $elapsed = [Math]::Min($timeout, $elapsed + $interval)
        }
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName WaitForReadiness -NotePropertyValue ({
        param($process, $regex, $timeoutMs, $stableMs)
        if ([string]::IsNullOrWhiteSpace([string]$regex)) { return [bool]$state.stable_ready }
        return [bool]$state.ready
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName StopProcess -NotePropertyValue ({
        param($process, $timeoutMs)
        $state.stop_count++
        if ($state.graceful_stop) { $state.running = $false }
        return [bool]$state.graceful_stop
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName KillProcess -NotePropertyValue ({
        param($process)
        $state.kill_count++
        $state.running = $false
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName IsRunning -NotePropertyValue ({
        param($process)
        return [bool]$state.running
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName GetProcessResult -NotePropertyValue ({
        param($process)
        return [pscustomobject]@{
            exit_code = 0
            timed_out = [bool]$process.timed_out
            pid = [int]$process.pid
            actual_path = [string]$process.actual_path
            stdout = [string]$state.stdout
            stderr = [string]$state.stderr
        }
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName DisposeProcess -NotePropertyValue ({
        param($process)
        $state.dispose_count++
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName Invoke -NotePropertyValue ({
        param($plan)
        $index = [int]$state.invoke_count
        $state.invoke_count++
        $state.invoked_plans.Add($plan)
        if ($index -ge @($state.results).Count) { throw 'MOCK_PROCESS_RESULT_NOT_CONFIGURED' }
        $result = $state.results[$index]
        if ($null -ne $state.invoke_durations_ms) {
            if ($index -ge @($state.invoke_durations_ms).Count) { throw 'MOCK_PROCESS_DURATION_NOT_CONFIGURED' }
            $watchdogTimeoutMs = & $adapter.GetWatchdogTimeout $plan
            $state.watchdog_timeouts_ms.Add($watchdogTimeoutMs)
            if ([long]$state.invoke_durations_ms[$index] -gt $watchdogTimeoutMs) {
                $result = $result | Select-Object *
                $result.timed_out = $true
                $result.exit_code = -1
                $state.watchdog_kill_count++
            }
        }
        return $result
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName InvokeConcurrent -NotePropertyValue ({
        param($plans)
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($plan in @($plans)) { $results.Add((& $adapter.Invoke $plan)) }
        return $results.ToArray()
    }.GetNewClosure())
    return $adapter
}

function Invoke-ConcurrentProcessPlans {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Plans,
        [Parameter(Mandatory)]$ProcessAdapter,
        [switch]$AllowProductRuntime
    )
    if ($Plans.Count -lt 2 -or $Plans.Count -gt 8) { throw 'PROCESS_CONCURRENT_COUNT_INVALID' }
    if (-not [bool]$ProcessAdapter.is_mock -and -not $AllowProductRuntime) { throw 'PROCESS_RUNTIME_NOT_ALLOWED' }
    if ($null -eq $ProcessAdapter.PSObject.Properties['InvokeConcurrent']) { throw 'PROCESS_ADAPTER_MISSING_INVOKE_CONCURRENT' }
    $results = @(& $ProcessAdapter.InvokeConcurrent $Plans)
    if ($results.Count -ne $Plans.Count) { throw 'PROCESS_CONCURRENT_RESULT_COUNT_MISMATCH' }
    foreach ($result in $results) {
        foreach ($field in @('exit_code', 'timed_out', 'pid', 'actual_path', 'stdout', 'stderr')) {
            if ($null -eq $result.PSObject.Properties[$field]) { throw "PROCESS_RESULT_MISSING_$field" }
        }
        if ($null -eq $result.PSObject.Properties['actual_path_probe_status']) {
            $result | Add-Member -NotePropertyName actual_path_probe_status -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace([string]$result.actual_path)) { 'PROCESS_EXITED' } else { 'PATH_OBTAINED' })
        }
        if ($null -eq $result.PSObject.Properties['actual_path_probe_attempts']) { $result | Add-Member -NotePropertyName actual_path_probe_attempts -NotePropertyValue 1 }
        if ($null -eq $result.PSObject.Properties['actual_path_probe_elapsed_ms']) { $result | Add-Member -NotePropertyName actual_path_probe_elapsed_ms -NotePropertyValue 0 }
    }
    return $results
}

function Invoke-ProcessPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ProcessAdapter,
        [switch]$AllowProductRuntime
    )

    if (-not [bool]$ProcessAdapter.is_mock -and -not $AllowProductRuntime) { throw 'PROCESS_RUNTIME_NOT_ALLOWED' }
    if ($null -eq $ProcessAdapter.PSObject.Properties['Invoke']) { throw 'PROCESS_ADAPTER_MISSING_INVOKE' }
    $result = & $ProcessAdapter.Invoke $Plan
    foreach ($field in @('exit_code', 'timed_out', 'pid', 'actual_path', 'stdout', 'stderr')) {
        if ($null -eq $result.PSObject.Properties[$field]) { throw "PROCESS_RESULT_MISSING_$field" }
    }
    if ($null -eq $result.PSObject.Properties['actual_path_probe_status']) {
        $result | Add-Member -NotePropertyName actual_path_probe_status -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace([string]$result.actual_path)) { 'PROCESS_EXITED' } else { 'PATH_OBTAINED' })
    }
    if ($null -eq $result.PSObject.Properties['actual_path_probe_attempts']) { $result | Add-Member -NotePropertyName actual_path_probe_attempts -NotePropertyValue 1 }
    if ($null -eq $result.PSObject.Properties['actual_path_probe_elapsed_ms']) { $result | Add-Member -NotePropertyName actual_path_probe_elapsed_ms -NotePropertyValue 0 }
    return $result
}

Export-ModuleMember -Function Join-ProcessArguments, New-SystemProcessAdapter, New-MockProcessAdapter, Invoke-ProcessPlan, Invoke-ConcurrentProcessPlans
