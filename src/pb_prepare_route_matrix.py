"""Prepare an isolated, sealed three-case Core; reuse the signed observation kernel."""
import argparse, hashlib, json, shutil
from pathlib import Path

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p, value): p.write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')

SETUP = '''    /* Diagnostic-only, fixed cases; no arbitrary runtime tuning. */
    char pbdiag_case[64] = {0};
    int pbdiag_saved_wsa = WSAGetLastError();
    DWORD pbdiag_case_length = GetEnvironmentVariableA("PB_TESTLAB_ROUTE_CASE", pbdiag_case, sizeof(pbdiag_case));
    int pbdiag_backlog;
    BOOL pbdiag_delay;
    if (pbdiag_case_length == 0 || pbdiag_case_length >= sizeof(pbdiag_case) ||
        (strcmp(pbdiag_case, "original") && strcmp(pbdiag_case, "backlog1024") && strcmp(pbdiag_case, "backlog1024-delay650")))
    {
        log_message("[ROUTECASE] invalid-selector; refusing diagnostic listener");
        WSASetLastError(pbdiag_saved_wsa);
        return 1;
    }
    pbdiag_backlog = !strcmp(pbdiag_case, "original") ? SOMAXCONN : SOMAXCONN_HINT(1024);
    pbdiag_delay = !strcmp(pbdiag_case, "backlog1024-delay650");
    log_message("[ROUTECASE] case=%s backlog=%d delay_ms=%d", pbdiag_case, pbdiag_backlog, pbdiag_delay ? 650 : 0);
    WSASetLastError(pbdiag_saved_wsa);
'''
DELAY = '''            if (pbdiag_delay && !pbdiag_first_accept_delayed)
            {
                pbdiag_first_accept_delayed = TRUE;
                int saved_wsa = WSAGetLastError();
                LARGE_INTEGER start, end, frequency;
                QueryPerformanceFrequency(&frequency);
                QueryPerformanceCounter(&start);
                Sleep(650);
                QueryPerformanceCounter(&end);
                log_message("[ROUTEDELAY] start_qpc=%lld end_qpc=%lld frequency=%lld requested_ms=650", start.QuadPart, end.QuadPart, frequency.QuadPart);
                WSASetLastError(saved_wsa);
            }
'''
LEG = '''/* Address/status metadata only; never inspect packet or context payloads. */
static void pbdiag_route_leg(const char *stage, SOCKET incoming, SOCKET upstream, int api_return)
{
    int saved_wsa = WSAGetLastError();
    LARGE_INTEGER qpc, frequency;
    QueryPerformanceCounter(&qpc);
    QueryPerformanceFrequency(&frequency);
    struct sockaddr_in native_peer = {0}, up_local = {0}, up_peer = {0};
    int length = sizeof(native_peer);
    int native_rc = getpeername(incoming, (struct sockaddr *)&native_peer, &length);
    int native_error = native_rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    length = sizeof(up_local);
    int local_rc = getsockname(upstream, (struct sockaddr *)&up_local, &length);
    int local_error = local_rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    length = sizeof(up_peer);
    int peer_rc = getpeername(upstream, (struct sockaddr *)&up_peer, &length);
    int peer_error = peer_rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    log_message("[ROUTELEG] stage=%s incoming_socket=%llu upstream_socket=%llu relay_pid=%lu thread=%lu qpc=%lld frequency=%lld api_return=%d api_error=%d native_family=%u native_v4=%u native_port=%u native_error=%d upstream_local_family=%u upstream_local_v4=%u upstream_local_port=%u upstream_local_error=%d upstream_peer_family=%u upstream_peer_v4=%u upstream_peer_port=%u upstream_peer_error=%d",
        stage, (unsigned long long)incoming, (unsigned long long)upstream, GetCurrentProcessId(), GetCurrentThreadId(), qpc.QuadPart, frequency.QuadPart,
        api_return, saved_wsa, native_peer.sin_family, native_peer.sin_addr.s_addr, ntohs(native_peer.sin_port), native_error,
        up_local.sin_family, up_local.sin_addr.s_addr, ntohs(up_local.sin_port), local_error,
        up_peer.sin_family, up_peer.sin_addr.s_addr, ntohs(up_peer.sin_port), peer_error);
    WSASetLastError(saved_wsa);
}

'''
CONNECT_OLD='    if (connect(socks_sock, (struct sockaddr *)&socks_addr, sizeof(socks_addr)) == SOCKET_ERROR)\n'
CONNECT_NEW='''    int pbdiag_connect_result = connect(socks_sock, (struct sockaddr *)&socks_addr, sizeof(socks_addr));
    pbdiag_route_leg("proxy-connect", client_sock, socks_sock, pbdiag_connect_result);
    if (pbdiag_connect_result == SOCKET_ERROR)
'''
HANDSHAKE='        pbdiag_route_leg("socks-handshake", client_sock, socks_sock, rc);\n'

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--parent', type=Path, required=True);ap.add_argument('--output', type=Path, required=True)
    args=ap.parse_args();parent=args.parent.resolve();new=args.output.resolve()
    if new.exists(): raise ValueError('ROUTE_PREPARATION_REQUIRES_FRESH_DIRECTORY')
    root=Path(__file__).resolve().parents[1]
    if new.parent != root/'artifacts/diagnostics': raise ValueError('ROUTE_PREPARATION_OUTSIDE_DIAGNOSTICS')
    build=read(parent/'kit/redirect-context-diagnostic.json')
    if build['method']!='redirect-kernel-context-v4' or build['listener_backlog_policy']['candidate_argument_value']!=-1024: raise ValueError('ROUTE_PARENT_INVALID')
    new.mkdir();shutil.copytree(parent/'source',new/'source');(new/'kit').mkdir();(new/'verification').mkdir()
    for name in ('ProxyBridge_CLI.exe','ProxyBridgeDrv.sys','LICENSE'):
        if (parent/'kit'/name).exists(): shutil.copy2(parent/'kit'/name,new/'kit'/name)
    original=new/'source/Windows/src/relay/pb_relay_tcp.c'
    text=original.read_text(encoding='utf-8-sig');before=text
    if text.count('SOMAXCONN_HINT(1024)')!=2 or '[ROUTECASE]' in text: raise ValueError('ROUTE_SOURCE_PARENT_DIFFERS')
    text=text.replace('DWORD WINAPI local_proxy_server(LPVOID arg)\n',LEG+'DWORD WINAPI local_proxy_server(LPVOID arg)\n',1)
    text=text.replace('    WSADATA wsa_data;\n',SETUP+'    WSADATA wsa_data;\n',1)
    text=text.replace('SOMAXCONN_HINT(1024)', 'pbdiag_backlog')
    # Restore the constant inside the selector, not the two listen arguments.
    text=text.replace('? SOMAXCONN : pbdiag_backlog;', '? SOMAXCONN : SOMAXCONN_HINT(1024);')
    declaration='    BOOL pbdiag_first_accept_delayed = FALSE;\n'
    text=text.replace('    extern void pbdiag_note_accept(SOCKET accepted);\n','    extern void pbdiag_note_accept(SOCKET accepted);\n'+declaration,1)
    anchor='            SOCKET client_sock = accept('
    text=text.replace(anchor,DELAY+anchor,1)
    if text.count(CONNECT_OLD)!=1: raise ValueError('ROUTE_PROXY_CONNECT_SOURCE_DIFFERS')
    text=text.replace(CONNECT_OLD,CONNECT_NEW,1).replace('        if (rc != 0)\n',HANDSHAKE+'        if (rc != 0)\n',1)
    inverse=text.replace(LEG,'',1).replace(CONNECT_NEW,CONNECT_OLD,1).replace(HANDSHAKE,'',1).replace(SETUP,'',1).replace(declaration,'',1).replace(DELAY,'',1).replace('listen(listen_sock, pbdiag_backlog)','listen(listen_sock, SOMAXCONN_HINT(1024))').replace('listen(listen_sock6, pbdiag_backlog)','listen(listen_sock6, SOMAXCONN_HINT(1024))')
    if inverse!=before: raise ValueError('ROUTE_INVERSE_SOURCE_DIFFERS')
    original.write_text(text,encoding='utf-8')
    policy=dict(method='listener-route-matrix-v1',diagnostic_only=True,performance_comparable=False,
        cases=['original','backlog1024','backlog1024-delay650'],selector='PB_TESTLAB_ROUTE_CASE',delay_ms=650,
        only_changed_source='Windows/src/relay/pb_relay_tcp.c',original_single_query_preserved=True,payload_pump_unchanged=True,
        wsa_state_preserved=True,payload_recorded=False,raw_kernel_pointers_recorded=False,route_leg_metadata='incoming-to-upstream-ipv4-status-qpc-v1',
        parent=str(parent),source_before_sha256=sha(parent/'source/Windows/src/relay/pb_relay_tcp.c'),source_after_sha256=sha(original),
        inverse_patch_exact=True,runtime_pending=True)
    prep=read(parent/'preparation.json')
    for key in ('listener_backlog_policy','accept_delay_policy'): prep.pop(key,None)
    prep['route_matrix_policy']=policy
    prep['timing_patched_files']['Windows/src/relay/pb_relay_tcp.c']=sha(original)
    prep['compiler_args']=[x.replace(str(parent),str(new)) for x in prep['compiler_args']]
    save(new/'preparation.json',prep);save(new/'verification/route-policy.json',policy)
    save(new/'verification/source-isolation.json',dict(parent=str(parent),inverse_patch_exact=True,
        changed_sources=[str(original.relative_to(new/'source'))],components_reused={x:sha(new/'kit'/x) for x in ('ProxyBridge_CLI.exe','ProxyBridgeDrv.sys')}))
    print(str(new))
if __name__=='__main__':main()
