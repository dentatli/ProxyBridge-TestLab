"""Prepare a fresh kernel/Core observation copy; never install or start it."""
import argparse,json
from pathlib import Path
from pb_prepare_redirect_context_diagnostic import prepare,digest

METHOD='redirect-kernel-context-v4'

def patch_driver(text):
    text=text.replace('\r\n','\n')
    start=text.index('static void ClassifyCore(');end=text.index('\n// classifyFn v1:',start)
    original=text[start:end];value=original
    def sub(old,new):
        nonlocal value
        if value.count(old)!=1:raise ValueError('KERNEL_PATCH_ANCHOR: '+old)
        value=value.replace(old,new,1)
    sub('    UNREFERENCED_PARAMETER(layerData);', '    PBK_EVENT diag;\n    PbkStart(&diag, family, inFixed, inMeta, classifyOut, idxProto, idxAppId);\n    UNREFERENCED_PARAMETER(layerData);')
    # Every exit records a reason while preserving the upstream branch and release order.
    reasons=[('if (!(classifyOut->rights & FWPS_RIGHT_ACTION_WRITE)) return;',1),
      ('if (InterlockedCompareExchange(&gEnabled, 1, 1) == 0) return;',2),
      ('            return;',3),
      ('if (inFixed->incomingValue[idxProto].value.type != FWP_UINT8) return;',4),
      ('if (protocol != IPPROTO_TCP && protocol != IPPROTO_UDP) return;',5),
      ('if (protocol == IPPROTO_UDP && !cfg.redirectUdp)   return;',6),
      ('if (family   == AF_INET6    && !cfg.redirectIpv6)  return;',7),
      ('if (pid != 0 && pid == cfg.selfPid) return;',8),
      ('        return;                                       // not a ruled process -> direct, in kernel',9),
      ('if (!NT_SUCCESS(status)) return;',10),
      ('if (!NT_SUCCESS(status) || req == NULL) { FwpsReleaseClassifyHandle0(classifyHandle); return; }',11),
      ('if (lb) { FwpsReleaseClassifyHandle0(classifyHandle); return; }',12)]
    for old,reason in reasons:
        replacement=old.replace('return;',f'{{ diag.reason={reason}; PbkFinish(&diag, classifyOut); return; }}')
        sub(old,replacement)
    sub('        if (st == FWPS_CONNECTION_REDIRECTED_BY_SELF ||','        diag.redirect_state = (ULONG)st;\n        if (st == FWPS_CONNECTION_REDIRECTED_BY_SELF ||')
    sub('    if (!NT_SUCCESS(status)) { diag.reason=10;', '    diag.acquire_called=1; diag.acquire_status=(ULONG)status;\n    if (!NT_SUCCESS(status)) { diag.reason=10;')
    sub('    if (!NT_SUCCESS(status) || req == NULL)', '    diag.writable_called=1; diag.writable_status=(ULONG)status; diag.req_present=(req!=NULL);\n    if (!NT_SUCCESS(status) || req == NULL)')
    sub('    if (ctx != NULL) {','    diag.allocation_attempted=1; diag.allocation_present=(ctx!=NULL);\n    if (ctx != NULL) {')
    sub('    FwpsApplyModifiedLayerData0(classifyHandle, req, 0);', '''    // Snapshot while the caller still owns writable req/context; never dereference after Apply.
    diag.context_size=(ULONG)req->localRedirectContextSize; diag.target_pid=req->localRedirectTargetPID;
    diag.handle_present=(req->localRedirectHandle!=NULL);
    if (ctx) { diag.context_pid=ctx->pid; diag.context_family=ctx->family; diag.context_protocol=ctx->protocol; }
    if (family==AF_INET) {
        PSOCKADDR_IN before=(PSOCKADDR_IN)&req->localAddressAndPort;
        PSOCKADDR_IN after=(PSOCKADDR_IN)&req->remoteAddressAndPort;
        diag.local_v4=before->sin_addr.S_un.S_addr; diag.local_port=RtlUshortByteSwap(before->sin_port);
        if (ctx) {diag.remote_v4=ctx->origV4;diag.remote_port=ctx->origPort;}
        diag.new_v4=after->sin_addr.S_un.S_addr;diag.new_port=RtlUshortByteSwap(after->sin_port);
    }
    diag.apply_called=1;
    FwpsApplyModifiedLayerData0(classifyHandle, req, 0);
    diag.apply_returned=1;''')
    sub('    classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;', '    classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;\n    diag.reason=13; PbkFinish(&diag, classifyOut);')
    text=text[:start]+'#include "pb_kernel_diag_internal.h"\n\n'+value+text[end:]
    anchor='    case PBDRV_IOCTL_ENABLE:'
    if text.count(anchor)!=1:raise ValueError('KERNEL_IOCTL_ANCHOR')
    text=text.replace(anchor,'''    case PBK_IOCTL:
        status=PbkDrain(buf, sp->Parameters.DeviceIoControl.OutputBufferLength, &info);
        break;

'''+anchor,1)
    return text,original,value

def prepare_kernel(root,output):
    metadata=prepare(root,output)
    rel='Windows/driver/src/ProxyBridgeDrv.c';path=output/'source'/rel
    text,original,instrumented=patch_driver(path.read_text(encoding='utf-8'))
    path.write_text(text,encoding='utf-8')
    for name in ('pb_kernel_diag_shared.h','pb_kernel_diag_internal.h'):
        (path.parent/name).write_bytes((root/'src'/name).read_bytes())
    metadata.update(method=METHOD,kernel_patched_file=rel,kernel_patched_source_sha256=digest(path),
        added_sources={name:digest(path.parent/name) for name in ('pb_kernel_diag_shared.h','pb_kernel_diag_internal.h')},
        observation_policy=dict(ring_capacity=8192,maximum_drain_records=64,ipv4_tcp_native_image='ctsTraffic.exe',
         raw_kernel_pointers_recorded=False,payload_recorded=False,original_actions_preserved=True,apply_return_is_void=True,
         original_query_only=True,no_delayed_queries=True),user_authorized_kernel_candidate=True)
    verify=output/'verification';verify.mkdir()
    (verify/'classify-original.c').write_text(original,encoding='utf-8');(verify/'classify-instrumented.c').write_text(instrumented,encoding='utf-8')
    (output/'preparation.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    return metadata

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();r=prepare_kernel(a.root.resolve(),a.output.resolve());print(json.dumps(dict(status=r['status'],method=METHOD,output=str(a.output))))
