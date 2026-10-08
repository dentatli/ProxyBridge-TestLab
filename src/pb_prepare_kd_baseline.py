"""Copy a verified logging Core and stock driver into a fresh, files-only KD kit."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

PINNED = {
    'ProxyBridge_CLI.exe': 'ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca',
    'ProxyBridgeCore.dll': '7dc8952e7562ac4dff3cf278136d1fe8fd44474885f707c93c220f94e9f624ed',
    'ProxyBridgeDrv.sys': '3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e',
}
POLICY = dict(method='kd-owned-four-v1', connections=4, hold_seconds=8,
              load_levels=[], recovery=False, driver_installation=False,
              original_single_query=True, listener_case='original', diagnostic_only=True,
              debugger_coverage_verified=False, performance_comparable=False)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def plain(path):
    path=path.absolute()
    for item in (path, *path.parents):
        if item.exists() and item.is_symlink():
            raise ValueError('KD_BASELINE_REPARSE_PATH')
        if item.exists() and getattr(item.stat(), 'st_file_attributes', 0) & 0x400:
            raise ValueError('KD_BASELINE_REPARSE_PATH')
    return path

def prepare(root, output, python):
    root=plain(root);output=plain(output);python=plain(python)
    output.relative_to(root/'artifacts/diagnostics')
    if output.exists():
        raise ValueError('KD_BASELINE_PREPARATION_MUST_BE_FRESH')
    base=root/'artifacts/product-builds/driver-63be0eb-testlab-cli'
    logged=root/'artifacts/diagnostics/tcp-redirect-context-preparation-20261007-151313-480f38a3/kit'
    origins={name: plain((logged if name=='ProxyBridgeCore.dll' else base)/name) for name in PINNED}
    for name,path in origins.items():
        if digest(path)!=PINNED[name]:
            raise ValueError('KD_BASELINE_REUSED_BINARY_CHANGED: '+name)
    files=[root/p for p in (
        'scripts/Invoke-KdContextBaseline.ps1', 'scripts/Invoke-KdContextBaselineWorkload.ps1',
        'src/pb_prepare_kd_baseline.py', 'src/pb_kd_baseline_report.py',
        'src/pb_tcp_redirect_context_report.py', 'src/pb_tcp_connections_report.py',
        'src/pb_tcp_kernel_timing_report.py', 'src/pb_controlled_tcp_proxy.py',
        'src/pb_pc_sampler.py', 'src/pb_proactor_close_guard.py',
        'scripts/debugger/pb-context-lifecycle-candidate.wdbg',
        'scripts/debugger/pb-context-lifecycle-conditional-patch.wdbg',
        'bin/pb_console_host.exe', 'bin/pb_wfp_state.exe',
        'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe',
        'bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe',
        'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl',
        'bin/tools/windivert-2.2.2/windivertctl.exe', 'bin/tools/windivert-2.2.2/WinDivert.dll',
        'config/runtime.json', 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env')]
    files+=list((root/'modules').glob('*.psm1'))
    files += [python, python.parent/'Lib/asyncio/proactor_events.py', *origins.values()]
    for path in files:
        plain(path)
        if not path.is_file():
            raise ValueError('KD_BASELINE_REQUIRED_FILE_MISSING: '+str(path))
    kit=output/'kit';kit.mkdir(parents=True)
    for name,path in origins.items():
        shutil.copyfile(path,kit/name)
        if digest(kit/name)!=PINNED[name]:
            raise ValueError('KD_BASELINE_COPY_DIFFERS')
    receipt=dict(schema_version=1, method='redirect-kd-baseline-v5',
                 status='DIAGNOSTIC_BUILD_PREPARED', diagnostic_only=True, performance_comparable=False,
                 source_commit='63be0ebf9bec92bfba95ef3d6729c375aa9af84e', base_kit=str(base),
                 kd_baseline_policy=POLICY, reused_binary_sha256=PINNED,
                 components=[dict(name=name,sha256=sha) for name,sha in PINNED.items()],
                 reused_binary_paths={k:str(v) for k,v in origins.items()},
                 original_single_query_preserved=True, product_built=False, driver_installed=False)
    (kit/'redirect-context-diagnostic.json').write_text(json.dumps(receipt,indent=2)+'\n')
    values=dict(PB_PROXYBRIDGE_CLI_EXE=str(kit/'ProxyBridge_CLI.exe'), PB_PROXYBRIDGE_EXE='',
        PB_PROXYBRIDGE_SOURCE_COMMIT=receipt['source_commit'], PB_DRIVER_PATH=str(kit/'ProxyBridgeDrv.sys'),
        PB_PROXYBRIDGE_SERVICE='ProxyBridgeDrv', PB_EXPECTED_PROXYBRIDGE_CLI_SHA256=PINNED['ProxyBridge_CLI.exe'],
        PB_EXPECTED_PROXYBRIDGE_CORE_SHA256=PINNED['ProxyBridgeCore.dll'],
        PB_EXPECTED_DRIVER_SHA256=PINNED['ProxyBridgeDrv.sys'], PB_PROXYBRIDGE_CLI_VARIANT='testlab-unbuffered-v1',
        PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=receipt['method'])
    (kit/'product.env').write_text('\n'.join(k+'='+v for k,v in values.items())+'\n')
    files+=list(kit.iterdir())
    plan=dict(schema_version=1, method='kd-owned-four-v1', diagnostic_only=True, performance_comparable=False,
              root=str(root), preparation=str(output), python=str(python), kd_baseline_policy=POLICY,
              files=[dict(path=str(p), sha256=digest(p)) for p in sorted(set(files))])
    (output/'runtime-plan.json').write_text(json.dumps(plan,indent=2)+'\n')
    print(json.dumps(dict(status='KD_BASELINE_FILES_PREPARED',files=len(plan['files']),
                         preparation=str(output),driver_installed=False,traffic_generated=False)))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--python',type=Path,required=True)
    a=p.parse_args();prepare(a.root,a.output,a.python)
