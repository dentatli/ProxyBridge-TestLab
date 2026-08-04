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

    $adapter | Add-Member -NotePropertyName StartProcess -NotePropertyValue {
        param($plan)
        $argumentText = Join-ProcessArguments -Arguments @($plan.arguments)
        $session = [ProxyBridge.TestLab.SafeProcessSession]::Start([string]$plan.executable, $argumentText)
        return [pscustomobject]@{
            pid = $session.Pid
            actual_path = ''
            session = $session
            timed_out = $false
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
            $probeTimeoutMs = $(if ($null -ne $plan.PSObject.Properties['actual_path_timeout_ms']) { [int]$plan.actual_path_timeout_ms } else { 2000 })
            $pathProbe = & $adapter.ProbeActualPath $process $probeTimeoutMs 25
            $process.actual_path = [string]$pathProbe.actual_path
            $completed = $process.session.WaitForExit([int]$plan.timeout_ms)
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
        invoked_plans = [System.Collections.Generic.List[object]]::new()
        results = @($InvokeResults)
        ready = $Ready
        stable_ready = $StableReady
        graceful_stop = $GracefulStop
        actual_path = $ActualPath
        actual_path_probe_sequence = @($probeSequence)
        actual_path_probe_index = 0
        stdout = $LifecycleStdout
        stderr = $LifecycleStderr
    }
    $adapter = [pscustomobject]@{ is_mock = $true; state = $state }

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
        return $state.results[$index]
    }.GetNewClosure())
    return $adapter
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
    return $result
}

Export-ModuleMember -Function Join-ProcessArguments, New-SystemProcessAdapter, New-MockProcessAdapter, Invoke-ProcessPlan
