"""Offline-only proposal: arm setter after selected CREATE; no kernel connection."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from pb_target_flag_candidate import candidate as previous_candidate, fixture


def candidate():
    p = previous_candidate()
    p.update(method='create-armed-flag-candidate-v1', load_allowed=False,
             status='PROPOSAL_REQUIRES_EXPLICIT_HOST_ENABLE_EXCEPTION',
             automatic_enable=True, proposed_initial_active_point_ids=[2, 4],
             proposed_active_point_ids=[2, 3, 4], registered_point_ids=[2, 3, 4],
             required_inactive_point_ids=[], automatic_enable_point_ids=[3])
    action = p['points'][0]['action']
    old = 'dwo(@rax+0x1f0); } .else'
    new = 'dwo(@rax+0x1f0); r @$t4 = 0; be3; } .else'
    if action.count(old) != 1:
        raise ValueError('CREATE_ACTION_CHANGED_REVIEW_REQUIRED')
    p['points'][0]['action'] = action.replace(old, new)
    p['limitations'] += [
        'Not accepted by the runtime launcher or any existing frozen plan.',
        'Host user must explicitly authorize be3 inside the selected CREATE action.',
        'Global receive hits after CREATE may still exhaust the unchanged cap.',
        'Parser/state proof does not establish kernel coverage, timing, or low cost.']
    return p


def check(output):
    output.mkdir(parents=True, exist_ok=False)
    p = candidate()
    (output/'candidate.json').write_text(json.dumps(p, indent=2)+'\n', encoding='utf-8', newline='\n')
    debugger = Path(r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe')
    symbols = output/'empty-symbols'
    symbols.mkdir()
    result = dict(kernel_connection=False, product_started=False, traffic_generated=False,
                  runtime_authorized=False, cases=[])
    for kind in ('selected', 'nonselected', 'unreadable', 'limit'):
        commands = ['bp2 @$ip+0x20 "gc"', 'bp3 @$ip+0x30 "gc"', 'bp4 @$ip+0x40 "gc"',
                    'bd3', 'r @$t1 = 0', 'r @$t2 = 0', 'r @$t4 = 0xf',
                    'r @$t3 = '+('0xf' if kind == 'limit' else '0'),
                    fixture(p['points'][0]['action'], kind),
                    '.printf "ARM_STATE_BEGIN\\n"', '.bpcmds',
                    '.printf "ARM_STATE_END\\n"',
                    '.printf "ARM_VALUES record=%I64x ep=%I64x raw=%I64x\\n", @$t1, @$t2, @$t4', 'q']
        path = output/(kind+'.wdbg')
        path.write_text('\n'.join(commands)+'\n', encoding='ascii', newline='\n')
        c = subprocess.run([str(debugger), '-sins', '-y', str(symbols), '-cf', str(path),
                            r'C:\Windows\System32\cmd.exe', '/d', '/c', 'exit', '0'],
                           capture_output=True, timeout=20, creationflags=0x08000000)
        (output/(kind+'.stdout.txt')).write_bytes(c.stdout)
        (output/(kind+'.stderr.txt')).write_bytes(c.stderr)
        text = (c.stdout+c.stderr).decode('utf-8', errors='replace')
        lines = [line.strip() for line in text.splitlines()]
        state = lines[lines.index('ARM_STATE_BEGIN')+1:lines.index('ARM_STATE_END')]
        disabled = {i: any(re.fullmatch(r'bd\s+'+str(i)+r';', line) for line in state) for i in (2, 3, 4)}
        expected = {2: True, 3: False, 4: False} if kind == 'selected' else (
            {2: False, 3: True, 4: False} if kind == 'nonselected' else {2: True, 3: True, 4: True})
        values = ('ARM_VALUES record=1000 ep=1000 raw=0' if kind == 'selected' else
                  'ARM_VALUES record=0 ep=0 raw=f') in lines
        passed = (c.returncode == 0 and disabled == expected and values and
                  not re.search(r'(?i)(syntax error|extra character error|couldn.t resolve)', text))
        result['cases'].append(dict(name=kind, passed=passed, disabled=disabled, values_verified=values))
    result['passed'] = all(case['passed'] for case in result['cases'])
    (output/'parser-check.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.output)
    print(json.dumps(result))
    raise SystemExit(not result['passed'])
