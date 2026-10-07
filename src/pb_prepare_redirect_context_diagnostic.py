"""Prepare an isolated logging-only Core copy from the pinned archive. No execution."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

COMMIT = '63be0ebf9bec92bfba95ef3d6729c375aa9af84e'
ARCHIVE = '0381286929084199f68189f97b904731a602e21d158aed8b76dce69b755b746d'

PATCH = r'''// Diagnostic-only: query arguments, verdict and context remain upstream.
// Preserve the immediate Winsock state across metadata/logging calls.
extern void log_message(const char *msg, ...);
static volatile LONG pbdiag_query_seq = 0;
static void pbdiag_endpoint(SOCKET s, BOOL peer, char *ip, DWORD cap, USHORT *port, int *error)
{
    SOCKADDR_STORAGE address;
    int length = sizeof(address);
    int rc = peer ? getpeername(s, (SOCKADDR *)&address, &length)
                  : getsockname(s, (SOCKADDR *)&address, &length);
    *error = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
    *port = 0;
    strcpy_s(ip, cap, "unavailable");
    if (rc == 0 && address.ss_family == AF_INET) {
        struct sockaddr_in *v4 = (struct sockaddr_in *)&address;
        if (InetNtopA(AF_INET, &v4->sin_addr, ip, cap) == NULL) *error = WSAGetLastError();
        *port = ntohs(v4->sin_port);
    } else if (rc == 0 && address.ss_family == AF_INET6) {
        struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&address;
        if (InetNtopA(AF_INET6, &v6->sin6_addr, ip, cap) == NULL) *error = WSAGetLastError();
        *port = ntohs(v6->sin6_port);
    }
}
BOOL pbdrv_get_original_dest(SOCKET accepted, PBDRV_REDIRECT_CTX *ctx)
{
    DWORD bytes = 0;
    int rc = WSAIoctl(accepted, SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT, NULL, 0,
                      ctx, sizeof(*ctx), &bytes, NULL, NULL);
    int wsa_after = WSAGetLastError();
    LARGE_INTEGER ticks, frequency;
    QueryPerformanceCounter(&ticks);
    QueryPerformanceFrequency(&frequency);
    BOOL complete = rc == 0 && bytes >= sizeof(*ctx);
    char local[INET6_ADDRSTRLEN], peer[INET6_ADDRSTRLEN];
    USHORT local_port, peer_port;
    int local_error, peer_error;
    pbdiag_endpoint(accepted, FALSE, local, sizeof(local), &local_port, &local_error);
    pbdiag_endpoint(accepted, TRUE, peer, sizeof(peer), &peer_port, &peer_error);
    log_message("[CTXDIAG] seq=%ld socket=%llu relay_pid=%lu thread=%lu qpc=%lld frequency=%lld "
                "api_return=%d api_error=%d wsa_after=%d bytes=%lu required=%lu complete=%d "
                "family=%u protocol=%u ctx_pid=%lu local_addr=%s local_port=%u local_error=%d "
                "peer_addr=%s peer_port=%u peer_error=%d",
                InterlockedIncrement(&pbdiag_query_seq), (unsigned long long)accepted,
                GetCurrentProcessId(), GetCurrentThreadId(), ticks.QuadPart, frequency.QuadPart,
                rc, rc == SOCKET_ERROR ? wsa_after : 0, wsa_after, bytes, (DWORD)sizeof(*ctx), complete,
                complete ? (unsigned)ctx->family : 0, complete ? (unsigned)ctx->protocol : 0,
                complete ? ctx->pid : 0, local, local_port, local_error, peer, peer_port, peer_error);
    WSASetLastError(wsa_after);
    return complete;
}
'''

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def prepare(root, output):
    root, output = root.resolve(), output.resolve()
    output.relative_to(root/'artifacts/diagnostics')
    if output.exists(): raise ValueError('DIAGNOSTIC_OUTPUT_MUST_BE_FRESH')
    archive = root/'artifacts/product-builds'/(COMMIT+'.zip')
    if digest(archive) != ARCHIVE: raise ValueError('PINNED_ARCHIVE_CHANGED')
    original = root/'artifacts/product-builds'/('ProxyBridge-'+COMMIT)
    base = root/'artifacts/product-builds/driver-63be0eb-testlab-cli'
    receipt = json.loads((base/'build-receipt.json').read_text(encoding='utf-8-sig'))
    for component in receipt['components']:
        if digest(base/component['name']) != component['sha256']: raise ValueError('BASE_KIT_CHANGED')
    sources = {}
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if info.is_dir(): continue
            rel = Path(*Path(info.filename).parts[1:])
            if '..' in rel.parts: raise ValueError('ARCHIVE_PATH_INVALID')
            data = z.read(info)
            if not (original/rel).is_file() or (original/rel).read_bytes() != data:
                raise ValueError('PINNED_SOURCE_CHANGED: '+str(rel))
            sources[rel.as_posix()] = data
    output.mkdir(parents=True)
    for rel, data in sources.items():
        dest = output/'source'/rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    rel = 'Windows/src/driver/ProxyBridgeDrv_user.c'
    text = sources[rel].decode().replace('\r\n','\n')
    start = text.index('BOOL pbdrv_get_original_dest(')
    end = text.index('\n}\n', start)+3
    text = text[:start]+PATCH+text[end:]
    (output/'source'/rel).write_text(text, encoding='utf-8')
    kit = output/'kit'; kit.mkdir()
    for name in ('ProxyBridge_CLI.exe', 'ProxyBridgeDrv.sys', 'LICENSE'):
        (kit/name).write_bytes((base/name).read_bytes())
    commands = json.loads((root/'artifacts/product-builds/driver-63be0eb/commands.json').read_text())
    args = [arg.replace(str(original),str(output/'source')) for arg in commands['core_args']]
    metadata = dict(schema_version=1, method='redirect-context-logging-v1', diagnostic_only=True,
        performance_comparable=False, status='SOURCES_PREPARED_BUILD_PENDING', source_commit=COMMIT,
        source_archive_sha256=ARCHIVE, original_sources=len(sources), patched_file=rel,
        base_kit=str(base), compiler=commands['compiler'], compiler_args=args,
        original_source_sha256={n:hashlib.sha256(b).hexdigest() for n,b in sources.items()},
        patched_source_sha256=digest(output/'source'/rel),
        base_files_sha256={str(p.relative_to(root)):digest(p) for p in base.iterdir() if p.is_file()},
        product_started=False, driver_changed=False, driver_installed=False, runtime_verified=False)
    (output/'preparation.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    return metadata

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    metadata=prepare(args.root,args.output)
    print(json.dumps(dict(status=metadata['status'],output=str(args.output))))
