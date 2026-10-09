"""Process counters with an explicit scope; no claim of driver CPU or driver memory."""
from __future__ import annotations

import ctypes
import os
from pathlib import Path
from typing import Any


def system_sample() -> dict[str, Any]:
    """Whole-OS counters include background work and cannot be attributed to the driver."""
    try:
        if os.name == "nt":
            from ctypes import wintypes as w
            class MemoryStatus(ctypes.Structure):
                _fields_ = [("length", w.DWORD), ("load", w.DWORD)] + [(name, ctypes.c_ulonglong) for name in
                    ("total", "available", "total_pagefile", "available_pagefile", "total_virtual", "available_virtual", "available_extended")]
            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.GetSystemTimes.argtypes = [ctypes.POINTER(ctypes.c_ulonglong)] * 3
            kernel.GetSystemTimes.restype = w.BOOL
            kernel.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(MemoryStatus)]
            kernel.GlobalMemoryStatusEx.restype = w.BOOL
            idle, kernel_time, user = [ctypes.c_ulonglong() for _ in range(3)]
            memory = MemoryStatus()
            memory.length = ctypes.sizeof(memory)
            if not kernel.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kernel_time), ctypes.byref(user)) or not kernel.GlobalMemoryStatusEx(ctypes.byref(memory)):
                raise OSError("RESOURCE_SYSTEM_QUERY_FAILED")
            total = kernel_time.value + user.value
            busy = total - idle.value
            total_memory, available = memory.total, memory.available
            identity = "windows-system-current-attempt"
            memory_scope = "windows-whole-OS-physical-memory"
        else:
            values = [int(value) for value in Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
            total = sum(values)
            busy = total - values[3] - values[4]
            fields = {line.split(":")[0]: int(line.split()[1]) * 1024 for line in Path("/proc/meminfo").read_text().splitlines() if ":" in line}
            total_memory, available = fields["MemTotal"], fields["MemAvailable"]
            identity = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            memory_scope = "linux-whole-OS-MemTotal-minus-MemAvailable"
        return {"available": True, "scope": "whole-OS-including-background-work", "identity_start": identity,
                "cpu_busy_ticks": busy, "cpu_total_ticks": total, "physical_total_bytes": total_memory,
                "physical_available_bytes": available, "physical_used_bytes": total_memory - available, "memory_scope": memory_scope}
    except (OSError, ValueError, KeyError, IndexError):
        return {"available": False, "error": "RESOURCE_SYSTEM_UNAVAILABLE"}


def process_sample(pid: int, expected_path: str | None = None) -> dict[str, Any]:
    try:
        row = windows_sample(pid) if os.name == "nt" else linux_sample(pid)
        if expected_path and os.path.normcase(os.path.realpath(expected_path)) != os.path.normcase(os.path.realpath(row.pop("path"))):
            raise ValueError("RESOURCE_PROCESS_IDENTITY_CHANGED")
        row.pop("path", None)
        return {"available": True, "pid": pid, **row}
    except (OSError, ValueError, KeyError):
        return {"available": False, "pid": pid, "error": "RESOURCE_PROCESS_UNAVAILABLE_OR_IDENTITY_CHANGED"}


def linux_sample(pid: int) -> dict[str, Any]:
    root = Path(f"/proc/{pid}")
    status = {}
    for line in (root / "status").read_text().splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            status[key] = value.strip()
    raw = (root / "stat").read_text()
    fields = raw[raw.rfind(")") + 2:].split()
    ticks = os.sysconf("SC_CLK_TCK")
    return {"identity_start": fields[19], "cpu_seconds": (int(fields[11]) + int(fields[12])) / ticks,
            "working_set_bytes": int(status["VmRSS"].split()[0]) * 1024,
            "anonymous_rss_bytes": int(status["RssAnon"].split()[0]) * 1024,
            "handles": len(list((root / "fd").iterdir())), "threads": int(status["Threads"]),
            "memory_scope": "linux-process-rss-and-anonymous-rss", "path": os.readlink(root / "exe")}


def windows_sample(pid: int) -> dict[str, Any]:
    from ctypes import wintypes as w

    class FileTime(ctypes.Structure):
        _fields_ = [("low", w.DWORD), ("high", w.DWORD)]

    class Memory(ctypes.Structure):
        _fields_ = [("size", w.DWORD), ("page_faults", w.DWORD)] + [(name, ctypes.c_size_t) for name in
            ("peak_working_set", "working_set", "peak_paged_pool", "paged_pool", "peak_nonpaged_pool", "nonpaged_pool", "pagefile", "peak_pagefile", "private")]

    class ThreadEntry(ctypes.Structure):
        _fields_ = [("size", w.DWORD), ("usage", w.DWORD), ("thread_id", w.DWORD), ("owner_pid", w.DWORD),
                    ("base_priority", w.LONG), ("delta_priority", w.LONG), ("flags", w.DWORD)]

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    kernel.OpenProcess.restype = w.HANDLE
    kernel.CloseHandle.argtypes = [w.HANDLE]
    kernel.CloseHandle.restype = w.BOOL
    kernel.GetProcessTimes.argtypes = [w.HANDLE] + [ctypes.POINTER(FileTime)] * 4
    kernel.GetProcessTimes.restype = w.BOOL
    kernel.GetProcessHandleCount.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
    kernel.GetProcessHandleCount.restype = w.BOOL
    kernel.QueryFullProcessImageNameW.argtypes = [w.HANDLE, w.DWORD, w.LPWSTR, ctypes.POINTER(w.DWORD)]
    kernel.QueryFullProcessImageNameW.restype = w.BOOL
    psapi.GetProcessMemoryInfo.argtypes = [w.HANDLE, ctypes.POINTER(Memory), w.DWORD]
    psapi.GetProcessMemoryInfo.restype = w.BOOL
    kernel.CreateToolhelp32Snapshot.argtypes = [w.DWORD, w.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = w.HANDLE
    kernel.Thread32First.argtypes = [w.HANDLE, ctypes.POINTER(ThreadEntry)]
    kernel.Thread32First.restype = w.BOOL
    kernel.Thread32Next.argtypes = [w.HANDLE, ctypes.POINTER(ThreadEntry)]
    kernel.Thread32Next.restype = w.BOOL

    handle = kernel.OpenProcess(0x1000 | 0x0010, False, pid)
    if not handle:
        raise OSError("RESOURCE_PROCESS_OPEN_FAILED")
    snapshot = None
    try:
        times = [FileTime() for _ in range(4)]
        if not kernel.GetProcessTimes(handle, *(ctypes.byref(value) for value in times)):
            raise OSError("RESOURCE_PROCESS_TIMES_FAILED")
        memory = Memory()
        memory.size = ctypes.sizeof(memory)
        if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(memory), memory.size):
            raise OSError("RESOURCE_PROCESS_MEMORY_FAILED")
        handles = w.DWORD()
        if not kernel.GetProcessHandleCount(handle, ctypes.byref(handles)):
            raise OSError("RESOURCE_PROCESS_HANDLES_FAILED")
        path = ctypes.create_unicode_buffer(32768)
        size = w.DWORD(len(path))
        if not kernel.QueryFullProcessImageNameW(handle, 0, path, ctypes.byref(size)):
            raise OSError("RESOURCE_PROCESS_PATH_FAILED")
        snapshot = kernel.CreateToolhelp32Snapshot(4, 0)
        if snapshot == ctypes.c_void_p(-1).value:
            raise OSError("RESOURCE_PROCESS_THREADS_FAILED")
        entry = ThreadEntry()
        entry.size = ctypes.sizeof(entry)
        threads = 0
        found = kernel.Thread32First(snapshot, ctypes.byref(entry))
        while found:
            if entry.owner_pid == pid:
                threads += 1
            found = kernel.Thread32Next(snapshot, ctypes.byref(entry))
        def integer(value: FileTime) -> int:
            return (int(value.high) << 32) | int(value.low)
        return {"identity_start": str(integer(times[0])), "cpu_seconds": (integer(times[2]) + integer(times[3])) / 10_000_000,
                "working_set_bytes": int(memory.working_set), "private_bytes": int(memory.private),
                "handles": int(handles.value), "threads": threads,
                "memory_scope": "windows-process-working-set-and-private-committed-bytes", "path": path.value}
    finally:
        if snapshot is not None and snapshot != ctypes.c_void_p(-1).value:
            kernel.CloseHandle(snapshot)
        kernel.CloseHandle(handle)


class ResourceWindow:
    """Streaming aggregates plus at most 4096 decimated timeline points per role."""
    def __init__(self) -> None:
        self.roles: dict[str, dict[str, Any]] = {}

    def add(self, role: str, stamp: float, sample: dict[str, Any]) -> None:
        row = self.roles.setdefault(role, {"samples": 0, "unavailable_samples": 0, "identity_start": None,
                                          "timeline": [], "timeline_stride": 1, "counters": {}, "last_cpu": None})
        row["samples"] += 1
        if not sample.get("available") or (row["identity_start"] is not None and row["identity_start"] != sample["identity_start"]):
            row["unavailable_samples"] += 1
            return
        row["identity_start"] = sample["identity_start"]
        values = {key: value for key, value in sample.items() if key in ("working_set_bytes", "private_bytes", "anonymous_rss_bytes", "handles", "threads",
            "physical_total_bytes", "physical_available_bytes", "physical_used_bytes")}
        last_cpu = row["last_cpu"]
        if "cpu_total_ticks" in sample:
            if last_cpu is not None and sample["cpu_total_ticks"] > last_cpu[2]:
                values["cpu_percent_of_pc"] = max(0, min(100, (sample["cpu_busy_ticks"] - last_cpu[1]) / (sample["cpu_total_ticks"] - last_cpu[2]) * 100))
            row["last_cpu"] = [stamp, sample["cpu_busy_ticks"], sample["cpu_total_ticks"]]
        else:
            if last_cpu is not None and stamp > last_cpu[0]:
                values["cpu_percent_of_pc"] = max(0, (sample["cpu_seconds"] - last_cpu[1]) / (stamp - last_cpu[0]) * 100 / sample.get("cpu_count", os.cpu_count() or 1))
            row["last_cpu"] = [stamp, sample["cpu_seconds"]]
        for key, value in values.items():
            counter = row["counters"].setdefault(key, {"count": 0, "sum": 0.0, "first": value, "last": value, "max": value, "min": value})
            counter["count"] += 1
            counter["sum"] += value
            counter["last"] = value
            counter["max"] = max(counter["max"], value)
            counter["min"] = min(counter["min"], value)
        if row["samples"] % row["timeline_stride"] == 0:
            row["timeline"].append({"seconds": stamp, **values})
            if len(row["timeline"]) > 4096:
                row["timeline"] = row["timeline"][::2]
                row["timeline_stride"] *= 2
        row["memory_scope"] = sample["memory_scope"]

    def view(self) -> dict[str, Any]:
        result = {}
        for role, row in self.roles.items():
            counters = {name: {key: value for key, value in counter.items() if key != "sum"} | {"mean": counter["sum"] / counter["count"]}
                        for name, counter in row["counters"].items()}
            result[role] = {key: value for key, value in row.items() if key not in ("last_cpu", "counters")}
            result[role]["timeline"] = list(row["timeline"])
            result[role]["counters"] = counters
        return result
