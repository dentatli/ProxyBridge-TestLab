from __future__ import annotations

import ctypes
import hashlib
import json
import msvcrt
import os
import re
import shutil
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from model import WorkerContractError, WorkerPlan


_DOM_MARKER = "PB_TESTLAB_BROWSER_READY"
_DOM_RESULT_ID = "proxybridge-testlab-browser-result"
_MAX_BROWSER_OUTPUT_BYTES = 65_536
_PATH_PROBE_INTERVAL_SECONDS = 0.025
_WINDOWS_STILL_ACTIVE = 259
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_PROCESS_SET_QUOTA = 0x0100
_PROCESS_TERMINATE = 0x0001
_TH32CS_SNAPPROCESS = 0x00000002
_JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
_JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000
_JOB_OBJECT_BASIC_PROCESS_ID_LIST = 3
_ERROR_MORE_DATA = 234
_CREATE_SUSPENDED = 0x00000004
_CREATE_NO_WINDOW = 0x08000000
_STARTF_USESTDHANDLES = 0x00000100
_HANDLE_FLAG_INHERIT = 0x00000001
_WAIT_OBJECT_0 = 0
_WAIT_TIMEOUT = 258
_INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value


class _SecurityAttributes(ctypes.Structure):
    _fields_ = [("nLength", ctypes.c_uint32), ("lpSecurityDescriptor", ctypes.c_void_p), ("bInheritHandle", ctypes.c_bool)]


class _StartupInfoW(ctypes.Structure):
    _fields_ = [
        ("cb", ctypes.c_uint32), ("lpReserved", ctypes.c_wchar_p), ("lpDesktop", ctypes.c_wchar_p), ("lpTitle", ctypes.c_wchar_p),
        ("dwX", ctypes.c_uint32), ("dwY", ctypes.c_uint32), ("dwXSize", ctypes.c_uint32), ("dwYSize", ctypes.c_uint32),
        ("dwXCountChars", ctypes.c_uint32), ("dwYCountChars", ctypes.c_uint32), ("dwFillAttribute", ctypes.c_uint32), ("dwFlags", ctypes.c_uint32),
        ("wShowWindow", ctypes.c_uint16), ("cbReserved2", ctypes.c_uint16), ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", ctypes.c_void_p), ("hStdOutput", ctypes.c_void_p), ("hStdError", ctypes.c_void_p),
    ]


class _ProcessInformation(ctypes.Structure):
    _fields_ = [("hProcess", ctypes.c_void_p), ("hThread", ctypes.c_void_p), ("dwProcessId", ctypes.c_uint32), ("dwThreadId", ctypes.c_uint32)]


class _SuspendedBrowserProcess:
    def __init__(self, command: list[str], cwd: Path) -> None:
        if os.name != "nt":
            raise WorkerContractError("BROWSER_SUSPENDED_LAUNCH_UNAVAILABLE")
        self._kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self._process_handle: int | None = None
        self._thread_handle: int | None = None
        self.pid = 0
        self.returncode: int | None = None
        self.stdout: Any = None
        self.stderr: Any = None
        stdout_read: int | None = None
        stdout_write: int | None = None
        stderr_read: int | None = None
        stderr_write: int | None = None
        null_input: int | None = None
        try:
            stdout_read, stdout_write = self._create_pipe()
            stderr_read, stderr_write = self._create_pipe()
            null_input = self._open_null_input()
            startup = _StartupInfoW()
            startup.cb = ctypes.sizeof(_StartupInfoW)
            startup.dwFlags = _STARTF_USESTDHANDLES
            startup.hStdInput = null_input
            startup.hStdOutput = stdout_write
            startup.hStdError = stderr_write
            info = _ProcessInformation()
            create = self._kernel32.CreateProcessW
            create.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_bool, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_wchar_p, ctypes.POINTER(_StartupInfoW), ctypes.POINTER(_ProcessInformation)]
            create.restype = ctypes.c_bool
            command_line = ctypes.create_unicode_buffer(subprocess.list2cmdline(command))
            if not create(str(command[0]), command_line, None, None, True, _CREATE_SUSPENDED | _CREATE_NO_WINDOW, None, str(cwd), ctypes.byref(startup), ctypes.byref(info)):
                raise WorkerContractError("BROWSER_SUSPENDED_LAUNCH_FAILED")
            self._process_handle = int(info.hProcess)
            self._thread_handle = int(info.hThread)
            self.pid = int(info.dwProcessId)
            self._close_handle(null_input)
            null_input = None
            self._close_handle(stdout_write)
            stdout_write = None
            self._close_handle(stderr_write)
            stderr_write = None
            self.stdout = self._open_reader(stdout_read)
            stdout_read = None
            self.stderr = self._open_reader(stderr_read)
            stderr_read = None
        except BaseException as exc:
            self._terminate_created_process()
            self.close()
            raise WorkerContractError("BROWSER_SUSPENDED_LAUNCH_FAILED") from exc
        finally:
            self._close_handle(null_input)
            self._close_handle(stdout_write)
            self._close_handle(stderr_write)
            self._close_handle(stdout_read)
            self._close_handle(stderr_read)

    def _terminate_created_process(self) -> None:
        if not self._process_handle:
            return
        try:
            terminate = self._kernel32.TerminateProcess
            terminate.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            terminate.restype = ctypes.c_bool
            if not terminate(self._process_handle, 1):
                return
            wait = self._kernel32.WaitForSingleObject
            wait.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            wait.restype = ctypes.c_uint32
            wait(self._process_handle, 2_000)
        except (AttributeError, OSError):
            return

    def _create_pipe(self) -> tuple[int, int]:
        create_pipe = self._kernel32.CreatePipe
        create_pipe.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(_SecurityAttributes), ctypes.c_uint32]
        create_pipe.restype = ctypes.c_bool
        set_handle = self._kernel32.SetHandleInformation
        set_handle.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
        set_handle.restype = ctypes.c_bool
        attributes = _SecurityAttributes(ctypes.sizeof(_SecurityAttributes), None, True)
        reader = ctypes.c_void_p()
        writer = ctypes.c_void_p()
        if not create_pipe(ctypes.byref(reader), ctypes.byref(writer), ctypes.byref(attributes), 0):
            raise WorkerContractError("BROWSER_SUSPENDED_LAUNCH_FAILED")
        if not set_handle(reader, _HANDLE_FLAG_INHERIT, 0):
            self._close_handle(int(reader.value))
            self._close_handle(int(writer.value))
            raise WorkerContractError("BROWSER_SUSPENDED_LAUNCH_FAILED")
        return int(reader.value), int(writer.value)

    def _open_null_input(self) -> int:
        create_file = self._kernel32.CreateFileW
        create_file.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(_SecurityAttributes), ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
        create_file.restype = ctypes.c_void_p
        attributes = _SecurityAttributes(ctypes.sizeof(_SecurityAttributes), None, True)
        handle = create_file("NUL", 0x80000000, 0x00000001 | 0x00000002, ctypes.byref(attributes), 3, 0x80, None)
        if not handle or handle == _INVALID_HANDLE_VALUE:
            raise WorkerContractError("BROWSER_SUSPENDED_LAUNCH_FAILED")
        return int(handle)

    def _open_reader(self, handle: int) -> Any:
        return os.fdopen(msvcrt.open_osfhandle(handle, os.O_RDONLY), "rb", buffering=0)

    def _close_handle(self, handle: int | None) -> bool:
        if not handle:
            return True
        return bool(self._kernel32.CloseHandle(handle))

    def resume(self) -> None:
        if not self._thread_handle:
            raise WorkerContractError("BROWSER_RESUME_FAILED")
        resume = self._kernel32.ResumeThread
        resume.argtypes = [ctypes.c_void_p]
        resume.restype = ctypes.c_uint32
        result = resume(self._thread_handle)
        if result != 1:
            raise WorkerContractError("BROWSER_RESUME_FAILED")
        deadline = time.monotonic() + 0.1
        while time.monotonic() < deadline:
            if self.poll() is None:
                if not self._close_handle(self._thread_handle):
                    raise WorkerContractError("BROWSER_RESUME_FAILED")
                self._thread_handle = None
                return
            time.sleep(_PATH_PROBE_INTERVAL_SECONDS)
        raise WorkerContractError("BROWSER_RESUME_FAILED")

    def poll(self) -> int | None:
        if self.returncode is not None:
            return self.returncode
        if not self._process_handle:
            return self.returncode
        wait = self._kernel32.WaitForSingleObject
        wait.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        wait.restype = ctypes.c_uint32
        state = wait(self._process_handle, 0)
        if state == _WAIT_TIMEOUT:
            return None
        if state != _WAIT_OBJECT_0:
            raise WorkerContractError("BROWSER_PROCESS_STATUS_FAILED")
        exit_code = ctypes.c_uint32()
        get_exit_code = self._kernel32.GetExitCodeProcess
        get_exit_code.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        get_exit_code.restype = ctypes.c_bool
        if not get_exit_code(self._process_handle, ctypes.byref(exit_code)):
            raise WorkerContractError("BROWSER_PROCESS_STATUS_FAILED")
        self.returncode = int(exit_code.value)
        return self.returncode

    def close(self) -> bool:
        ok = True
        for stream_name in ("stdout", "stderr"):
            stream = getattr(self, stream_name)
            if stream is not None:
                try:
                    stream.close()
                except OSError:
                    ok = False
                setattr(self, stream_name, None)
        if self._thread_handle:
            if self._close_handle(self._thread_handle):
                self._thread_handle = None
            else:
                ok = False
        if self._process_handle:
            if self._close_handle(self._process_handle):
                self._process_handle = None
            else:
                ok = False
        return ok


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

    def process_ids(self) -> list[int]:
        query = self._kernel32.QueryInformationJobObject
        query.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32)]
        query.restype = ctypes.c_bool
        size = 4_096
        while size <= 1_048_576:
            buffer = ctypes.create_string_buffer(size)
            returned = ctypes.c_uint32()
            if query(self._handle, _JOB_OBJECT_BASIC_PROCESS_ID_LIST, buffer, size, ctypes.byref(returned)):
                assigned = ctypes.c_uint32.from_buffer(buffer, 0).value
                listed = ctypes.c_uint32.from_buffer(buffer, ctypes.sizeof(ctypes.c_uint32)).value
                if assigned > 512 or listed > assigned or 8 + listed * ctypes.sizeof(ctypes.c_size_t) > size:
                    raise WorkerContractError("BROWSER_JOB_QUERY_FAILED")
                values = (ctypes.c_size_t * listed).from_buffer(buffer, 8)
                return sorted({int(value) for value in values})
            if ctypes.get_last_error() != _ERROR_MORE_DATA:
                raise WorkerContractError("BROWSER_JOB_QUERY_FAILED")
            size *= 2
        raise WorkerContractError("BROWSER_JOB_QUERY_FAILED")

    def close(self) -> bool:
        if self._handle:
            handle = self._handle
            if self._kernel32.CloseHandle(handle):
                self._handle = None
                return True
            return False
        return True


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
    if value:
        raise WorkerContractError("BROWSER_ARGUMENT_FORBIDDEN")
    return []


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while True:
                block = stream.read(65_536)
                if not block:
                    break
                digest.update(block)
    except OSError as exc:
        raise WorkerContractError("BROWSER_EXECUTABLE_READ_FAILED") from exc
    return digest.hexdigest()


def _sha256_parameter(plan: WorkerPlan, name: str) -> str:
    value = _required_string(plan, name).lower()
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise WorkerContractError(f"BROWSER_PARAMETER_INVALID:{name}")
    return value


def _positive_timeout_ms(plan: WorkerPlan, name: str) -> int:
    value = plan.raw["parameters"].get(name)
    operation_timeout_ms = plan.raw["operation_timeout_ms"]
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0 or value > operation_timeout_ms:
        raise WorkerContractError(f"BROWSER_PARAMETER_INVALID:{name}")
    return value


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
    if os.name != "nt":
        return False
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    open_process = kernel32.OpenProcess
    open_process.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    open_process.restype = ctypes.c_void_p
    terminate = kernel32.TerminateProcess
    terminate.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    terminate.restype = ctypes.c_bool
    close_handle = kernel32.CloseHandle
    close_handle.argtypes = [ctypes.c_void_p]
    close_handle.restype = ctypes.c_bool
    for pid in sorted(set(known_pids)):
        if not _process_running(pid):
            continue
        handle = open_process(_PROCESS_TERMINATE | _PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        try:
            if not terminate(handle, 1):
                return False
        finally:
            close_handle(handle)
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline and any(_process_running(pid) for pid in known_pids):
        time.sleep(0.025)
    return not any(_process_running(pid) for pid in known_pids)


def _create_isolated_directories(profile: Path, downloads: Path) -> tuple[bool, bool]:
    profile_created = False
    downloads_created = False
    try:
        profile.mkdir(parents=True, exist_ok=False)
        profile_created = True
        downloads.mkdir(parents=True, exist_ok=False)
        downloads_created = True
        return profile_created, downloads_created
    except OSError as exc:
        _remove_isolated_directories(profile, downloads, profile_created, downloads_created)
        raise WorkerContractError("BROWSER_ISOLATION_SETUP_FAILED") from exc


def _remove_isolated_directories(profile: Path, downloads: Path, profile_owned: bool, downloads_owned: bool) -> bool:
    for path, owned in ((downloads, downloads_owned), (profile, profile_owned)):
        if not owned:
            continue
        try:
            if path.exists():
                shutil.rmtree(path)
        except OSError:
            return False
    return (not downloads_owned or not downloads.exists()) and (not profile_owned or not profile.exists())


def _probe_actual_path(process: subprocess.Popen[bytes], timeout_ms: int) -> tuple[str, str, int, int]:
    started = time.monotonic()
    deadline = started + timeout_ms / 1000.0
    attempts = 0
    while True:
        if process.poll() is not None:
            elapsed = int((time.monotonic() - started) * 1000)
            return "", "PROCESS_EXITED", attempts, elapsed
        attempts += 1
        try:
            observed = _query_process_image(process.pid)
        except WorkerContractError:
            if time.monotonic() >= deadline:
                elapsed = int((time.monotonic() - started) * 1000)
                return "", "QUERY_TIMEOUT", attempts, elapsed
            time.sleep(_PATH_PROBE_INTERVAL_SECONDS)
            continue
        elapsed = int((time.monotonic() - started) * 1000)
        return observed, "PATH_OBTAINED", attempts, elapsed


def _drain_bounded(stream: Any, captured: bytearray, overflow: list[bool]) -> None:
    while True:
        block = stream.read(4096)
        if not block:
            return
        remaining = _MAX_BROWSER_OUTPUT_BYTES - len(captured)
        if remaining > 0:
            captured.extend(block[:remaining])
        if len(block) > remaining:
            overflow[0] = True


def _start_output_capture(process: subprocess.Popen[bytes]) -> tuple[bytearray, bytearray, list[bool], list[threading.Thread]]:
    stdout = bytearray()
    stderr = bytearray()
    overflow = [False]
    assert process.stdout is not None and process.stderr is not None
    readers = [
        threading.Thread(target=_drain_bounded, args=(process.stdout, stdout, overflow), daemon=True),
        threading.Thread(target=_drain_bounded, args=(process.stderr, stderr, overflow), daemon=True),
    ]
    for reader in readers:
        reader.start()
    return stdout, stderr, overflow, readers


def _wait_for_browser_exit(process: subprocess.Popen[bytes], deadline: float) -> None:
    while process.poll() is None:
        if time.monotonic() >= deadline:
            raise WorkerContractError("BROWSER_EVIDENCE_TIMEOUT")
        time.sleep(_PATH_PROBE_INTERVAL_SECONDS)


def _parse_dom_marker(dom: bytes) -> dict[str, Any]:
    try:
        text = dom.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise WorkerContractError("BROWSER_DOM_MARKER_INVALID") from exc
    marker_pattern = re.compile(
        r'<script\b[^>]*\bid=["\']' + re.escape(_DOM_RESULT_ID) + r'["\'][^>]*>(.*?)</script\s*>',
        re.IGNORECASE | re.DOTALL,
    )
    matches = marker_pattern.findall(text)
    if len(matches) != 1:
        raise WorkerContractError("BROWSER_DOM_MARKER_INVALID")
    try:
        marker = json.loads(matches[0])
    except json.JSONDecodeError as exc:
        raise WorkerContractError("BROWSER_DOM_MARKER_INVALID") from exc
    if not isinstance(marker, dict) or marker.get("dom_marker") != _DOM_MARKER:
        raise WorkerContractError("BROWSER_DOM_MARKER_INVALID")
    return marker


def run_browser(plan: WorkerPlan) -> list[dict[str, Any]]:
    """Run one isolated browser canary and return only post-cleanup evidence."""
    started = time.monotonic()
    requested = Path(_required_string(plan, "browser_executable"))
    if not requested.is_file():
        raise WorkerContractError("BROWSER_EXECUTABLE_MISSING")
    requested = requested.resolve()
    expected_image_sha256 = _sha256_parameter(plan, "expected_browser_sha256")
    if _sha256_file(requested) != expected_image_sha256:
        raise WorkerContractError("BROWSER_EXECUTABLE_HASH_MISMATCH")
    browser_identity = _required_string(plan, "expected_browser_identity")
    browser_version = _required_string(plan, "expected_browser_version")
    target_url = _required_string(plan, "target_url")
    parsed = urlparse(target_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise WorkerContractError("BROWSER_TARGET_URL_INVALID")
    profile = Path(_required_string(plan, "profile_dir")).resolve()
    downloads = Path(_required_string(plan, "download_dir")).resolve()
    if profile == downloads or profile.exists() or downloads.exists():
        raise WorkerContractError("BROWSER_ISOLATION_PATH_INVALID")
    expected_content_sha256 = _sha256_parameter(plan, "expected_content_sha256")
    expected_response_status = plan.raw["parameters"].get("expected_response_status")
    if isinstance(expected_response_status, bool) or not isinstance(expected_response_status, int) or not 100 <= expected_response_status <= 599:
        raise WorkerContractError("BROWSER_PARAMETER_INVALID:expected_response_status")
    expected_protocol = _required_string(plan, "expected_negotiated_protocol")
    virtual_time_budget_ms = _positive_timeout_ms(plan, "virtual_time_budget_ms") if "virtual_time_budget_ms" in plan.raw["parameters"] else min(1_000, plan.raw["operation_timeout_ms"])
    actual_path_timeout_ms = _positive_timeout_ms(plan, "actual_path_timeout_ms")

    process: _SuspendedBrowserProcess | None = None
    job: _BrowserJob | None = None
    profile_owned = False
    downloads_owned = False
    tree_pids: list[int] = []
    observed = ""
    probe_status = ""
    probe_attempts = 0
    probe_elapsed_ms = 0
    stdout = bytearray()
    stderr = bytearray()
    output_overflow = [False]
    readers: list[threading.Thread] = []
    failure: BaseException | None = None
    cleanup_ok = True
    try:
        profile_owned, downloads_owned = _create_isolated_directories(profile, downloads)
        command = [
            str(requested), *_browser_arguments(plan), "--headless=new", "--disable-background-networking", "--disable-sync",
            "--no-first-run", "--no-default-browser-check", "--dump-dom", f"--virtual-time-budget={virtual_time_budget_ms}",
            f"--user-data-dir={profile}", target_url,
        ]
        job = _BrowserJob()
        process = _SuspendedBrowserProcess(command, downloads)
        job.assign(process.pid)
        process.resume()
        stdout, stderr, output_overflow, readers = _start_output_capture(process)
        observed, probe_status, probe_attempts, probe_elapsed_ms = _probe_actual_path(process, actual_path_timeout_ms)
        if probe_status == "PROCESS_EXITED":
            raise WorkerContractError("BROWSER_EXITED_BEFORE_PATH_OBSERVABLE")
        if probe_status == "QUERY_TIMEOUT":
            raise WorkerContractError("BROWSER_OBSERVED_PATH_QUERY_TIMEOUT")
        if os.path.normcase(str(observed)) != os.path.normcase(str(requested)):
            raise WorkerContractError("BROWSER_OBSERVED_PATH_MISMATCH")
        tree_pids = _process_tree(process.pid)
        if process.pid not in tree_pids:
            raise WorkerContractError("BROWSER_PROCESS_TREE_INVALID")
        _wait_for_browser_exit(process, started + plan.raw["operation_timeout_ms"] / 1000.0)
        tree_pids = sorted(set(tree_pids) | set(job.process_ids()))
        for reader in readers:
            reader.join(timeout=2.0)
        if any(reader.is_alive() for reader in readers):
            raise WorkerContractError("BROWSER_OUTPUT_CAPTURE_FAILED")
        if output_overflow[0]:
            raise WorkerContractError("BROWSER_OUTPUT_LIMIT_EXCEEDED")
        if process.returncode != 0:
            raise WorkerContractError("BROWSER_PROCESS_FAILED")
        marker_data = _parse_dom_marker(bytes(stdout))
        content_sha256 = marker_data.get("content_sha256")
        if not isinstance(content_sha256, str) or content_sha256.lower() != expected_content_sha256:
            raise WorkerContractError("BROWSER_CONTENT_HASH_MISMATCH")
        if marker_data.get("response_status") != expected_response_status:
            raise WorkerContractError("BROWSER_RESPONSE_STATUS_MISMATCH")
        if marker_data.get("negotiated_protocol") != expected_protocol:
            raise WorkerContractError("BROWSER_NEGOTIATED_PROTOCOL_MISMATCH")
    except BaseException as exc:
        failure = exc
    finally:
        if job is not None:
            try:
                tree_pids = sorted(set(tree_pids) | set(job.process_ids()))
            except WorkerContractError:
                cleanup_ok = False
            cleanup_ok = job.close() and cleanup_ok
        if process is not None:
            if not tree_pids:
                try:
                    tree_pids = _process_tree(process.pid)
                except WorkerContractError:
                    tree_pids = [process.pid]
            cleanup_ok = _terminate_tree(process.pid, tree_pids) and cleanup_ok
        for reader in readers:
            reader.join(timeout=2.0)
        if any(reader.is_alive() for reader in readers):
            cleanup_ok = False
        if process is not None:
            cleanup_ok = process.close() and cleanup_ok
        directories_removed = _remove_isolated_directories(profile, downloads, profile_owned, downloads_owned)
        cleanup_ok = cleanup_ok and directories_removed
    if not cleanup_ok:
        raise WorkerContractError("BROWSER_TREE_CLEANUP_FAILED") from failure
    if failure is not None:
        if isinstance(failure, WorkerContractError):
            raise failure
        raise WorkerContractError("BROWSER_WORKER_UNEXPECTED_FAILURE") from failure

    payload_sha256 = expected_content_sha256
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
        "browser_identity": browser_identity,
        "browser_version": browser_version,
        "navigation_url_digest": hashlib.sha256(target_url.encode("utf-8")).hexdigest(),
        "negotiated_protocol": expected_protocol,
        "response_status": expected_response_status,
        "content_sha256": payload_sha256,
        "browser_executable_requested": str(requested),
        "browser_executable_observed": observed,
        "browser_image_sha256": expected_image_sha256,
        "browser_image_sha256_verified": True,
        "browser_process_tree_pids": tree_pids,
        "profile_id": hashlib.sha256(str(profile).encode("utf-8")).hexdigest(),
        "actual_path_probe_status": probe_status,
        "actual_path_probe_attempts": probe_attempts,
        "actual_path_probe_elapsed_ms": probe_elapsed_ms,
        "process_tree_cleaned": True,
    }]
