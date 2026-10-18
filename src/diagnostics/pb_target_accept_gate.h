/* Diagnostic Core only: one externally released IPv4 accept barrier. */
static BOOL pbdiag_target_accept_gate(void)
{
    char token[33] = {0}, route_case[9] = {0}, name[96];
    DWORD n, wait_result = WAIT_FAILED;
    HANDLE ready = NULL, release = NULL;
    BOOL ok = FALSE;
    int saved_wsa = WSAGetLastError();
    ULONGLONG started;
    if (GetEnvironmentVariableA("PB_TESTLAB_ROUTE_CASE", route_case, sizeof(route_case)) != 8 ||
        strcmp(route_case, "original")) goto done;
    n = GetEnvironmentVariableA("PB_TESTLAB_TARGET_GATE", token, sizeof(token));
    if (n != 32) goto done;
    for (DWORD i = 0; i < n; ++i)
        if (!((token[i] >= '0' && token[i] <= '9') || (token[i] >= 'a' && token[i] <= 'f'))) goto done;
    snprintf(name, sizeof(name), "Local\\PBTarget-%s-ready", token);
    ready = OpenEventA(EVENT_MODIFY_STATE, FALSE, name);
    if (!ready) goto done;
    snprintf(name, sizeof(name), "Local\\PBTarget-%s-release", token);
    release = OpenEventA(SYNCHRONIZE, FALSE, name);
    if (!release) goto done;
    if (!SetEvent(ready)) goto done;
    log_message("[TARGETGATE] stage=ready token=%s timeout_ms=30000", token);
    started = GetTickCount64();
    while (running && GetTickCount64() - started < 30000) {
        wait_result = WaitForSingleObject(release, 50);
        if (wait_result == WAIT_OBJECT_0) {ok = TRUE; break;}
        if (wait_result != WAIT_TIMEOUT) break;
    }
done:
    if (release) CloseHandle(release);
    if (ready) CloseHandle(ready);
    log_message("[TARGETGATE] stage=exit released=%d wait_result=%lu", ok, wait_result);
    WSASetLastError(saved_wsa);
    return ok;
}
