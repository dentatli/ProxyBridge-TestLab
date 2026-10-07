"""Prepare accept/query timestamps in a fresh Core copy; reuse the verified signed v4 kernel."""
import argparse,json,shutil
from pathlib import Path
from pb_prepare_kernel_context_diagnostic import prepare_kernel
from pb_prepare_redirect_context_diagnostic import digest

POLICY={'method':'accept-query-qpc-v1','points':['accept-return','query-entry','query-exit'],
        'logging_after_original_query':True,'original_single_query_preserved':True,'payload_recorded':False}
SUPPORT=r'''
static __declspec(thread) SOCKET pbdiag_accept_socket = INVALID_SOCKET;
static __declspec(thread) LARGE_INTEGER pbdiag_accept_ticks;
static __declspec(thread) LARGE_INTEGER pbdiag_accept_frequency;
static __declspec(thread) BOOL pbdiag_accept_valid;
void pbdiag_note_accept(SOCKET accepted)
{
    int previous_wsa = WSAGetLastError();
    pbdiag_accept_socket = accepted;
    BOOL tick_ok = QueryPerformanceCounter(&pbdiag_accept_ticks);
    BOOL frequency_ok = QueryPerformanceFrequency(&pbdiag_accept_frequency);
    pbdiag_accept_valid = tick_ok && frequency_ok && pbdiag_accept_frequency.QuadPart > 0;
    WSASetLastError(previous_wsa);
}
'''

def patch_timing(text):
    def sub(old,new):
        nonlocal text
        if text.count(old)!=1:raise ValueError('TIMING_PATCH_ANCHOR: '+old)
        text=text.replace(old,new,1)
    sub('static volatile LONG pbdiag_query_seq = 0;', 'static volatile LONG pbdiag_query_seq = 0;\n'+SUPPORT)
    sub('    DWORD bytes = 0;\n    int rc = WSAIoctl', '''    DWORD bytes = 0;
    int entry_wsa = WSAGetLastError();
    LARGE_INTEGER query_entry = {0};
    BOOL entry_valid = QueryPerformanceCounter(&query_entry);
    WSASetLastError(entry_wsa);
    int rc = WSAIoctl''')
    sub('    LARGE_INTEGER ticks, frequency;', '    LARGE_INTEGER ticks = {0}, frequency = {0};')
    sub('    QueryPerformanceCounter(&ticks);\n    QueryPerformanceFrequency(&frequency);', '''    BOOL exit_valid = QueryPerformanceCounter(&ticks);
    BOOL frequency_valid = QueryPerformanceFrequency(&frequency);
    BOOL accept_valid = pbdiag_accept_valid && pbdiag_accept_socket == accepted &&
        pbdiag_accept_frequency.QuadPart == frequency.QuadPart;
    LARGE_INTEGER accept_ticks = pbdiag_accept_ticks;
    pbdiag_accept_valid = FALSE;
    pbdiag_accept_socket = INVALID_SOCKET;
    LONG query_seq = InterlockedIncrement(&pbdiag_query_seq);''')
    sub('                InterlockedIncrement(&pbdiag_query_seq), (unsigned long long)accepted,','                query_seq, (unsigned long long)accepted,')
    sub('    WSASetLastError(wsa_after);\n    return complete;', '''    log_message("[CTXTIMING] seq=%ld socket=%llu relay_pid=%lu thread=%lu accept_qpc=%lld entry_qpc=%lld exit_qpc=%lld frequency=%lld valid=%d api_return=%d api_error=%d bytes=%lu",
                query_seq, (unsigned long long)accepted, GetCurrentProcessId(), GetCurrentThreadId(),
                accept_valid ? accept_ticks.QuadPart : 0, query_entry.QuadPart, ticks.QuadPart, frequency.QuadPart,
                accept_valid && entry_valid && exit_valid && frequency_valid && frequency.QuadPart > 0,
                rc, rc == SOCKET_ERROR ? wsa_after : 0, bytes);
    WSASetLastError(wsa_after);
    return complete;''')
    return text

def prepare(root,output,kernel_preparation):
    saved=json.loads((kernel_preparation/'kit/redirect-context-diagnostic.json').read_text(encoding='utf-8-sig'))
    expected='1e2acb496aa4caf703408f0b96ceae04b416a56616fa165270c619f4b404b103'
    if saved['method']!='redirect-kernel-context-v4' or digest(kernel_preparation/'kit/ProxyBridgeDrv.sys')!=expected:
        raise ValueError('TIMING_REQUIRES_VERIFIED_V4_KERNEL')
    metadata=prepare_kernel(root,output)
    if metadata['kernel_patched_source_sha256']!=saved['kernel_patched_source_sha256'] or metadata['added_sources']!=saved['added_sources']:
        raise ValueError('REUSED_KERNEL_SOURCE_DIFFERS')
    core=output/'source'/metadata['patched_file'];original=core.read_text(encoding='utf-8')
    core.write_text(patch_timing(original),encoding='utf-8')
    relay_rel='Windows/src/relay/pb_relay_tcp.c';relay=output/'source'/relay_rel
    text=relay.read_text(encoding='utf-8').replace('\r\n','\n')
    # Declare after includes, where SOCKET is already defined.
    declaration='extern void pbdiag_note_accept(SOCKET accepted);\n'
    anchor='    log_message("Local proxy listening on port %d", g_local_relay_port);'
    if text.count(anchor)!=1:raise ValueError('TIMING_RELAY_DECLARATION_ANCHOR')
    text=text.replace(anchor,'    '+declaration+anchor,1)
    for name in ('client_sock','client_sock6'):
        anchor=f'            SOCKET {name} = accept('
        start=text.index(anchor);end=text.index(';',start)+1
        text=text[:end]+f'\n            if ({name} != INVALID_SOCKET) pbdiag_note_accept({name});'+text[end:]
    relay.write_text(text,encoding='utf-8')
    shutil.copyfile(kernel_preparation/'kit/ProxyBridgeDrv.sys',output/'kit/ProxyBridgeDrv.sys')
    metadata.update(patched_source_sha256=digest(core),timing_patched_files={metadata['patched_file']:digest(core),relay_rel:digest(relay)},
        timing_policy=POLICY,reused_kernel_preparation=str(kernel_preparation),reused_kernel_sha256=expected,
        reused_kernel_build_receipt_sha256=digest(kernel_preparation/'kit/redirect-context-diagnostic.json'),signing=saved['signing'])
    (output/'preparation.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    (output/'verification/query-before-timing.c').write_text(original,encoding='utf-8')
    return metadata

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--kernel-preparation',type=Path,required=True)
    a=p.parse_args();r=prepare(a.root.resolve(),a.output.resolve(),a.kernel_preparation.resolve());print(json.dumps({'status':r['status'],'output':str(a.output)}))
