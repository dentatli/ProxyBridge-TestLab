"""Prepare bounded positive controls, delayed context and socket metadata in an isolated Core."""
import argparse
import json
from pathlib import Path
from pb_prepare_redirect_context_extended import prepare_extended, extended_patch
from pb_prepare_redirect_context_diagnostic import digest

METHOD = 'redirect-context-probes-v3'
POLICY = dict(positive_first_sequences=4, positive_sequence_stride=128, positive_limit=16,
              delayed_targets_ms=[5,25,100], delayed_failure_limit=1000,
              probe_buffer_capacity=1024, socket_metadata='type-and-endpoints-no-so-error-v1',
              original_verdict_preserved=True, probe_payload_recorded=False)

PROBES = r'''// Extra observations are bounded and never replace the original result or buffer.
static volatile LONG pbdiag_positive_count = 0, pbdiag_delayed_count = 0;
static void pbdiag_positive(SOCKET accepted, LONG seq)
{
    BYTE buffer[1024] = {0}; DWORD bytes = 0;
    LARGE_INTEGER before, after; QueryPerformanceCounter(&before);
    int rc = WSAIoctl(accepted, SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
                      NULL, 0, buffer, sizeof(buffer), &bytes, NULL, NULL);
    int error = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    QueryPerformanceCounter(&after);
    log_message("[CTXDIAG_CONTROL] seq=%ld socket=%llu relay_pid=%lu qpc_before=%lld qpc_after=%lld "
                "api_return=%d api_error=%d bytes=%lu capacity=%lu",
                seq, (unsigned long long)accepted, GetCurrentProcessId(), before.QuadPart, after.QuadPart,
                rc, error, bytes, (DWORD)sizeof(buffer));
}
static void pbdiag_socket(SOCKET accepted, LONG seq, DWORD target, LONGLONG qpc)
{
    int type = 0, length = sizeof(type);
    int rc = getsockopt(accepted, SOL_SOCKET, SO_TYPE, (char *)&type, &length);
    int error = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    char local[INET6_ADDRSTRLEN], peer[INET6_ADDRSTRLEN]; USHORT local_port, peer_port;
    int local_error, peer_error;
    pbdiag_endpoint(accepted, FALSE, local, sizeof(local), &local_port, &local_error);
    pbdiag_endpoint(accepted, TRUE, peer, sizeof(peer), &peer_port, &peer_error);
    log_message("[CTXDIAG_SOCKET] seq=%ld socket=%llu relay_pid=%lu target_ms=%lu qpc=%lld "
                "type_return=%d type_error=%d type_bytes=%d socket_type=%d "
                "local_addr=%s local_port=%u local_error=%d peer_addr=%s peer_port=%u peer_error=%d",
                seq, (unsigned long long)accepted, GetCurrentProcessId(), target, qpc,
                rc, error, length, rc == 0 && length == sizeof(type) ? type : 0,
                local, local_port, local_error, peer, peer_port, peer_error);
}
static void pbdiag_delayed(SOCKET accepted, LONG seq, LARGE_INTEGER start, LARGE_INTEGER frequency)
{
    static const DWORD targets[3] = {5,25,100};
    LARGE_INTEGER now; QueryPerformanceCounter(&now);
    pbdiag_socket(accepted, seq, 0, now.QuadPart);
    for (int i = 0; i < 3; ++i) {
        QueryPerformanceCounter(&now);
        double elapsed = (double)(now.QuadPart-start.QuadPart)*1000.0/(double)frequency.QuadPart;
        if (elapsed < targets[i]) Sleep((DWORD)(targets[i]-elapsed)+1);
        LARGE_INTEGER before, after; QueryPerformanceCounter(&before);
        BYTE buffer[1024] = {0}; DWORD bytes = 0;
        int rc = WSAIoctl(accepted, SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
                          NULL, 0, buffer, sizeof(buffer), &bytes, NULL, NULL);
        int error = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
        QueryPerformanceCounter(&after);
        BOOL complete = rc == 0 && bytes >= sizeof(PBDRV_REDIRECT_CTX) && bytes <= sizeof(buffer);
        PBDRV_REDIRECT_CTX decoded = {0}; char destination[INET6_ADDRSTRLEN] = "unavailable";
        USHORT destination_port = 0;
        if (complete) {
            memcpy(&decoded, buffer, sizeof(decoded));
            if (decoded.family == AF_INET) {
                struct in_addr address; address.s_addr = decoded.origV4;
                if (InetNtopA(AF_INET, &address, destination, sizeof(destination)) == NULL)
                    strcpy_s(destination, sizeof(destination), "unavailable");
                destination_port = decoded.origPort;
            }
        }
        log_message("[CTXDIAG_LATE] seq=%ld socket=%llu relay_pid=%lu target_ms=%lu qpc_before=%lld qpc_after=%lld "
                    "api_return=%d api_error=%d bytes=%lu capacity=%lu complete=%d family=%u protocol=%u "
                    "ctx_pid=%lu destination_addr=%s destination_port=%u",
                    seq, (unsigned long long)accepted, GetCurrentProcessId(), targets[i], before.QuadPart, after.QuadPart,
                    rc, error, bytes, (DWORD)sizeof(buffer), complete, complete ? (unsigned)decoded.family : 0,
                    complete ? (unsigned)decoded.protocol : 0, complete ? decoded.pid : 0,
                    destination, destination_port);
        pbdiag_socket(accepted, seq, targets[i], after.QuadPart);
    }
}
'''

def probes_patch():
    value=extended_patch()
    anchor='BOOL pbdrv_get_original_dest(SOCKET accepted, PBDRV_REDIRECT_CTX *ctx)'
    assert value.count(anchor)==1
    value=value.replace(anchor,PROBES+'\n'+anchor,1)
    anchor='    if (rc == SOCKET_ERROR) pbdiag_followup(accepted, seq);'
    replacement='''    if (complete && ctx->family == AF_INET && (seq <= 4 || seq % 128 == 0) &&
        InterlockedIncrement(&pbdiag_positive_count) <= 16) pbdiag_positive(accepted, seq);
    if (rc == SOCKET_ERROR) {
        pbdiag_followup(accepted, seq);
        if (InterlockedIncrement(&pbdiag_delayed_count) <= 1000 && frequency.QuadPart > 0)
            pbdiag_delayed(accepted, seq, ticks, frequency);
    }'''
    assert value.count(anchor)==1
    return value.replace(anchor,replacement,1)

def prepare_probes(root,output):
    metadata=prepare_extended(root,output)
    path=output/'source'/metadata['patched_file']
    value=path.read_text(encoding='utf-8')
    assert value.count(extended_patch())==1
    path.write_text(value.replace(extended_patch(),probes_patch(),1),encoding='utf-8')
    metadata.update(method=METHOD,probe_policy=POLICY,patched_source_sha256=digest(path))
    (output/'preparation.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    return metadata

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();result=prepare_probes(args.root.resolve(),args.output.resolve())
    print(json.dumps(dict(status=result['status'],method=METHOD,output=str(args.output))))
