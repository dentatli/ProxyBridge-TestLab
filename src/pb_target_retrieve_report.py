"""Decision report for user-associated control-port retrieve snapshots; no absence proof."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from pb_target_accept_report import evaluate as native_evaluate
from pb_target_accept_plan import retrieve_policy

RETRIEVE = 'hit ep nbl local_raw peer_raw status record'.split()
RECORD = 'hit record context size refs'.split()
DEBUGGER_ERROR = re.compile(r'(?i)(syntax error|extra character error|memory access error|couldn.t resolve|unable to resolve|80000004)')


def parse(line, prefix, fields):
    parts = [s.split('=', 1) for s in line[len(prefix):].split()]
    if [s[0] for s in parts] != fields:
        raise ValueError('FIELDS_INVALID')
    result = {}
    for key, value in parts:
        if not re.fullmatch(r'[0-9a-fA-F`]{1,17}', value):
            raise ValueError('HEX_INVALID')
        result[key] = int(value.replace('`', ''), 16)
        if result[key] > 0xffffffffffffffff:
            raise ValueError('HEX_TOO_LARGE')
    return result


def correlate(console, native):
    rows, metadata, errors = [], [], []
    result = dict(status='INCOMPLETE', errors=errors, retrieve_events=rows, record_snapshots=metadata,
        correlation_source='user-associated-latest-run-and-control-source-port',
        automatic_capture_scope_verified=False, trap_coverage_verified=False,
        root_cause_proven=False, private_lifetime_complete=False)
    controls = [m for m in native.get('matches', []) if m.get('role') == 'control']
    if native['errors'] or len(controls) != 1 or controls[0]['peer'] != '127.0.0.1:42201':
        errors.append('NATIVE_CONTROL_INCOMPLETE')
        return result
    result.update(control=controls[0], target_trigger_observed=native.get('target_trigger_observed', False),
                  control_original_api_failure=native.get('control_original_api_failure', False))
    for line in console.splitlines():
        if line.startswith('PBTA_UNREADABLE'):
            errors.append('DEBUGGER_METADATA_INCOMPLETE')
        if DEBUGGER_ERROR.search(line):
            errors.append('DEBUGGER_ERROR')
        try:
            if line.startswith('PBTA RETRIEVE '):
                row = parse(line, 'PBTA RETRIEVE ', RETRIEVE)
                if (not row['hit'] or not row['ep'] or not row['nbl'] or
                        row['local_raw'] != 0xda84 or row['peer_raw'] != 0xd9a4 or row['status'] > 0xffffffff):
                    raise ValueError('CONTROL_SELECTOR_INVALID')
                rows.append(row)
            elif line.startswith('PBTA RECORD '):
                metadata.append(parse(line, 'PBTA RECORD ', RECORD))
        except (ValueError, IndexError) as exc:
            errors.append('LINE_INVALID:' + str(exc))
    hits = [r['hit'] for r in rows]
    if hits != sorted(set(hits)) or len(rows) > 64:
        errors.append('HIT_SEQUENCE_INVALID')
    if len({r['hit'] for r in metadata}) != len(metadata):
        errors.append('DUPLICATE_RECORD_SNAPSHOT')
    for item in metadata:
        owner = [r for r in rows if r['hit'] == item['hit']]
        if (len(owner) != 1 or owner[0]['status'] != 0 or item['record'] != owner[0]['record'] or
                not item['context'] or item['size'] != 32 or item['refs'] < 1):
            errors.append('RECORD_METADATA_INCONSISTENT')
    if errors:
        return result
    statuses = [r['status'] for r in rows]
    if not rows:
        result['status'] = 'NO_RETRIEVE_EVENT_COVERAGE_UNPROVEN'
    elif any(r['status'] == 0 and r['record'] == 0 for r in rows):
        result['status'] = 'SUCCESS_WITH_NULL_RECORD_OBSERVED'
    elif statuses == [0, 0xc0000225] and hits == [1, 2]:
        result['status'] = 'RETRIEVE_SUCCESS_THEN_NOT_FOUND_OBSERVED'
    elif all(s == 0 for s in statuses):
        result['status'] = ('SUCCESS_SNAPSHOTS_OBSERVED_API_FAILED' if result['control_original_api_failure']
                            else 'RETRIEVE_SUCCESS_OBSERVED')
    elif all(s == 0xc0000225 for s in statuses):
        result['status'] = 'RETRIEVE_NOT_FOUND_OBSERVED'
    else:
        result['status'] = 'RETRIEVE_STATUS_SEQUENCE_REVIEW_REQUIRED'
    result['limitation'] = 'Positive status snapshots only; no complete hit coverage, payload validity or automatic SYN-to-event timestamp alignment.'
    return result


def evaluate(capture, console_path):
    read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
    plan, run = read(capture / 'runtime-plan.json'), read(capture / 'diagnostic-run.json')
    if plan['policy'] not in (retrieve_policy(), retrieve_policy(False)) or run.get('debugger_observer') is not True:
        raise ValueError('RETRIEVE_OBSERVER_CONTRACT_REQUIRED')
    sha = hashlib.sha256((capture / 'runtime-plan.json').read_bytes()).hexdigest()
    if sha != run['plan_sha256'].lower():
        raise ValueError('CAPTURE_PLAN_SHA_DIFFERS')
    raw = console_path.read_bytes()
    result = correlate(raw.decode('utf-8-sig'), native_evaluate(capture))
    result.update(plan_sha256=sha, console_sha256=hashlib.sha256(raw).hexdigest())
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture-directory', type=Path, required=True)
    p.add_argument('--console', type=Path, required=True)
    p.add_argument('--output-directory', type=Path, required=True)
    a = p.parse_args()
    result = evaluate(a.capture_directory, a.console)
    a.output_directory.mkdir(parents=True, exist_ok=True)
    with (a.output_directory / 'retrieve-report.json').open('x', encoding='utf-8') as f:
        json.dump(result, f, indent=2)
        f.write('\n')
    print(json.dumps(dict(status=result['status'], errors=result['errors'])))
    raise SystemExit(bool(result['errors']))
