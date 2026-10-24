"""Own only the selected local PnP device's enable/disable lease, once per queue."""
from __future__ import annotations
import json
import subprocess
from pathlib import Path
from typing import Any
from trafficlab.schedule import atomic


def device(binding_path: str, binding: dict[str, Any], action: str) -> dict[str, Any]:
    if action not in ('Enable', 'Disable'):
        raise ValueError('TRAFFIC_PNP_ACTION_INVALID')
    if binding.get('product_contract') != 'driver' or binding.get('runtime_mode') != 'local':
        return {'applicable': False}
    script = Path(binding['root']) / 'scripts/Set-TrafficWfpDevice.ps1'
    result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', str(script), '-BindingPath', binding_path, '-Action', action], capture_output=True,
        timeout=35, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode or len(result.stdout) > 8192:
        atomic(str(Path(binding_path).parent / ('wfp-device-' + action.lower() + '-failure.json')),
               {'exit_code': result.returncode, 'stdout': result.stdout[:8192].decode('utf-8-sig', errors='replace'),
                'stderr': result.stderr[:8192].decode('utf-8-sig', errors='replace')})
        raise ValueError('TRAFFIC_PNP_' + action.upper() + '_FAILED')
    value = json.loads(result.stdout.decode('utf-8-sig'))
    if value.get('applicable') is not False and (value.get('verified') is not True or value.get('action') != action):
        raise ValueError('TRAFFIC_PNP_STATE_NOT_VERIFIED')
    return value
