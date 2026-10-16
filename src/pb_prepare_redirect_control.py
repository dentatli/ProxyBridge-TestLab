"""Prepare an isolated 968-connection diagnostic control, without running the product."""
import argparse
import json
from pathlib import Path
import re
import shutil

from pb_prepare_kd_baseline import PINNED, digest, plain

METHOD = 'redirect-context-control-v1'
POLICY = dict(method=METHOD, phase_connections=[4, 64, 256, 640, 4], total_connections=968,
              hold_seconds=8, load_levels=[64, 256, 640], final_four_same_session=True,
              connect_method='ConnectEx', pending_limit=32, original_single_query=True,
              listener_case='original', listener_delay_ms=0, debugger_points='disabled',
              cohort_budget_ms=180000, client_wait_limit_ms=60000,
              driver_installation=False, automatic_debugger_control=False,
              diagnostic_only=True, performance_comparable=False)
FILES = (
    'scripts/Invoke-RedirectContextControl.ps1', 'scripts/Invoke-RedirectContextControlWorkload.ps1',
    'modules/RedirectControlConnectionLoad.psm1', 'src/pb_prepare_redirect_control.py',
    'src/pb_tcp_redirect_control_report.py', 'src/pb_prepare_kd_baseline.py',
    'src/pb_tcp_redirect_context_report.py', 'src/pb_tcp_connections_report.py',
    'src/pb_tcp_kernel_timing_report.py', 'src/pb_controlled_tcp_proxy.py',
    'src/pb_pc_sampler.py', 'src/pb_proactor_close_guard.py',
    'bin/pb_console_host.exe', 'bin/pb_wfp_state.exe',
    'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe', 'bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe',
    'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl',
    'bin/tools/windivert-2.2.2/windivertctl.exe', 'bin/tools/windivert-2.2.2/WinDivert.dll',
    'config/runtime.json', 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env',
)


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8', newline='\n')


def runtime_files(directory):
    """Exclude reproducible caches; reject redirects, do not silently follow them."""
    result = {}
    for path in sorted(directory.rglob('*')):
        if '__pycache__' in path.parts or path.suffix.lower() == '.pyc':
            continue
        plain(path)
        if path.is_file():
            result[path.relative_to(directory).as_posix()] = digest(path)
    return result


def prepare(root, output, python):
    root, output, python = plain(root), plain(output), plain(python)
    if (output.parent != root / 'artifacts/diagnostics'
            or not re.fullmatch(r'pb-redirect-control-preparation-\d{8}-\d{6}-[a-f0-9]{8}', output.name)):
        raise ValueError('REDIRECT_CONTROL_DIRECTORY_INVALID')
    if output.exists():
        raise ValueError('REDIRECT_CONTROL_PREPARATION_MUST_BE_FRESH')
    source_runtime = python.parent
    if python.name.lower() != 'python.exe' or (source_runtime / 'python312._pth').exists():
        raise ValueError('REDIRECT_CONTROL_RUNTIME_SOURCE_UNEXPECTED')
    before = runtime_files(source_runtime)
    for name in ('python.exe', 'python312.dll', 'DLLs/_socket.pyd', 'Lib/asyncio/proactor_events.py'):
        if name not in before:
            raise ValueError('REDIRECT_CONTROL_RUNTIME_INCOMPLETE: ' + name)
    base = root / 'artifacts/product-builds/driver-63be0eb-testlab-cli'
    logged = root / 'artifacts/diagnostics/tcp-redirect-context-preparation-20261007-151313-480f38a3/kit'
    origins = {name: plain((logged if name == 'ProxyBridgeCore.dll' else base) / name) for name in PINNED}
    for name, path in origins.items():
        if digest(path) != PINNED[name]:
            raise ValueError('REDIRECT_CONTROL_PINNED_BINARY_CHANGED: ' + name)
    files = {plain(root / name) for name in FILES}
    files.update(plain(p) for p in (root / 'modules').glob('*.psm1'))
    files.update(plain(p) for p in (root / 'bin/tools/psutil-7.2.2/packages').rglob('*') if p.is_file())
    files.update(origins.values())
    windows = [Path(r'C:\Windows\System32\ntoskrnl.exe'), Path(r'C:\Windows\System32\drivers\tcpip.sys'),
               Path(r'C:\Windows\System32\drivers\fwpkclnt.sys')]
    files.update(plain(p) for p in windows)
    if not all(p.is_file() for p in files):
        raise ValueError('REDIRECT_CONTROL_REQUIRED_FILE_MISSING')
    # These are ordinary file copies. Never execute copied product binaries or touch SCM.
    snapshot = output / 'runtime/python'
    snapshot.mkdir(parents=True)
    for relative, expected in before.items():
        destination = snapshot / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_runtime / relative, destination)
        if digest(destination) != expected:
            raise ValueError('REDIRECT_CONTROL_RUNTIME_COPY_DIFFERS: ' + relative)
    if runtime_files(source_runtime) != before:
        raise ValueError('REDIRECT_CONTROL_RUNTIME_CHANGED_DURING_COPY')
    # Isolated Windows path configuration: no registry/user site/environment fallback.
    # The diagnostic source directory is explicitly included and frozen separately.
    pth = snapshot / 'python312._pth'
    pth.write_text('.\nDLLs\nLib\n' + str(root / 'src') + '\n', encoding='ascii', newline='\n')
    copied = runtime_files(snapshot)
    manifest = output / 'runtime/manifest.json'
    save(manifest, dict(schema_version=1, source=str(source_runtime), source_files=len(before),
                        source_exe_sha256=before['python.exe'], copied_files=len(copied),
                        excludes=['__pycache__', '*.pyc'], bytecode_writes_disabled_by_invocation=True,
                        isolated_pth=True, import_site=False, source_runtime_reused_at_run=False,
                        files=copied))
    kit = output / 'kit'
    kit.mkdir()
    for name, path in origins.items():
        shutil.copyfile(path, kit / name)
        if digest(kit / name) != PINNED[name]:
            raise ValueError('REDIRECT_CONTROL_PRODUCT_COPY_DIFFERS')
    receipt = dict(schema_version=1, method=METHOD, diagnostic_only=True, performance_comparable=False,
                   status='DIAGNOSTIC_BUILD_PREPARED', source_commit='63be0ebf9bec92bfba95ef3d6729c375aa9af84e',
                   base_kit=str(base), control_policy=POLICY,
                   components=[dict(name=name, sha256=value) for name, value in PINNED.items()],
                   reused_binary_sha256=PINNED, original_single_query_preserved=True,
                   product_built=False, driver_installed=False)
    save(kit / 'redirect-context-diagnostic.json', receipt)
    environment = dict(PB_PROXYBRIDGE_CLI_EXE=str(kit / 'ProxyBridge_CLI.exe'), PB_PROXYBRIDGE_EXE='',
                       PB_PROXYBRIDGE_SOURCE_COMMIT=receipt['source_commit'], PB_DRIVER_PATH=str(kit / 'ProxyBridgeDrv.sys'),
                       PB_PROXYBRIDGE_SERVICE='ProxyBridgeDrv', PB_PROXYBRIDGE_CLI_VARIANT='testlab-unbuffered-v1',
                       PB_EXPECTED_PROXYBRIDGE_CLI_SHA256=PINNED['ProxyBridge_CLI.exe'],
                       PB_EXPECTED_PROXYBRIDGE_CORE_SHA256=PINNED['ProxyBridgeCore.dll'],
                       PB_EXPECTED_DRIVER_SHA256=PINNED['ProxyBridgeDrv.sys'],
                       PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC=METHOD)
    (kit / 'product.env').write_text(''.join(f'{key}={value}\n' for key, value in environment.items()), encoding='utf-8', newline='\n')
    files.update(kit.iterdir())
    files.update(snapshot / relative for relative in copied)
    files.add(manifest)
    plan = dict(schema_version=1, method=METHOD, diagnostic_only=True, performance_comparable=False,
                root=str(root), preparation=str(output), python=str(snapshot / 'python.exe'),
                runtime_manifest_sha256=digest(manifest), control_policy=POLICY,
                windows_disk_images={str(path): digest(path) for path in windows}, loaded_image_identity_verified=False,
                files=[dict(path=str(path), sha256=digest(path)) for path in sorted(files)])
    save(output / 'runtime-plan.json', plan)
    print(json.dumps(dict(status='REDIRECT_CONTROL_FILES_PREPARED', preparation=str(output),
                          files=len(files), runtime_files=len(copied), total_connections=968,
                          product_started=False, traffic_generated=False, driver_installed=False,
                          debugger_control=False, runtime_ready=False)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--python', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.root, args.output, args.python)
