"""Prepare a fresh files-only packet logger kit; reuse the isolated four-connection workload."""
import argparse
import contextlib
import io
import json
from pathlib import Path

from pb_prepare_kd_baseline import prepare as prepare_four, digest, plain

LOGGER_FILES = (
    'scripts/Invoke-KdPacketBaselineV2.ps1',
    'src/pb_prepare_kd_packet_baseline_v2.py',
    'scripts/debugger/pb-context-packet-stage-v2.wdbg',
    'scripts/debugger/pb-context-packet-stage-code-gate-v2.wdbg',
    'scripts/debugger/pb-context-packet-stage-body-v2.wdbg',
    'scripts/debugger/pb-context-packet-logger-plan-v2.json',
    'scripts/debugger/pb-context-packet-format-probe-v2.wdbg',
)


def prepare(root, output, python):
    root, output, python = plain(root), plain(output), plain(python)
    output.relative_to(root / 'artifacts/diagnostics')
    if output.exists():
        raise ValueError('KD_PACKET_PREPARATION_MUST_BE_FRESH')
    manifest_path = root / 'scripts/debugger/pb-context-packet-logger-plan-v2.json'
    manifest = json.loads(manifest_path.read_text())
    identity = manifest['identity_validation']
    if (len(manifest['points']) != 25 or [p['id'] for p in manifest['points']] != list(range(25))
            or not manifest['debugger_format_runtime_verified']
            or not identity['loaded_kernel_identity_verified'] or not identity['live_expression_verified']
            or not identity['manual_disabled_staging_allowed']
            or manifest['owned_baseline_coverage_verified'] or manifest['root_cause_proven']):
        raise ValueError('KD_PACKET_FORMAT_PRECONDITION_UNCONFIRMED')
    paths = [plain(root / p) for p in LOGGER_FILES]
    for path in paths:
        if not path.is_file():
            raise ValueError('KD_PACKET_LOGGER_FILE_MISSING: ' + str(path))
    # The original preparer rejects existing directories and copies only the same pinned binaries.
    # This fresh plan has never been inspected or used; no historical plan or capture is rewritten.
    with contextlib.redirect_stdout(io.StringIO()):
        prepare_four(root, output, python)
    plan_path = output / 'runtime-plan.json'
    plan = json.loads(plan_path.read_text())
    policy = dict(method='packet-stage-four-v2', point_ids=list(range(25)),
                  point_count=25, expected_manual_stage_state='disabled',
                  stage_entry='scripts/debugger/pb-context-packet-stage-v2.wdbg',
                  stage_sha256=digest(root / 'scripts/debugger/pb-context-packet-stage-v2.wdbg'),
                  manifest_sha256=digest(manifest_path),
                  format_probe_sha256=identity['physical_probe_sha256_user_confirmed'],
                  format_log_sha256=identity['format_log_sha256'],
                  user_stage_review_required=True, automatic_debugger_control=False,
                  owned_nonzero_pid_tid_verified=False, owned_packet_coverage_verified=False)
    receipt_path = output / 'kit/redirect-context-diagnostic.json'
    receipt = json.loads(receipt_path.read_text())
    receipt['packet_logger_policy'] = policy
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    plan['method'] = 'kd-packet-owned-four-v2'
    plan['packet_logger_policy'] = policy
    all_paths = {Path(f['path']) for f in plan['files']} | set(paths)
    plan['files'] = [dict(path=str(p), sha256=digest(p)) for p in sorted(all_paths)]
    plan_path.write_text(json.dumps(plan, indent=2) + '\n')
    print(json.dumps(dict(status='KD_PACKET_FILES_PREPARED', files=len(plan['files']),
                          preparation=str(output), connections=4, product_built=False,
                          driver_installed=False, traffic_generated=False,
                          debugger_points_registered=False, debugger_coverage_verified=False)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--python', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.root, args.output, args.python)
