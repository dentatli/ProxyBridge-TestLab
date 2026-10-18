"""Prepare/build inputs only: isolate a one-shot accept barrier, never run product."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

PARENT_CORE = '7dc8952e7562ac4dff3cf278136d1fe8fd44474885f707c93c220f94e9f624ed'
PARENT_RELAY = 'd5f632b510aa1f0a24e944b0808946b96c25f6db0a2b650fb7875aef35a400db'
CLI = 'ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca'
DRIVER = '3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e'
INCLUDE = '#include "pb_target_accept_gate.h"\n'
DECL = '    BOOL pbdiag_target_gate_used = FALSE;\n'
GATE = '''            if (!pbdiag_target_gate_used) {
                pbdiag_target_gate_used = TRUE;
                if (!pbdiag_target_accept_gate()) break;
            }
'''
ANCHOR = '            SOCKET client_sock = accept('


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def plain(path):
    path = Path(path).absolute()
    for p in (path, *path.parents):
        if p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()):
            raise ValueError('TARGET_REPARSE_PATH')
    return path


def patch(text):
    for anchor in ('DWORD WINAPI local_proxy_server(LPVOID arg)\n', '    WSADATA wsa_data;\n', ANCHOR):
        if text.count(anchor) != 1:
            raise ValueError('TARGET_SOURCE_ANCHOR_DIFFERS')
    if '[TARGETGATE]' in text or 'pbdiag_target_' in text:
        raise ValueError('TARGET_SOURCE_ALREADY_PATCHED')
    new = text.replace('DWORD WINAPI local_proxy_server(LPVOID arg)\n', INCLUDE+'\nDWORD WINAPI local_proxy_server(LPVOID arg)\n', 1)
    new = new.replace('    WSADATA wsa_data;\n', DECL+'    WSADATA wsa_data;\n', 1)
    new = new.replace(ANCHOR, GATE+ANCHOR, 1)
    inverse = new.replace(INCLUDE+'\n', '', 1).replace(DECL, '', 1).replace(GATE, '', 1)
    if inverse != text:
        raise ValueError('TARGET_INVERSE_DIFFERS')
    return new


def prepare(root, parent, assets_kit, output):
    root, parent, assets_kit, output = map(plain, (root, parent, assets_kit, output))
    if output.parent != root / 'artifacts/diagnostics' or output.exists():
        raise ValueError('TARGET_FRESH_DIAGNOSTIC_DIRECTORY_REQUIRED')
    relay = Path('Windows/src/relay/pb_relay_tcp.c')
    checks = [(parent/'kit/ProxyBridgeCore.dll', PARENT_CORE),
              (parent/'source'/relay, PARENT_RELAY),
              (assets_kit/'ProxyBridge_CLI.exe', CLI), (assets_kit/'ProxyBridgeDrv.sys', DRIVER)]
    for p, sha in checks:
        if digest(plain(p)) != sha:
            raise ValueError('TARGET_PINNED_PARENT_DIFFERS: '+str(p))
    entries = [plain(p) for p in (parent/'source').rglob('*')]
    sources = {p.relative_to(parent/'source').as_posix():digest(p) for p in entries if p.is_file()}
    parent_build = json.loads((parent/'preparation.json').read_text(encoding='utf-8-sig'))
    for relative, expected in parent_build['original_source_sha256'].items():
        if relative == parent_build['kernel_patched_file']:
            expected = parent_build['kernel_patched_source_sha256']
        expected = parent_build.get('timing_patched_files', {}).get(relative, expected)
        if sources.get(relative) != expected:
            raise ValueError('TARGET_PARENT_SOURCE_CHANGED: '+relative)
    old = (parent/'source'/relay).read_text(encoding='utf-8-sig')
    new = patch(old)
    output.mkdir()
    shutil.copytree(parent/'source', output/'source')
    for relative, sha in sources.items():
        if digest(output/'source'/relative) != sha:
            raise ValueError('TARGET_SOURCE_COPY_DIFFERS')
    (output/'source'/relay).write_text(new, encoding='utf-8', newline='\n')
    header = root/'src/diagnostics/pb_target_accept_gate.h'
    shutil.copy2(header, output/'source'/relay.parent/header.name)
    (output/'kit').mkdir()
    for name in ('ProxyBridge_CLI.exe','ProxyBridgeDrv.sys'):
        shutil.copy2(assets_kit/name, output/'kit'/name)
    receipt = dict(method='target-accept-barrier-v1',status='SOURCES_PREPARED_BUILD_PENDING',
        parent=str(parent),root=str(root),compiler=parent_build['compiler'],
        compiler_args=[a.replace(str(parent),str(output)) for a in parent_build['compiler_args']],
        source_before_sha256=sources,source_after_sha256={p.relative_to(output/'source').as_posix():digest(p)
            for p in (output/'source').rglob('*') if p.is_file()},
        inverse_patch_exact=True,original_single_query_preserved=True,driver_installation=False,
        product_started=False,traffic_generated=False,runtime_verified=False,
        reused_binary_sha256={'ProxyBridge_CLI.exe':CLI,'ProxyBridgeDrv.sys':DRIVER},
        policy=dict(listener_case='original',barrier='before_first_ipv4_accept',
            timeout_ms=30000,fill_connections=200,control_connections=1,control_port=57201,
            source_port_option='-LocalPort:57201',filler_ports_option='-LocalPort:[57001,57200]',
            workload_authorized=False,debugger_control=False,capacity_claim=False))
    with (output/'preparation.json').open('x',encoding='utf-8') as f:
        json.dump(receipt,f,indent=2)
    return receipt


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('root','parent','assets-kit','output'):
        ap.add_argument('--'+name,type=Path,required=True)
    a=ap.parse_args()
    receipt=prepare(a.root,a.parent,a.assets_kit,a.output)
    print(json.dumps(dict(output=str(a.output),status=receipt['status'],product_started=False,traffic_generated=False)))


if __name__ == '__main__':
    main()
