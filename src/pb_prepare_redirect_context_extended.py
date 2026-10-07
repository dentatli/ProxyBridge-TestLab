"""Prepare metadata queries after an original failure, in a fresh isolated Core copy."""
import argparse
import json
from pathlib import Path
from pb_prepare_redirect_context_diagnostic import prepare, PATCH, digest

METHOD = 'redirect-context-followup-v2'
FOLLOWUP = r'''// Bounded metadata observations only after the original API failure.
// No buffers are logged or passed to the relay; the original verdict stays FALSE.
static void pbdiag_followup(SOCKET accepted, LONG seq)
{
    BYTE records[1024] = {0}, wide[1024] = {0};
    DWORD record_bytes = 0, size_bytes = 0, wide_bytes = 0;
    int record_rc = WSAIoctl(accepted, SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
                             NULL, 0, records, sizeof(records), &record_bytes, NULL, NULL);
    int record_error = record_rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    int size_rc = WSAIoctl(accepted, SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
                           NULL, 0, NULL, 0, &size_bytes, NULL, NULL);
    int size_error = size_rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    int wide_rc = WSAIoctl(accepted, SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
                           NULL, 0, wide, sizeof(wide), &wide_bytes, NULL, NULL);
    int wide_error = wide_rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    BOOL wide_complete = wide_rc == 0 && wide_bytes >= sizeof(PBDRV_REDIRECT_CTX)
                                     && wide_bytes <= sizeof(wide);
    PBDRV_REDIRECT_CTX decoded = {0};
    if (wide_complete) memcpy(&decoded, wide, sizeof(decoded));
    log_message("[CTXDIAG_EXTRA] seq=%ld socket=%llu relay_pid=%lu "
                "records_return=%d records_error=%d records_bytes=%lu records_capacity=%lu "
                "size_return=%d size_error=%d size_bytes=%lu "
                "wide_return=%d wide_error=%d wide_bytes=%lu wide_capacity=%lu wide_complete=%d "
                "wide_family=%u wide_protocol=%u wide_ctx_pid=%lu",
                seq, (unsigned long long)accepted, GetCurrentProcessId(),
                record_rc, record_error, record_bytes, (DWORD)sizeof(records),
                size_rc, size_error, size_bytes, wide_rc, wide_error, wide_bytes, (DWORD)sizeof(wide),
                wide_complete, wide_complete ? (unsigned)decoded.family : 0,
                wide_complete ? (unsigned)decoded.protocol : 0, wide_complete ? decoded.pid : 0);
}
'''

def extended_patch():
    value=PATCH
    substitutions={
        'BOOL pbdrv_get_original_dest(SOCKET accepted, PBDRV_REDIRECT_CTX *ctx)': FOLLOWUP+'\nBOOL pbdrv_get_original_dest(SOCKET accepted, PBDRV_REDIRECT_CTX *ctx)',
        '    log_message("[CTXDIAG]': '    LONG seq = InterlockedIncrement(&pbdiag_query_seq);\n    log_message("[CTXDIAG]',
        'InterlockedIncrement(&pbdiag_query_seq), (unsigned long long)accepted': 'seq, (unsigned long long)accepted',
        '    WSASetLastError(wsa_after);': '    if (rc == SOCKET_ERROR) pbdiag_followup(accepted, seq);\n    WSASetLastError(wsa_after);',
    }
    for old,new in substitutions.items():
        if value.count(old)!=1:raise ValueError('FOLLOWUP_PATCH_ANCHOR_CHANGED')
        value=value.replace(old,new,1)
    return value

def prepare_extended(root,output):
    metadata=prepare(root,output)
    path=output/'source'/metadata['patched_file']
    text=path.read_text(encoding='utf-8')
    if text.count(PATCH)!=1:raise ValueError('FOLLOWUP_SOURCE_ANCHOR_CHANGED')
    path.write_text(text.replace(PATCH,extended_patch(),1),encoding='utf-8')
    metadata.update(method=METHOD,patched_source_sha256=digest(path),followup_only_after_api_failure=True,
        original_verdict_preserved=True,followup_buffer_capacity=1024,followup_queries_per_failure=3,
        followup_payload_recorded=False)
    (output/'preparation.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    return metadata

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=prepare_extended(args.root.resolve(),args.output.resolve())
    print(json.dumps(dict(status=result['status'],method=METHOD,output=str(args.output))))
