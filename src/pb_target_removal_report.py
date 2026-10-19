"""Read pre-callback refcounts and bounded stacks for the selected redirect record."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from pb_target_retrieve_report import parse
from pb_target_flow_console import TRACK
from pb_target_accept_plan import flow_policy
from pb_target_accept_report import evaluate as native_evaluate

REMOVE = 'thread scope nbl record refs context size'.split()
MARKER = 'thread scope record'.split()
FRAME = re.compile(r'^\s*(?:[0-9a-fA-F]{1,2}\s+)?[0-9a-fA-F`]{8,17}\s+[0-9a-fA-F`]{8,17}\s+')


def correlate(console):
    errors, tracks, removals = [], [], []
    current, in_stack = None, False
    result = dict(status='INCOMPLETE', errors=errors, tracks=tracks, removals=removals,
        trap_coverage_verified=False, root_cause_proven=False, record_lifetime_complete=False)
    for line in console.splitlines():
        if line.startswith(('PBTF_UNREADABLE', 'PBTF_DUPLICATE', 'PBRM_UNREADABLE')):
            errors.append('DEBUGGER_CAPTURE_INCOMPLETE')
        if line.startswith(('PBTF ENTER ', 'PBTF EXIT ')):
            errors.append('WRONG_CALLBACK_LOGGER')
        if re.search(r'(?i)(syntax error|memory access error|unable to resolve|couldn.t resolve|80000004)', line):
            errors.append('DEBUGGER_ERROR')
        try:
            if line.startswith('PBTF TRACK '):
                item = parse(line, 'PBTF TRACK ', TRACK)
                tracks.append(item)
                if len(tracks) != 1 or not all(item.values()) or item['size'] != 32:
                    raise ValueError('TRACK_INVALID_OR_REPEATED')
            elif line.startswith('PBRM REMOVE '):
                if current is not None:
                    raise ValueError('STACK_NOT_COMPLETED')
                item = parse(line, 'PBRM REMOVE ', REMOVE)
                if (len(tracks) != 1 or item['record'] != tracks[0]['record'] or
                        not all(item[k] for k in ('thread', 'scope', 'nbl')) or item['refs'] > 0xffffffff):
                    raise ValueError('REMOVAL_UNBOUND')
                current = dict(snapshot=item, stack_lines=[], frames=[])
            elif line.startswith(('PBRM STACK_BEGIN ', 'PBRM STACK_END ')):
                begin = line.startswith('PBRM STACK_BEGIN ')
                marker = parse(line, 'PBRM STACK_BEGIN ' if begin else 'PBRM STACK_END ', MARKER)
                if current is None or any(marker[k] != current['snapshot'][k] for k in MARKER):
                    raise ValueError('STACK_IDENTITY_DIFFERS')
                if begin:
                    if in_stack:
                        raise ValueError('STACK_BEGIN_REPEATED')
                    in_stack = True
                else:
                    if not in_stack or not current['frames']:
                        raise ValueError('STACK_EMPTY_OR_BEGIN_MISSING')
                    removals.append(current)
                    current, in_stack = None, False
            elif in_stack:
                if len(current['stack_lines']) >= 64:
                    raise ValueError('STACK_OUTPUT_UNBOUNDED')
                current['stack_lines'].append(line)
                if FRAME.match(line):
                    current['frames'].append(line)
                if re.search(r'(?i)(unwind.*(fail|unavail)|stack unwind information not available)', line):
                    errors.append('STACK_UNWIND_WARNING')
        except (ValueError, IndexError) as exc:
            errors.append(str(exc))
    if current is not None:
        errors.append('STACK_END_MISSING')
    if errors:
        return result
    if not tracks:
        result['status'] = 'TRACK_NOT_OBSERVED_COVERAGE_UNPROVEN'
    elif not removals:
        result['status'] = 'REMOVAL_NOT_OBSERVED_COVERAGE_UNPROVEN'
    else:
        result['status'] = 'REMOVAL_STACKS_AND_PRECALL_REFS_OBSERVED'
        result['precall_refs'] = [r['snapshot']['refs'] for r in removals]
    result['limitation'] = ('Pre-callback snapshots only; refcount may change before the decrement. '
        'No atomic last-reference/free proof, payload validity, exclusion of object reuse, '
        'complete callback coverage, or automatic stack-to-SYN time alignment.')
    return result


def evaluate(capture, console):
    read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
    plan, run = read(capture/'runtime-plan.json'), read(capture/'diagnostic-run.json')
    sha = hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    if (plan['policy'] != flow_policy(True) or run.get('debugger_observer') is not True or
            run.get('flow_registration_acknowledged') is not True or sha != run['plan_sha256'].lower()):
        raise ValueError('REMOVAL_CAPTURE_BINDING_INVALID')
    raw = console.read_bytes()
    result = correlate(raw.decode('utf-8-sig'))
    native = native_evaluate(capture)
    controls = [m for m in native['matches'] if m['role'] == 'control']
    result.update(plan_sha256=sha, console_sha256=hashlib.sha256(raw).hexdigest(),
        correlation_source='user-associated-latest-run-and-control-port-selector',
        automatic_capture_scope_verified=False, native_status=native['status'],
        native_errors=native['errors'], control_original_api_failure=native.get('control_original_api_failure', False))
    if native['errors'] or len(controls) != 1 or controls[0]['peer'] != '127.0.0.1:42201':
        result['errors'].append('NATIVE_CONTROL_INCOMPLETE')
        result['status'] = 'INCOMPLETE'
    else:
        result['control'] = controls[0]
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture-directory', type=Path, required=True)
    p.add_argument('--console', type=Path, required=True)
    p.add_argument('--output-directory', type=Path, required=True)
    a = p.parse_args()
    r = evaluate(a.capture_directory, a.console)
    a.output_directory.mkdir(parents=True, exist_ok=True)
    with (a.output_directory/'removal-report.json').open('x', encoding='utf-8') as f:
        json.dump(r, f, indent=2)
        f.write('\n')
    print(json.dumps({k:r[k] for k in ('status', 'errors', 'native_status')}))
    raise SystemExit(bool(r['errors']))
