"""Join user-associated single-record callback observations to a sealed native Run."""
import argparse
import hashlib
import json
from pathlib import Path
from pb_target_accept_plan import flow_policy
from pb_target_accept_report import evaluate as native_evaluate
from pb_target_flow_console import correlate


def evaluate(capture, console):
    read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
    plan, run = read(capture/'runtime-plan.json'), read(capture/'diagnostic-run.json')
    sha = hashlib.sha256((capture/'runtime-plan.json').read_bytes()).hexdigest()
    if (plan['policy'] != flow_policy() or run.get('debugger_observer') is not True or
            run.get('flow_registration_acknowledged') is not True or sha != run['plan_sha256'].lower()):
        raise ValueError('FLOW_CAPTURE_BINDING_INVALID')
    raw = console.read_bytes()
    result = correlate(raw.decode('utf-8-sig'))
    native = native_evaluate(capture)
    controls = [m for m in native['matches'] if m['role'] == 'control']
    result.update(plan_sha256=sha, console_sha256=hashlib.sha256(raw).hexdigest(),
                  correlation_source='user-associated-latest-run-and-control-port-selector',
                  automatic_capture_scope_verified=False, native_status=native['status'],
                  target_trigger_observed=native.get('target_trigger_observed', False),
                  control_original_api_failure=native.get('control_original_api_failure', False),
                  native_errors=native['errors'])
    if native['errors'] or len(controls) != 1 or controls[0]['peer'] != '127.0.0.1:42201':
        result['errors'].append('NATIVE_CONTROL_INCOMPLETE')
        result['status'] = 'INCOMPLETE'
    else:
        result['control'] = controls[0]
    result['clone_callbacks'] = sum(p['enter']['event'] in (1, 2, 3) for p in result['callbacks'])
    result['removed_callbacks'] = sum(p['enter']['event'] == 5 for p in result['callbacks'])
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture-directory', type=Path, required=True)
    p.add_argument('--console', type=Path, required=True)
    p.add_argument('--output-directory', type=Path, required=True)
    a = p.parse_args()
    r = evaluate(a.capture_directory, a.console)
    a.output_directory.mkdir(parents=True, exist_ok=True)
    with (a.output_directory/'flow-report.json').open('x', encoding='utf-8') as f:
        json.dump(r, f, indent=2)
        f.write('\n')
    print(json.dumps({k:r[k] for k in ('status', 'errors', 'native_status', 'clone_callbacks', 'removed_callbacks')}))
    raise SystemExit(bool(r['errors']))
