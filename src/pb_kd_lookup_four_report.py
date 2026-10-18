"""Verify four native queries; leave the lookup miss kernel capture pending review."""
import argparse
import json

from pathlib import Path
from pb_prepare_kd_lookup_four import POLICY, METHOD
from pb_tcp_connections_report import read
from pb_tcp_redirect_context_report import evaluate as evaluate_native, parse_queries
from pb_tcp_kernel_timing_report import parse as parse_timing


def summarize_original_queries(queries, matched):
    """A user API failure is measurable here. Its kernel status requires another capture."""
    failed = [row for row in matched if row['native_result'] != 'Succeeded']
    identified = [row for row in failed if row['api_return'] == -1 and row['api_error'] == 10022]
    return dict(query_count=len(queries), original_query_10022_count=sum(
                    q['api_return'] == -1 and q['api_error'] == 10022 for q in queries),
                uniquely_correlated_original_query_10022_count=len(identified),
                correlated_failure_sequences=[row['seq'] for row in identified],
                correlated_native_failed=len(failed), ntstatus_observed=False,
                kernel_c0000225_proven=False, root_cause_proven=False)


def evaluate(path):
    result = evaluate_native(path, diagnostic_method='tcp-' + METHOD, report_method=METHOD,
                             distinguish_unidentified_connect_failures=True)
    result['source_sha256'].pop('kd-lookup-four-report.json', None)
    result['source_sha256'].pop('kd-lookup-four-summary.md', None)
    errors = result['errors']
    result.update(debugger_control=False, debugger_enabled_user_acknowledged_only=True,
                  original_failure_signature='NOT_ASSESSED', ntstatus_observed=False,
                  kernel_c0000225_proven=False, root_cause_proven=False)
    try:
        manifest = read(path / 'comparison-manifest.json')
        config = read(path / 'proxy/benchmark-config.json')
        mode = read(path / 'proxy/run-receipt.json')
        if manifest['control_policy'] != POLICY or config['control_policy'] != POLICY:
            raise ValueError('CONTROL_POLICY_DIFFERS')
        if ([phase['requested_connections'] for phase in mode['phases']] != POLICY['phase_connections']
                or any(phase['hold_seconds'] != 8 for phase in mode['phases'])
                or [phase['id'] for phase in mode['phases']] != ['baseline']):
            raise ValueError('CONTROL_PHASES_INCOMPLETE')
        if (config['workload_preset']['levels'] != []
                or config['workload_preset']['native_timeout_ms'] != 60000
                or config['diagnostic_connection_case'] != dict(id='connectex-32', connect_method='ConnectEx', pending_limit=32)):
            raise ValueError('CONTROL_WORKLOAD_DIFFERS')
        cli = read(path / 'proxy/cli-lifecycle.json')
        if '[ROUTECASE] case=original backlog=2147483647 delay_ms=0' not in cli['stdout']:
            raise ValueError('CONTROL_ORIGINAL_LISTENER_UNCONFIRMED')
        if '[CTXDIAG_EXTRA]' in cli['stdout'] or '[CTXPROBE]' in cli['stdout']:
            raise ValueError('CONTROL_ADDITIONAL_QUERY_NOT_ALLOWED')
        queries = parse_queries(cli['stdout'])
        timing = parse_timing(cli['stdout'])
        by_seq = {row['seq']: row for row in timing}
        if set(by_seq) != {row['seq'] for row in queries}:
            raise ValueError('CONTROL_TIMING_QUERY_SET_DIFFERS')
        for q in queries:
            t = by_seq[q['seq']]
            if (t['valid'] != 1 or t['exit_qpc'] != q['qpc']
                    or not 0 < t['accept_qpc'] <= t['entry_qpc'] <= t['exit_qpc']
                    or any(t[key] != q[key] for key in ('socket', 'relay_pid', 'thread', 'frequency', 'api_return', 'api_error', 'bytes'))):
                raise ValueError('CONTROL_TIMING_QUERY_IDENTITY_DIFFERS')
        matched = [row for phase in result['phases'] for row in phase['matched_queries']]
        result.update(summarize_original_queries(queries, matched))
        result['query_timing'] = timing
        result['original_failure_signature'] = (
            'CORE_QUERY_10022_WITH_NATIVE_FAILURE_REOBSERVED'
            if result['uniquely_correlated_original_query_10022_count'] else 'NOT_REOBSERVED_IN_THIS_CONTROL')
    except (OSError, KeyError, ValueError, TypeError) as exc:
        errors.append('INCOMPLETE_KD_LOOKUP_FOUR: ' + str(exc))
    if errors:
        result['status'] = 'KD_LOOKUP_FOUR_CAPTURE_INCOMPLETE'
        result['original_failure_signature'] = 'INCOMPLETE_EVIDENCE'
    else:
        result['status'] = 'KD_LOOKUP_FOUR_NATIVE_EVIDENCE_CONFIRMED_DEBUGGER_PENDING'
    result.update(debugger_coverage_verified=False, reduced_profile_run_verified=False,
                  active_point_ids=[2,3], registered_point_ids=[2,3], inactive_point_ids=[], load_authorized=False, lifecycle_coverage_verified=False, frame_reads_runtime_verified=False,
                  miss_actions_runtime_verified=False, successful_query_record_coverage=False)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    args = parser.parse_args()
    result = evaluate(args.evidence_directory)
    (args.evidence_directory / 'kd-lookup-four-report.json').write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    lines = ['# Контроль исходного запроса Core', '', result['status'], '',
             'Проба четырёх соединений с lookup miss точками; kernel console ещё не проверен. Не PASS продукта и не доказательство причины.',
             'NTSTATUS ядра здесь не измеряется.', '',
             '| Фаза | Запрошено | Успешно | Отказы |', '| --- | ---: | ---: | ---: |']
    lines += [f"| {p['id']} | {p['requested']} | {p['successful']} | {p['failed']} |" for p in result['phases']]
    lines += ['', result['original_failure_signature'], ''] + result['errors']
    (args.evidence_directory / 'kd-lookup-four-summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps(dict(status=result['status'], native_failed=result.get('native_failed'),
                          correlated_query_10022=result.get('uniquely_correlated_original_query_10022_count'),
                          ntstatus_observed=False, errors=result['errors'])))
    return bool(result['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
