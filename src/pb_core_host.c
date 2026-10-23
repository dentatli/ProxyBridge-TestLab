// TestLab session adapter for the selected, unmodified ProxyBridge Core DLL.
// Owns one Start/Stop, never toggles the product's global switch between cases.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef UINT32 (*ADD_PROXY)(int, const char *, UINT16, const char *, const char *, BOOL);
typedef UINT32 (*ADD_RULE)(const char *, const char *, const char *, const char *, int, int, UINT32, BOOL);
typedef UINT32 (*ADD_RULE_WFP)(const char *, const char *, const char *, const char *, int, int, UINT32);
typedef BOOL (*EDIT_RULE)(UINT32, const char *, const char *, const char *, const char *, int, int, UINT32, BOOL);
typedef BOOL (*EDIT_RULE_WFP)(UINT32, const char *, const char *, const char *, const char *, int, int, UINT32);
typedef BOOL (*RULE_OP)(UINT32);
typedef BOOL (*LIFECYCLE)(void);
typedef void (*VOID_OP)(void);
typedef void (*BOOL_SET)(BOOL);
typedef void (*LOG_SET)(void (*)(const char *));
typedef void (*CONN_SET)(void (*)(const char *, DWORD, const char *, UINT16, const char *));
static CRITICAL_SECTION output_lock;
static volatile LONG stopping = 0;
static DWORD worker_pid;
static UINT64 direct_count, proxy_count, blocked_count;
static void log_message(const char *message) {
    const unsigned char *p = (const unsigned char *)message;
    unsigned n = 0;
    EnterCriticalSection(&output_lock);
    fputs("PB_LOG\t", stdout);
    while (*p && n++ < 4096) { fprintf(stdout, "%02x", *p); p++; }
    fputc('\n', stdout); fflush(stdout);
    LeaveCriticalSection(&output_lock);
}
static void connection(const char *process, DWORD pid, const char *ip, UINT16 port, const char *route) {
    (void)process; (void)ip; (void)port;
    if (pid != worker_pid) return;
    EnterCriticalSection(&output_lock);
    if (strstr(route, "Proxy") || strstr(route, "SOCKS") || strstr(route, "proxy")) proxy_count++;
    else if (strstr(route, "Direct") || strstr(route, "DIRECT")) direct_count++;
    else if (strstr(route, "Block") || strstr(route, "BLOCK")) blocked_count++;
    LeaveCriticalSection(&output_lock);
}
static BOOL WINAPI stop_handler(DWORD event) { (void)event; InterlockedExchange(&stopping, 1); return TRUE; }
static void ack(unsigned id, BOOL ok, UINT32 config, UINT32 rule, BOOL enabled) {
    EnterCriticalSection(&output_lock);
    fprintf(stdout, "PB_ACK\t%u\t%d\t%u\t%u\t%d\t%llu\t%llu\t%llu\n", id, !!ok, config, rule, !!enabled,
        (unsigned long long)direct_count, (unsigned long long)proxy_count, (unsigned long long)blocked_count);
    fflush(stdout); LeaveCriticalSection(&output_lock);
}
static BOOL number(const char *s, unsigned *out) {
    char *end; unsigned long value;
    if (!*s || *s < '0' || *s > '9') return FALSE;
    value = strtoul(s, &end, 10); if (*end) return FALSE; *out = value; return TRUE;
}
// All text fields are hex UTF-8: no command delimiters or credentials in argv.
static BOOL decode(char *s) {
    size_t i, length = strlen(s); unsigned value;
    if (length % 2) return FALSE;
    for (i = 0; i < length; i += 2) {
        if (!strchr("0123456789abcdef", s[i]) || !strchr("0123456789abcdef", s[i+1])) return FALSE;
        if (sscanf_s(s+i, "%2x", &value) != 1 || !value) return FALSE;
        s[i/2] = (char)value;
    }
    s[length/2] = 0; return TRUE;
}
int wmain(int argc, wchar_t **argv) {
    HMODULE core;
    ADD_PROXY add_proxy; FARPROC add_rule, edit_rule;
    RULE_OP disable_rule, enable_rule; LIFECYCLE start, stop;
    VOID_OP clear_logs;
    LOG_SET set_log; CONN_SET set_connection; BOOL_SET logging, localhost, every;
    BOOL wfp, started = FALSE, enabled = FALSE, ok;
    UINT32 config = 0, rule = 0;
    char line[8192], process[1024] = {0}, host[1024] = {0};
    wchar_t loaded_path[32768];
    DWORD length = 0; int exit_code = 2;
    if (argc != 3 || (wcscmp(argv[2], L"wfp") && wcscmp(argv[2], L"windivert43"))) return 2;
    wfp = !wcscmp(argv[2], L"wfp");
    InitializeCriticalSection(&output_lock);
    if (!SetConsoleCtrlHandler(stop_handler, TRUE)) return 2;
    // Absolute selected path, normal dependency resolution limited to its folder/System32.
    core = LoadLibraryExW(argv[1], NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!core) return 2;
    if (!GetModuleFileNameW(core, loaded_path, 32768) || _wcsicmp(loaded_path, argv[1])) return 2;
#define RESOLVE(variable, type, name) variable = (type)GetProcAddress(core, "ProxyBridge_" name); if (!variable) return 2
    RESOLVE(add_proxy, ADD_PROXY, "AddProxyConfig");
    RESOLVE(add_rule, FARPROC, "AddRule"); RESOLVE(edit_rule, FARPROC, "EditRule");
    RESOLVE(disable_rule, RULE_OP, "DisableRule"); RESOLVE(enable_rule, RULE_OP, "EnableRule");
    RESOLVE(start, LIFECYCLE, "Start"); RESOLVE(stop, LIFECYCLE, "Stop");
    RESOLVE(set_log, LOG_SET, "SetLogCallback"); RESOLVE(set_connection, CONN_SET, "SetConnectionCallback");
    RESOLVE(logging, BOOL_SET, "SetTrafficLoggingEnabled");
    RESOLVE(clear_logs, VOID_OP, "ClearConnectionLogs");
    localhost = (BOOL_SET)GetProcAddress(core, "ProxyBridge_SetLocalhostViaProxy");
    every = (BOOL_SET)GetProcAddress(core, "ProxyBridge_SetLogEveryConnection");
    if (wfp && !localhost) return 2;
    set_log(log_message); set_connection(connection); logging(TRUE);
    if (localhost) localhost(TRUE); if (every) every(TRUE);
    while (!InterlockedCompareExchange(&stopping, 0, 0)) {
        DWORD available = 0, count = 0; char ch, *fields[14], *next; unsigned n = 0, id = 0, port = 0, pid = 0;
        if (!PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE), NULL, 0, NULL, &available, NULL)) break;
        if (!available) { Sleep(5); continue; }
        if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), &ch, 1, &count, NULL) || count != 1) break;
        if (ch == '\r') continue;
        if (ch != '\n') { if (length >= sizeof(line)-1) break; line[length++] = ch; continue; }
        line[length] = 0; length = 0;
        fields[n++] = line;
        for (next = line; *next; next++) if (*next == '\t') { *next = 0; if (n == 14) goto finish; fields[n++] = next+1; }
        if (n < 3 || strcmp(fields[0], "PB_CMD") || !number(fields[1], &id)) break;
        ok = FALSE;
        if (!strcmp(fields[2], "INIT") && n == 10 && !started && !config) {
            unsigned j;
            if (!number(fields[4], &port) || !port || port > 65535 || !number(fields[9], &pid) || !pid) break;
            for (j=3; j<=8; j++) if (j != 4 && !decode(fields[j])) goto finish;
            if (strlen(fields[3]) >= sizeof(host) || strlen(fields[7]) >= sizeof(process)) break;
            strcpy_s(host, sizeof(host), fields[3]); strcpy_s(process, sizeof(process), fields[7]); worker_pid = pid;
            config = add_proxy(1, host, (UINT16)port, fields[5], fields[6], FALSE);
            if (!config) break;
            rule = wfp ? ((ADD_RULE_WFP)add_rule)(process, host, fields[8], "", 2, 0, config) :
                ((ADD_RULE)add_rule)(process, host, fields[8], "", 2, 0, config, TRUE);
            if (!rule || !disable_rule(rule)) break;
            started = start(); ok = started;
        } else if (!strcmp(fields[2], "RULE") && n == 5 && started && !strcmp(fields[4], "1") && decode(fields[3])) {
            ok = disable_rule(rule); enabled = FALSE;
            if (ok) ok = wfp ? ((EDIT_RULE_WFP)edit_rule)(rule, process, host, fields[3], "", 2, 0, config) :
                ((EDIT_RULE)edit_rule)(rule, process, host, fields[3], "", 2, 0, config, TRUE);
            if (ok) { ok = enable_rule(rule); enabled = ok; }
        } else if (!strcmp(fields[2], "DISABLE") && n == 3 && started) {
            ok = disable_rule(rule); if (ok) enabled = FALSE;
        } else if (!strcmp(fields[2], "SNAP") && n == 3 && started) ok = TRUE;
        if (ok && (!strcmp(fields[2], "RULE") || !strcmp(fields[2], "DISABLE"))) clear_logs();
        ack(id, ok, config, rule, enabled);
        if (!ok) break;
    }
finish:
    if (started) { ok = disable_rule(rule); enabled = FALSE; if (stop() && ok) exit_code = 0; }
    // Keep the module and callback code mapped through process exit. No FreeLibrary race.
    return exit_code;
}
