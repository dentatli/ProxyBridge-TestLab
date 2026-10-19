"""Correlate positive CREATE metadata inside one explicit debugger capture scope."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from pb_target_accept_report import evaluate as evaluate_native

FIELDS = 'thread source local_raw ep assigned record context size refs'.split()


def correlate(console, plan_sha, native):
    errors, events = [], []
    result = dict(status='INCOMPLETE', errors=errors, create_events=events,
                  unique_control_creation_observed=False, root_cause_proven=False,
                  trap_coverage_verified=False, private_lifetime_complete=False)
    if not re.fullmatch(r'[a-fA-F0-9]{64}', plan_sha):
        errors.append('PLAN_SHA_INVALID')
        return result
    begin = 'PBTR_RUN_BEGIN plan=' + plan_sha.lower()
    end = 'PBTR_RUN_END plan=' + plan_sha.lower()
    lines = console.splitlines()
    malformed_markers = [line for line in lines if line.strip().startswith('PBTR_RUN_') and
                         plan_sha.lower() in line.lower() and line.strip().lower() not in (begin.lower(), end.lower())]
    starts = [i for i, line in enumerate(lines) if line.strip().lower() == begin.lower()]
    ends = [i for i, line in enumerate(lines) if line.strip().lower() == end.lower()]
    if malformed_markers or len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        errors.append('EXACT_CAPTURE_SCOPE_REQUIRED')
        return result
    controls = [m for m in native.get('matches', []) if m.get('role') == 'control']
    if len(controls) != 1 or controls[0]['peer'] != '127.0.0.1:42201':
        errors.append('NATIVE_CONTROL_MATCH_NOT_UNIQUE')
        return result
    if native['errors'] or native['status'] == 'INCOMPLETE':
        errors.append('NATIVE_CAPTURE_INCOMPLETE')
    result['control'] = controls[0]
    result['target_trigger_observed'] = native.get('target_trigger_observed', False)
    result['control_original_api_failure'] = native.get('control_original_api_failure', False)
    for line in lines[starts[0]+1:ends[0]]:
        if re.search(r'(?i)(syntax error|memory access error|couldn.t resolve|unable to resolve|80000004)', line):
            errors.append('DEBUGGER_ERROR_INSIDE_SCOPE')
        if line.startswith(('PBTR_UNREADABLE', 'PBTR_UNEXPECTED')):
            errors.append('DEBUGGER_METADATA_INCOMPLETE')
        if not line.startswith('PBTR CREATE '):
            continue
        try:
            pairs = [token.split('=', 1) for token in line[len('PBTR CREATE '):].split()]
            if len(pairs) != len(FIELDS) or [p[0] for p in pairs] != FIELDS:
                raise ValueError('FIELDS_INVALID')
            row = {}
            for field, value in pairs:
                if not re.fullmatch(r'[a-fA-F0-9`]{1,17}', value):
                    raise ValueError('HEX_VALUE_INVALID')
                row[field] = int(value.replace('`', ''), 16)
                if row[field] > 0xffffffffffffffff:
                    raise ValueError('VALUE_TOO_LARGE')
            family = row['local_raw'] & 0xffff
            port_raw = (row['local_raw'] >> 16) & 0xffff
            row['source_port'] = int.from_bytes(port_raw.to_bytes(2, 'little'), 'big')
            row['source_address_raw'] = row['local_raw'] >> 32
            if family != 2 or row['source_port'] != 42201:
                raise ValueError('CONTROL_PORT_OR_FAMILY_DIFFERS')
            if (any(row[k] == 0 for k in ('thread', 'source', 'ep', 'record', 'context')) or
                    row['assigned'] != row['record'] or row['size'] != 32 or row['refs'] < 1):
                raise ValueError('CREATE_METADATA_INVALID')
            events.append(row)
        except (ValueError, IndexError, OverflowError) as exc:
            errors.append('CREATE_LINE_INVALID:' + str(exc))
    if errors:
        return result
    result['unique_control_creation_observed'] = len(events) == 1
    result['status'] = ('CONTROL_CREATE_OBSERVED' if len(events) == 1 else
                        'MULTIPLE_CONTROL_CREATES_REVIEW_PENDING' if events else
                        'NO_CREATE_EVENT_OBSERVED_COVERAGE_UNPROVEN')
    return result


def evaluate(capture, console_path):
    read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
    plan = read(capture / 'runtime-plan.json')
    run = read(capture / 'diagnostic-run.json')
    if (plan['policy'].get('observer') != 'etw+kd-target-create' or
            plan['policy']['debugger_points'] != [2] or run.get('debugger_observer') is not True):
        raise ValueError('TARGET_CREATE_OBSERVER_CONTRACT_REQUIRED')
    sha = hashlib.sha256((capture / 'runtime-plan.json').read_bytes()).hexdigest()
    if sha.lower() != run['plan_sha256'].lower():
        raise ValueError('CAPTURE_PLAN_SHA_DIFFERS')
    raw = console_path.read_bytes()
    result = correlate(raw.decode('utf-8-sig'), sha, evaluate_native(capture))
    result['plan_sha256'] = sha
    result['console_sha256'] = hashlib.sha256(raw).hexdigest()
    result['limitation'] = 'Positive CREATE snapshot only; no transfer/free history, timestamp alignment or missed-trap proof.'
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture-directory', type=Path, required=True)
    p.add_argument('--console', type=Path, required=True)
    p.add_argument('--output-directory', type=Path, required=True)
    args = p.parse_args()
    result = evaluate(args.capture_directory, args.console)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    with (args.output_directory / 'create-report.json').open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({k: result[k] for k in ('status', 'errors', 'unique_control_creation_observed')}))
    raise SystemExit(bool(result['errors']))
