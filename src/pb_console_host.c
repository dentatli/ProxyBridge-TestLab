// Own one CLI in an isolated console or ConPTY. Never signal an inherited console.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

enum { HOST_NATURAL_EXIT = 0, HOST_BREAK_EXIT = 10, HOST_FORCED_EXIT = 11, HOST_ERROR = 12 };

typedef struct { HANDLE input, output; } TERMINAL_OUTPUT;

// Win32 ConPTY pipe forwarding follows Microsoft's EchoCon/MiniTerm samples.
// Keep draining while ClosePseudoConsole emits its final output frame.
static DWORD WINAPI forward_terminal_output(void *parameter) {
    TERMINAL_OUTPUT *pipes = (TERMINAL_OUTPUT *)parameter;
    char buffer[4096];
    DWORD count, offset, written;
    for (;;) {
        if (!ReadFile(pipes->input, buffer, sizeof(buffer), &count, NULL))
            return GetLastError() == ERROR_BROKEN_PIPE ? 0 : 1;
        if (count == 0) return 0;
        for (offset = 0; offset < count; offset += written) {
            if (!WriteFile(pipes->output, buffer + offset, count - offset, &written, NULL) || !written) return 1;
        }
    }
}

static DWORD WINAPI close_terminal(void *parameter) {
    ClosePseudoConsole((HPCON)parameter);
    return 0;
}

static BOOL WINAPI ignore_control(DWORD event) { (void)event; return TRUE; }

static BOOL append_char(wchar_t *buffer, size_t *length, wchar_t ch) {
    if (*length >= 32766) return FALSE;
    buffer[(*length)++] = ch;
    buffer[*length] = 0;
    return TRUE;
}

// Windows CRT quoting, including trailing backslashes and embedded quotes.
static BOOL append_arg(wchar_t *buffer, size_t *length, const wchar_t *arg) {
    size_t slashes = 0;
    if (*length && !append_char(buffer, length, L' ')) return FALSE;
    if (!append_char(buffer, length, L'"')) return FALSE;
    for (;;) {
        wchar_t ch = *arg++;
        if (ch == L'\\') { slashes++; continue; }
        if (ch == L'"' || ch == 0) slashes *= 2;
        while (slashes) { if (!append_char(buffer, length, L'\\')) return FALSE; slashes--; }
        if (ch == L'"' && !append_char(buffer, length, L'\\')) return FALSE;
        if (ch == 0) break;
        if (!append_char(buffer, length, ch)) return FALSE;
    }
    return append_char(buffer, length, L'"');
}

static BOOL duplicate_inheritable(HANDLE source, HANDLE *target) {
    return DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), target, 0, TRUE, DUPLICATE_SAME_ACCESS);
}

static BOOL send_owned_break(const PROCESS_INFORMATION *child) {
    DWORD members[4], count, i;
    BOOL saw_child = FALSE, sent = FALSE;
    // The retained process handle prevents PID reuse while attaching.
    if (WaitForSingleObject(child->hProcess, 0) != WAIT_TIMEOUT) return FALSE;
    FreeConsole();
    if (!AttachConsole(child->dwProcessId)) return FALSE;
    if (!SetConsoleCtrlHandler(ignore_control, TRUE)) { FreeConsole(); return FALSE; }
    count = GetConsoleProcessList(members, 4);
    if (count == 0 || count > 4) { FreeConsole(); return FALSE; }
    for (i = 0; i < count; i++) {
        if (members[i] == child->dwProcessId) saw_child = TRUE;
        else if (members[i] != GetCurrentProcessId()) { FreeConsole(); return FALSE; }
    }
    // Group zero is confined to the NEW_CONSOLE created below, after census.
    if (saw_child) sent = GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, 0);
    // Stay attached until exit: FreeConsole would reset our control handler
    // while delivery is still asynchronous.
    return sent;
}

int wmain(int argc, wchar_t **argv) {
    STARTUPINFOEXW startup = {0};
    PROCESS_INFORMATION child = {0};
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
    SECURITY_ATTRIBUTES security = {sizeof(SECURITY_ATTRIBUTES), NULL, TRUE};
    HANDLE job = NULL, input = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE inherited[3] = {NULL, NULL, INVALID_HANDLE_VALUE};
    HANDLE terminal_in_read = NULL, terminal_in_write = NULL;
    HANDLE terminal_out_read = NULL, terminal_out_write = NULL, output_thread = NULL;
    HPCON terminal = NULL;
    TERMINAL_OUTPUT terminal_output = {NULL, NULL};
    SIZE_T attribute_size = 0;
    wchar_t *command = NULL, *end = NULL;
    size_t command_length = 0;
    unsigned long stop_ms;
    int result = HOST_ERROR, i, offset;
    BOOL use_terminal;
    BOOL attributes_ready = FALSE, assigned = FALSE, signalled = FALSE;
    char request[8] = {0};
    DWORD request_length = 0;
    use_terminal = argc > 1 && wcscmp(argv[1], L"--terminal") == 0;
    offset = use_terminal ? 1 : 0;
    if (argc < 4 + offset) return HOST_ERROR;
    stop_ms = wcstoul(argv[1 + offset], &end, 10);
    if (*end || stop_ms < 1 || stop_ms > 60000) return HOST_ERROR;
    command = (wchar_t *)calloc(32768, sizeof(wchar_t));
    if (!command) goto done;
    for (i = 2 + offset; i < argc; i++) if (!append_arg(command, &command_length, argv[i])) goto done;
    job = CreateJobObjectW(NULL, NULL);
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) goto done;
    if (use_terminal) {
        COORD size = {240, 80};
        if (!CreatePipe(&terminal_in_read, &terminal_in_write, NULL, 0) ||
            !CreatePipe(&terminal_out_read, &terminal_out_write, NULL, 0)) goto done;
        if (FAILED(CreatePseudoConsole(size, terminal_in_read, terminal_out_write, 0, &terminal))) goto done;
        CloseHandle(terminal_in_read); terminal_in_read = NULL;
        CloseHandle(terminal_out_write); terminal_out_write = NULL;
        terminal_output.input = terminal_out_read;
        terminal_output.output = GetStdHandle(STD_OUTPUT_HANDLE);
        output_thread = CreateThread(NULL, 0, forward_terminal_output, &terminal_output, 0, NULL);
        if (!output_thread) goto done;
    } else {
        if (!duplicate_inheritable(GetStdHandle(STD_OUTPUT_HANDLE), &inherited[0]) ||
            !duplicate_inheritable(GetStdHandle(STD_ERROR_HANDLE), &inherited[1])) goto done;
        inherited[2] = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
        if (inherited[2] == INVALID_HANDLE_VALUE) goto done;
    }
    InitializeProcThreadAttributeList(NULL, 2, 0, &attribute_size);
    startup.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attribute_size);
    if (!startup.lpAttributeList || !InitializeProcThreadAttributeList(startup.lpAttributeList, 2, 0, &attribute_size)) goto done;
    attributes_ready = TRUE;
    if (use_terminal) {
        if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, terminal, sizeof(terminal), NULL, NULL)) goto done;
    } else if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, sizeof(inherited), NULL, NULL)) goto done;
    // Assign atomically at creation, so a host crash cannot leave an orphan
    // between CreateProcess and a later AssignProcessToJobObject call.
    if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_JOB_LIST, &job, sizeof(job), NULL, NULL)) goto done;
    startup.StartupInfo.cb = sizeof(startup);
    if (!use_terminal) {
        startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
        startup.StartupInfo.wShowWindow = SW_HIDE;
        startup.StartupInfo.hStdOutput = inherited[0];
        startup.StartupInfo.hStdError = inherited[1];
        startup.StartupInfo.hStdInput = inherited[2];
    }
    if (!CreateProcessW(argv[2 + offset], command, NULL, NULL, !use_terminal,
        (use_terminal ? 0 : CREATE_NEW_CONSOLE) | CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT,
        NULL, NULL, &startup.StartupInfo, &child)) goto done;
    assigned = TRUE;
    // The first stderr line is ours, before the product can write anything.
    fprintf(stderr, "PB_CONSOLE_HOST_PID=%lu\n", child.dwProcessId);
    fflush(stderr);
    if (ResumeThread(child.hThread) == (DWORD)-1) goto done;
    for (;;) {
        DWORD available = 0, read_count = 0;
        char ch;
        DWORD wait = WaitForSingleObject(child.hProcess, 25);
        if (wait == WAIT_OBJECT_0) { result = HOST_NATURAL_EXIT; goto done; }
        if (wait != WAIT_TIMEOUT) goto done;
        if (use_terminal && WaitForSingleObject(output_thread, 0) != WAIT_TIMEOUT) goto done;
        // EOF also requests cleanup, e.g. when the runner disappears.
        if (!PeekNamedPipe(input, NULL, 0, NULL, &available, NULL)) break;
        if (!available) continue;
        if (!ReadFile(input, &ch, 1, &read_count, NULL) || read_count != 1) break;
        if (ch == '\n') {
            if (request_length != 4 || memcmp(request, "STOP", 4) != 0) goto done;
            break;
        }
        if (ch == '\r') continue;
        if (request_length >= sizeof(request)) goto done;
        request[request_length++] = ch;
    }
    if (use_terminal) {
        // Microsoft MiniTerm forwards Ctrl+C as ETX to its owned pseudoconsole.
        char control = 3;
        DWORD written = 0;
        signalled = WriteFile(terminal_in_write, &control, 1, &written, NULL) && written == 1;
    } else { signalled = send_owned_break(&child); }
    if (signalled && WaitForSingleObject(child.hProcess, stop_ms) == WAIT_OBJECT_0) {
        result = HOST_BREAK_EXIT;
    } else {
        result = HOST_FORCED_EXIT;
    }
done:
    if (child.hProcess && WaitForSingleObject(child.hProcess, 0) != WAIT_OBJECT_0) {
        BOOL terminated = assigned ? TerminateJobObject(job, HOST_FORCED_EXIT) : TerminateProcess(child.hProcess, HOST_FORCED_EXIT);
        if (!terminated || WaitForSingleObject(child.hProcess, 5000) != WAIT_OBJECT_0) result = HOST_ERROR;
    }
    if (terminal) {
        HANDLE closing = CreateThread(NULL, 0, close_terminal, terminal, 0, NULL);
        // Bound teardown too. The forwarding thread continues draining here.
        // ExitProcess releases the job on a stalled ConPTY; no cleanup pass.
        if (!closing || WaitForSingleObject(closing, 3000) != WAIT_OBJECT_0) ExitProcess(HOST_ERROR);
        CloseHandle(closing);
    }
    if (output_thread) {
        DWORD output_result = 1;
        if (WaitForSingleObject(output_thread, 2000) != WAIT_OBJECT_0) ExitProcess(HOST_ERROR);
        if (!GetExitCodeThread(output_thread, &output_result) || output_result != 0) result = HOST_ERROR;
        CloseHandle(output_thread);
    }
    if (terminal_in_read) CloseHandle(terminal_in_read);
    if (terminal_in_write) CloseHandle(terminal_in_write);
    if (terminal_out_read) CloseHandle(terminal_out_read);
    if (terminal_out_write) CloseHandle(terminal_out_write);
    // No service/driver cleanup is implied by terminating this job.
    FreeConsole();
    if (child.hThread) CloseHandle(child.hThread);
    if (child.hProcess) CloseHandle(child.hProcess);
    if (job) CloseHandle(job);
    for (i = 0; i < 3; i++) if (inherited[i] && inherited[i] != INVALID_HANDLE_VALUE) CloseHandle(inherited[i]);
    if (attributes_ready) DeleteProcThreadAttributeList(startup.lpAttributeList);
    free(startup.lpAttributeList);
    free(command);
    return result;
}
