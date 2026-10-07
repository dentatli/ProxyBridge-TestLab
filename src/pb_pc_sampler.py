"""Bounded Windows resource observation using the pinned psutil implementation."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import queue
import sys
import threading
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--packages', required=True)
    parser.add_argument('--config', required=True)
    parser.add_argument('--jsonl-log', required=True)
    parser.add_argument('--max-duration-seconds', type=int, default=45)
    args = parser.parse_args()
    if not 10 <= args.max_duration_seconds <= 14400:
        parser.error('max duration must be between 10 and 14400 seconds')
    sys.path.insert(0, args.packages)
    import psutil
    if psutil.__version__ != '7.2.2' or sys.platform != 'win32':
        raise RuntimeError('SAMPLER_REQUIRES_PSUTIL_7_2_2_WINDOWS')
    cores = psutil.cpu_count(logical=True)
    if not cores:
        raise RuntimeError('LOGICAL_CPU_COUNT_UNAVAILABLE')
    commands = queue.Queue()
    watched = {}
    with Path(args.jsonl_log).open('x', encoding='utf-8', buffering=1) as log:
        def emit(event, **fields):
            log.write(json.dumps(dict(event=event, timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                                      qpc_ms=time.perf_counter() * 1000, **fields)) + '\n')

        def watch(spec):
            process = psutil.Process(spec['pid'])
            actual = process.exe()
            if os.path.normcase(os.path.realpath(actual)) != os.path.normcase(os.path.realpath(spec['path'])):
                raise RuntimeError('SAMPLER_EXECUTABLE_MISMATCH')
            times = process.cpu_times()
            watched[spec['role']] = dict(process=process, created=process.create_time(),
                                        path=actual, cpu=times.user + times.system, clock=time.perf_counter())
            emit('WATCHED', role=spec['role'], pid=process.pid, path=actual, create_time=process.create_time())

        def reader():
            for line in sys.stdin:
                commands.put(line.strip())
            commands.put('STOP')

        for spec in json.loads(Path(args.config).read_text(encoding='utf-8-sig')):
            watch(spec)
        watch(dict(role='sampler', pid=os.getpid(), path=sys.executable))
        threading.Thread(target=reader, daemon=True).start()
        psutil.cpu_percent(interval=None)  # Prime the library's system CPU delta.
        emit('LISTENING', logical_cpus=cores, interval_ms=250, psutil_version=psutil.__version__)
        started = time.perf_counter()
        previous_sample = started
        stop = False
        while not stop and time.perf_counter() - started < args.max_duration_seconds:
            deadline = time.perf_counter() + .25
            while time.perf_counter() < deadline:
                try:
                    command = commands.get(timeout=max(.001, deadline - time.perf_counter()))
                    if command == 'STOP':
                        stop = True
                        break
                    watch(json.loads(command))
                except queue.Empty:
                    break
            if stop:
                break
            now = time.perf_counter()
            processes = []
            for role, state in watched.items():
                process = state['process']
                try:
                    if not process.is_running() or psutil.Process(process.pid).create_time() != state['created']:
                        raise psutil.NoSuchProcess(process.pid)
                    with process.oneshot():
                        times = process.cpu_times()
                        memory = process.memory_info()
                    cpu = times.user + times.system
                    processes.append(dict(role=role, pid=process.pid, status='OBSERVED',
                                          interval_start_qpc_ms=state['clock'] * 1000,
                                          cpu_pct_machine=100 * max(0, cpu - state['cpu']) / (now - state['clock']) / cores,
                                          private_bytes=memory.private, working_set_bytes=memory.rss))
                    state.update(cpu=cpu, clock=now)
                except (psutil.NoSuchProcess, psutil.AccessDenied) as error:
                    processes.append(dict(role=role, pid=process.pid, status=type(error).__name__))
            memory = psutil.virtual_memory()
            emit('SAMPLE', interval_start_qpc_ms=previous_sample * 1000,
                 system_cpu_pct=psutil.cpu_percent(interval=None), system_memory_used_bytes=memory.total - memory.available,
                 system_memory_total_bytes=memory.total, processes=processes)
            previous_sample = now
        emit('STOPPED', requested=stop)


if __name__ == '__main__':
    main()
