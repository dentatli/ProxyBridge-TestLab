"""Exercise the real CDB command parser with safe substituted logger fixtures."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def fixture(action, readable):
    replacements = {
        '(@$t1 != 0)': '(1)', '(@ecx == 5)': '(1)',
        '($vvalid(@rsp+0x28,0x10) == 1)': '(1)',
        '((poi(@rsp+0x28) == @$t1) and (poi(@rsp+0x30) == 5))': '(1)',
        '($vvalid(@$t1+0x1e0,0x14) == 1)': '(1)' if readable else '(0)',
        'dwo(@$t1+0x1f0)': '3', 'poi(@$t1+0x1e0)': '0x1000',
        'poi(@$t1+0x1e8)': '0x20', '@$thread': '1', '@$t1': '0x1000',
    }
    for old, new in replacements.items():
        if old not in action:
            raise ValueError('FIXTURE_TOKEN_MISSING:' + old)
        action = action.replace(old, new)
    if any(t in action for t in ('$vvalid', 'poi(', 'dwo(', '@$t1', '@$thread')):
        raise ValueError('FIXTURE_UNSAFE_TOKEN')
    if not action.endswith('gc;'):
        raise ValueError('FIXTURE_GC_SUFFIX_REQUIRED')
    return action[:-3] + '.printf "PARSER_ACTION_END\\n";'


def run(root, output, debugger):
    output.mkdir(parents=True, exist_ok=False)
    symbols = output/'empty-symbols'
    symbols.mkdir()
    profiles = [root/'scripts/debugger'/('pb-kd-target-removal-disabled-candidate-20261019'+suffix+'.json')
                for suffix in ('', '-r2')]
    result = dict(method='cdb-safe-removal-command-fixture-v1', target='cmd.exe /d /c exit 0',
        kernel_connection=False, product_started=False, traffic_generated=False, cases=[])
    for index, readable in [(0, True), (1, True), (1, False)]:
        raw = profiles[index].read_bytes()
        action = json.loads(raw)['points'][1]['action']
        name = ('r1' if index == 0 else 'r2') + ('-readable' if readable else '-unreadable')
        command = fixture(action, readable)
        path = output/(name+'.wdbg')
        path.write_text(command+'\nq\n', encoding='ascii', newline='\n')
        completed = subprocess.run([str(debugger), '-sins', '-y', str(symbols), '-cf', str(path),
            r'C:\Windows\System32\cmd.exe', '/d', '/c', 'exit', '0'],
            capture_output=True, timeout=20, creationflags=0x08000000)
        (output/(name+'.stdout.txt')).write_bytes(completed.stdout)
        (output/(name+'.stderr.txt')).write_bytes(completed.stderr)
        text = (completed.stdout+completed.stderr).decode('utf-8', errors='replace')
        error = 'Extra character error' in text
        end = 'PARSER_ACTION_END' in text
        # CDB echoes command lines; require actual standalone marker output.
        lines = [l.strip() for l in text.splitlines()]
        end = 'PARSER_ACTION_END' in lines
        stack_begin = any(l.startswith('PBRM STACK_BEGIN thread=') for l in lines)
        stack_end = any(l.startswith('PBRM STACK_END thread=') for l in lines)
        passed = (error and not end) if index == 0 else (
            completed.returncode == 0 and not error and end and stack_begin and stack_end and
            'Syntax error' not in text)
        result['cases'].append(dict(name=name, exit_code=completed.returncode,
            profile_sha256=hashlib.sha256(raw).hexdigest(), expected_old_error=index == 0,
            old_error_reproduced=error, action_end=end, stack_begin=stack_begin,
            stack_end=stack_end, passed=passed))
    result['passed'] = all(c['passed'] for c in result['cases'])
    (output/'parser-check.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--debugger', type=Path, default=Path(r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'))
    a = p.parse_args()
    r = run(a.root, a.output, a.debugger)
    print(json.dumps(dict(passed=r['passed'], cases=r['cases'])))
    raise SystemExit(not r['passed'])
