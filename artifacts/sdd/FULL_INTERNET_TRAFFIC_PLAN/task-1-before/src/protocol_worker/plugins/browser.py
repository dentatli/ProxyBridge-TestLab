from __future__ import annotations

import ctypes
import hashlib
import json
import os
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from model import WorkerContractError, WorkerPlan


_DOM_MARKER = "PB_TESTLAB_BROWSER_READY"
_WINDOWS_STILL_ACTIVE = 259
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_PROCESS_SET_QUOTA = 0x0100
_PROCESS_TERMINATE = 0x0001
_TH32CS_SNAPPROCESS = 0x00000002
_JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
_JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000


class _BrowserJob:
    def __init__(self) -> None:
        if os.name != "nt":
            raise WorkerContractError("BROWSER_JOB_UNAVAILABLE")

        class IoCounters(ctypes.Structure):
            _fields_ = [(name, ctypes.c_uint64) for name in (
                "ReadOperationCount", "WriteOperationCount", "OtherOperationCount", "ReadTransferCount", "WriteTransferCount", "OtherTransferCount",
            )]

        class BasicLimitInformation(ctypes.Structure):
            _fields_ = [
                ("PerProcessUserTimeLimit", ctypes.c_int64), ("PerJobUserTimeLimit", ctypes.c_int64), ("LimitFlags", ctypes.c_uint32),
                ("MinimumWorkingSetSize", ctypes.c_size_t), ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", ctypes.c_uint32),
                ("Affinity", ctypes.c_size_t), ("PriorityClass", ctypes.c_uint32), ("SchedulingClass", ctypes.c_uint32),
            ]

        class ExtendedLimitInformation(ctypes.Structure):
            _fields_ = [
                ("BasicLimitInformation", BasicLimitInformation), ("IoInfo", IoCounters), ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t), ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t),
            ]

        self._kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        create = self._kernel32.CreateJobObjectW
        create.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p]
        create.restype = ctypes.c_void_p
        self._handle = create(None, None)
        if not self._handle:
            raise WorkerContractError("BROWSER_JOB_UNAVAILABLE")
        info = ExtendedLimitInformation()
        info.BasicLimitInformation.LimitFlags = _JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        set_information = self._kernel32.SetInformationJobObject
        set_information.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        set_information.restype = ctypes.c_bool
        if not set_information(self._handle, _JOB_OBJECT_EXTENDED_LIMIT_INFORMATION, ctypes.byref(info), ctypes.sizeof(info)):
            self.close()
            raise WorkerContractError("BROWSER_JOB_UNAVAILABLE")

    def assign(self, pid: int) -> None:
        open_process = self._kernel32.OpenProcess
        open_process.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
        open_process.restype = ctypes.c_void_p
        close_handle = self._kernel32.CloseHandle
        close_handle.argtypes = [ctypes.c_void_p]
        close_handle.restype = ctypes.c_bool
        process = open_process(_PROCESS_SET_QUOTA | _PROCESS_TERMINATE | _PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not process:
            raise WorkerContractError("BROWSER_JOB_ASSIGN_FAILED")
        try:
            assign = self._kernel32.AssignProcessToJobObject
            assign.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
            assign.restype = ctypes.c_bool
            if not assign(self._handle, process):
                raise WorkerContractError("BROWSER_JOB_ASSIGN_FAILED")
        finally:
            close_handle(process)

    def close(self) -> None:
        if self._handle:
            self._kernel32.CloseHandle(self._handle)
            self._handle = None


def _required_string(plan: WorkerPlan, name: str) -> str:
    value = plan.raw["parameters"].get(name)
    if not isinstance(value, str) or not value:
        raise WorkerContractError(f"BROWSER_PARAMETER_INVALID:{name}")
    return value


def _safe_name(plan: WorkerPlan, name: str) -> str:
    value = _required_string(plan, name)
    if Path(value).name != value or value in {".", ".."}:
        raise WorkerContractError(f"BROWSER_PARAMETER_INVALID:{name}")
    return value


def _browser_arguments(plan: WorkerPlan) -> list[str]:
    value = plan.raw["parameters"].get("browser_arguments", [])
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise WorkerContractError("BROWSER_PARAMETER_INVALID:browser_arguments")
    return list(value)


def _query_process_image(pid: int) -> str:
    if os.name != "nt":
        raise WorkerContractError("BROWSER_OBSERVED_PATH_UNAVAILABLE")
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    open_process = kernel32.OpenProcess
    open_process.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    open_process.restype = ctypes.c_void_p
    close_handle = kernel32.CloseHandle
    close_handle.argtypes = [ctypes.c_void_p]
    close_handle.restype = ctypes.c_bool
    query = kernel32.QueryFullProcessImageNameW
    query.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
    query.restype = ctypes.c_bool
    handle = open_process(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        raise WorkerContractError("BROWSER_OBSERVED_PATH_UNAVAILABLE")
    try:
        size = ctypes.c_uint32(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if not query(handle, 0, buffer, ctypes.byref(size)) or not buffer.value:
            raise WorkerContractError("BROWSER_OBSERVED_PATH_UNAVAILABLE")
        return str(Path(buffer.value).resolve())
    finally:
        close_handle(handle)


def _process_tree(root_pid: int) -> list[int]:
    if os.name != "nt":
        return [root_pid]
    class ProcessEntry32(ctypes.Structure):
        _fields_ = [
            ("dwSize", ctypes.c_uint32), ("cntUsage", ctypes.c_uint32), ("th32ProcessID", ctypes.c_uint32),
            ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", ctypes.c_uint32), ("cntThreads", ctypes.c_uint32),
            ("th32ParentProcessID", ctypes.c_uint32), ("pcPriClassBase", ctypes.c_long), ("dwFlags", ctypes.c_uint32),
            ("szExeFile", ctypes.c_wchar * 260),
        ]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    snapshot = kernel32.CreateToolhelp32Snapshot
    snapshot.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
    snapshot.restype = ctypes.c_void_p
    first = kernel32.Process32FirstW
    first.argtypes = [ctypes.c_void_p, ctypes.POINTER(ProcessEntry32)]
    first.restype = ctypes.c_bool
    next_entry = kernel32.Process32NextW
    next_entry.argtypes = [ctypes.c_void_p, ctypes.POINTER(ProcessEntry32)]
    next_entry.restype = ctypes.c_bool
    close_handle = kernel32.CloseHandle
    close_handle.argtypes = [ctypes.c_void_p]
    close_handle.restype = ctypes.c_bool
    handle = snapshot(_TH32CS_SNAPPROCESS, 0)
    invalid = ctypes.c_void_p(-1).value
    if handle == invalid:
        raise WorkerContractError("BROWSER_PROCESS_TREE_UNAVAILABLE")
    parents: dict[int, list[int]] = {}
    try:
        entry = ProcessEntry32()
        entry.dwSize = ctypes.sizeof(ProcessEntry32)
        if first(handle, ctypes.byref(entry)):
            while True:
                parents.setdefault(int(entry.th32ParentProcessID), []).append(int(entry.th32ProcessID))
                entry.dwSize = ctypes.sizeof(ProcessEntry32)
                if not next_entry(handle, ctypes.byref(entry)):
                    break
    finally:
        close_handle(handle)
    result: list[int] = []
    pending = [root_pid]
    while pending:
        pid = pending.pop()
        if pid in result:
            continue
        result.append(pid)
        pending.extend(parents.get(pid, []))
    return sorted(result)


def _process_running(pid: int) -> bool:
    if os.name != "nt":
        return False
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    open_process = kernel32.OpenProcess
    open_process.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    open_process.restype = ctypes.c_void_p
    close_handle = kernel32.CloseHandle
    close_handle.argtypes = [ctypes.c_void_p]
    close_handle.restype = ctypes.c_bool
    get_exit_code = kernel32.GetExitCodeProcess
    get_exit_code.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    get_exit_code.restype = ctypes.c_bool
    handle = open_process(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return False
    try:
        code = ctypes.c_uint32()
        return bool(get_exit_code(handle, ctypes.byref(code)) and code.value == _WINDOWS_STILL_ACTIVE)
    finally:
        close_handle(handle)


def _terminate_tree(root_pid: int, known_pids: list[int]) -> bool:
    if _process_running(root_pid):
        taskkill = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "taskkill.exe"
        try:
            subprocess.run([str(taskkill), "/PID", str(root_pid), "/T", "/F"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            return False
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline and any(_process_running(pid) for pid in known_pids):
        time.sleep(0.025)
    return not any(_process_running(pid) for pid in known_pids)


def _remove_isolated_directories(profile: Path, downloads: Path) -> bool:
    for path in (profile, downloads):
        try:
            if path.exists():
                shutil.rmtree(path)
        except OSError:
            return False
    return not profile.exists() and not downloads.exists()


def run_browser(plan: WorkerPlan) -> list[dict[str, Any]]:
    """Run one isolated browser canary and return only post-cleanup evidence."""
    started = time.monotonic()
    parameters = plan.raw["parameters"]
    requested = Path(_required_string(plan, "browser_executable"))
    if not requested.is_file():
        raise WorkerContractError("BROWSER_EXECUTABLE_MISSING")
    requested = requested.resolve()
    target_url = _required_string(plan, "target_url")
    parsed = urlparse(target_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise WorkerContractError("BROWSER_TARGET_URL_INVALID")
    profile = Path(_required_string(plan, "profile_dir")).resolve()
    downloads = Path(_required_string(plan, "download_dir")).resolve()
    if profile == downloads or profile.exists() or downloads.exists():
        raise WorkerContractError("BROWSER_ISOLATION_PATH_INVALID")
    download = downloads / _safe_name(plan, "download_name")
    marker = downloads / _safe_name(plan, "dom_marker_name")
    expected_hash = _required_string(plan, "expected_download_sha256").lower()
    if len(expected_hash) != 64 or any(character not in "0123456789abcdef" for character in expected_hash):
        raise WorkerContractError("BROWSER_PARAMETER_INVALID:expected_download_sha256")

    profile.mkdir(parents=True, exist_ok=False)
    downloads.mkdir(parents=True, exist_ok=False)
    process: subprocess.Popen[bytes] | None = None
    tree_pids: list[int] = []
    observed = ""
    failure: BaseException | None = None
    cleanup_ok = False
    try:
        command = [
            str(requested), *_browser_arguments(plan), "--headless=new", "--disable-background-networking", "--disable-sync",
            "--no-first-run", "--no-default-browser-check", f"--user-data-dir={profile}",
            f"--download-default-directory={downloads}", f"--testlab-dom-marker-path={marker}",
            f"--testlab-download-path={download}", target_url,
        ]
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
        observed = _query_process_image(process.pid)
        if os.path.normcase(str(observed)) != os.path.normcase(str(requested)):
            raise WorkerContractError("BROWSER_OBSERVED_PATH_MISMATCH")
        deadline = started + plan.raw["operation_timeout_ms"] / 1000.0
        while time.monotonic() < deadline and not (marker.is_file() and download.is_file()):
            if process.poll() is not None:
                raise WorkerContractError("BROWSER_EXITED_BEFORE_EVIDENCE")
            time.sleep(0.025)
        if not marker.is_file() or not download.is_file():
            raise WorkerContractError("BROWSER_EVIDENCE_TIMEOUT")
        tree_pids = _process_tree(process.pid)
        if process.pid not in tree_pids:
            raise WorkerContractError("BROWSER_PROCESS_TREE_INVALID")
        try:
            marker_data = json.loads(marker.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WorkerContractError("BROWSER_DOM_MARKER_INVALID") from exc
        actual_hash = hashlib.sha256(download.read_bytes()).hexdigest()
        if marker_data.get("dom_marker") != _DOM_MARKER:
            raise WorkerContractError("BROWSER_DOM_MARKER_MISMATCH")
        if marker_data.get("download_sha256") != actual_hash or actual_hash != expected_hash:
            raise WorkerContractError("BROWSER_DOWNLOAD_HASH_MISMATCH")
    except BaseException as exc:
        failure = exc
    finally:
        if process is not None:
            if not tree_pids:
                try:
                    tree_pids = _process_tree(process.pid)
                except WorkerContractError:
                    tree_pids = [process.pid]
            cleanup_ok = _terminate_tree(process.pid, tree_pids)
        directories_removed = _remove_isolated_directories(profile, downloads)
        cleanup_ok = cleanup_ok and directories_removed
    if not cleanup_ok:
        raise WorkerContractError("BROWSER_TREE_CLEANUP_FAILED") from failure
    if failure is not None:
        if isinstance(failure, WorkerContractError):
            raise failure
        raise WorkerContractError("BROWSER_WORKER_UNEXPECTED_FAILURE") from failure

    payload_sha256 = expected_hash
    return [{
        "schema_version": 1,
        "run_id": plan.raw["run_id"],
        "scenario_id": plan.raw["scenario_id"],
        "attempt_id": plan.raw["attempt_id"],
        "flow_id": plan.raw["flow_id"],
        "phase": "client",
        "sequence": 1,
        "event": "BROWSER_CANARY_COMPLETED",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "monotonic_ms": int((time.monotonic() - started) * 1000),
        "process_id": process.pid if process is not None else 0,
        "socket_id": 0,
        "protocol_family": plan.protocol_family,
        "transport": plan.transport,
        "local_ip": "",
        "local_port": 0,
        "remote_ip": "",
        "remote_port": 0,
        "payload_sha256": payload_sha256,
        "bytes": len(payload_sha256),
        "result": "PASS",
        "dom_marker": _DOM_MARKER,
        "download_sha256": payload_sha256,
        "browser_executable_requested": str(requested),
        "browser_executable_observed": observed,
        "browser_process_tree_pids": tree_pids,
        "profile_id": hashlib.sha256(str(profile).encode("utf-8")).hexdigest(),
        "process_tree_cleaned": True,
    }]
