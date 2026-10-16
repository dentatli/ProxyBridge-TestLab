"""Prepare a fresh four-connection kit for the reviewed seven-point logger, files only."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import shutil

from pb_prepare_kd_baseline import prepare as prepare_four, digest, plain

REVIEW_REL = 'artifacts/diagnostics/pb-kd-reconnect-review-20261016/minimal-registration-review/validation.json'
PROBE_REL = 'artifacts/diagnostics/pb-kd-reconnect-review-20261016/minimal-disabled-stage/probe-review.json'
CONSOLE_SHA = '0d025fe96d87a5726bba8ee25c479bab69b2c11fe4f6a5ad20b6b72b7936fe1d'
REGISTERED_STAGE_SHA = 'bfda5c41a138c0351110caeddd9256f0238d66b37b0bbd0a15031632bbd53413'
TARGETS = [
    'tcpip!AlepCreateRedirectRecord+0x396', 'tcpip!WfpAleAuthorizeAccept+0xcaf',
    'tcpip!WfpAleAuthorizeAccept+0xcbe', 'tcpip!WfpAleProcessSocketOption+0x2c4',
    'tcpip!WfpAleProcessSocketOption+0x47b', 'tcpip!AleRedirectRecordFree+0xd',
    'tcpip!AleRedirectRecordFree+0x76',
]
FILES = (
    'scripts/Invoke-KdMinimalBaseline.ps1', 'src/pb_prepare_kd_minimal_baseline.py',
    'scripts/debugger/pb-kd-minimal-stage-20261016.wdbg',
    'scripts/debugger/pb-kd-minimal-stage-profile-20261016.json',
    'scripts/debugger/pb-kd-minimal-format-probe-20261016.wdbg',
)


def prepare(root, output, python):
    root, output, python = plain(root), plain(output), plain(python)
    output.relative_to(root / 'artifacts/diagnostics')
    if output.exists():
        raise ValueError('KD_MINIMAL_PREPARATION_MUST_BE_FRESH')
    review_path, probe_path = plain(root / REVIEW_REL), plain(root / PROBE_REL)
    review = json.loads(review_path.read_text(encoding='utf-8-sig'))
    probe = json.loads(probe_path.read_text(encoding='utf-8-sig'))
    if (review['status'] != 'USER_SEVEN_DISABLED_POINTS_CONFIRMED_WITH_STAGE_COMMENT_ERROR_ACTIONS_PENDING'
            or review['source_sha256'] != CONSOLE_SHA or review['point_ids'] != list(range(7))
            or review['points_after'] != 7 or not review['all_points_disabled']
            or not review['addresses_and_bodies_exact'] or not review['bpcmds_exact']
            or not review['outer_g_separate'] or review['stage_clean']
            or len(review['stage_comment_errors']) != 1 or review['bp_registration_errors']
            or review['actual_point_actions_verified'] or review['gc_behavior_verified']
            or review['owned_packet_coverage_verified'] or review['core_query_binding_verified']
            or review['root_cause_proven']
            or digest(plain(Path(review['source']))) != CONSOLE_SHA
            or digest(plain(Path(review['registered_stage_snapshot']))) != REGISTERED_STAGE_SHA
            or digest(plain(Path(review['registered_profile_snapshot']))) != review['registered_profile_sha256']):
        raise ValueError('KD_MINIMAL_SAVED_REGISTRATION_UNCONFIRMED')
    if (probe['status'] != 'FORMAT_AND_RANGE_GUARD_PROBE_PASSED_NO_POINTS_OR_TRAFFIC'
            or not probe['commands_match_packaged_probe'] or probe['format_rows_exact'] != 7
            or probe['guard_rows'] != 7 or not probe['bl_empty_before_and_after']
            or not probe['outer_g_separate'] or probe['executed_error_markers']
            or digest(plain(Path(probe['source']))) != probe['source_sha256']):
        raise ValueError('KD_MINIMAL_SAVED_PROBE_UNCONFIRMED')
    profile = json.loads((root / FILES[3]).read_text(encoding='utf-8-sig'))
    registered = json.loads(Path(review['registered_profile_snapshot']).read_text(encoding='utf-8-sig'))
    if ([p['proposed_id'] for p in profile['points']] != list(range(7))
            or [p['target'] for p in profile['points']] != TARGETS
            or any(p['runtime_action_verified'] for p in profile['points'])
            or any(profile['points'][i]['registration_command'] != registered['points'][i]['registration_command'] for i in range(7))):
        raise ValueError('KD_MINIMAL_REGISTERED_ACTIONS_CHANGED')
    current_stage = (root / FILES[2]).read_text(encoding='ascii').splitlines()
    saved_stage = Path(review['registered_stage_snapshot']).read_text(encoding='ascii').splitlines()
    if ([s for s in current_stage if not s.startswith('$$')] != [s for s in saved_stage if not s.startswith('$$')]
            or any(';' in s for s in current_stage if s.startswith('$$'))
            or digest(root / FILES[2]) != profile['stage_sha256']):
        raise ValueError('KD_MINIMAL_STAGE_COMMENT_ONLY_CORRECTION_REQUIRED')
    paths = [plain(root / name) for name in FILES]
    if not all(p.is_file() for p in paths):
        raise ValueError('KD_MINIMAL_LOGGER_FILE_MISSING')
    # Reuse the bounded, original-queue, single-query workload and the same pinned three binaries.
    # prepare_four rejects existing directories and performs only file reads/copies/writes.
    with contextlib.redirect_stdout(io.StringIO()):
        prepare_four(root, output, python)
    evidence = output / 'debugger-evidence'
    evidence.mkdir()
    copies = {
        'registration-review.json': review_path, 'format-probe-review.json': probe_path,
        'registration-console.txt': plain(Path(review['source'])),
        'format-probe-console.txt': plain(Path(probe['source'])),
        'registered-stage.wdbg': plain(Path(review['registered_stage_snapshot'])),
        'registered-profile.json': plain(Path(review['registered_profile_snapshot'])),
    }
    for name, source in copies.items():
        destination = evidence / name
        shutil.copyfile(source, destination)
        if digest(source) != digest(destination):
            raise ValueError('KD_MINIMAL_EVIDENCE_COPY_DIFFERS')
    policy = dict(
        method='minimal-seven-stage-four-v1', point_count=7, point_ids=list(range(7)),
        expected_manual_stage_state='disabled', automatic_debugger_control=False,
        user_stage_review_required=True, saved_stage_registration_verified=True,
        saved_stage_clean=False, saved_stage_comment_error_count=1,
        saved_stage_log_sha256=CONSOLE_SHA, registered_stage_sha256=REGISTERED_STAGE_SHA,
        stage_review_sha256=digest(evidence / 'registration-review.json'),
        profile_entry=FILES[3], profile_sha256=digest(root / FILES[3]),
        source_stage_entry=FILES[2], source_stage_sha256=digest(root / FILES[2]),
        source_stage_change='comment-only-do-not-reload-current-session',
        format_probe_sha256=digest(root / FILES[4]),
        probe_review_sha256=digest(evidence / 'format-probe-review.json'),
        actual_point_actions_verified=False, gc_behavior_verified=False,
        owned_nonzero_pid_tid_verified=False, owned_packet_coverage_verified=False,
        core_query_binding_verified=False, root_cause_proven=False,
        host_capture_method='user-full-console-paste-no-logopen-required',
    )
    receipt_path = output / 'kit/redirect-context-diagnostic.json'
    receipt = json.loads(receipt_path.read_text())
    receipt['minimal_logger_policy'] = policy
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8', newline='\n')
    plan_path = output / 'runtime-plan.json'
    plan = json.loads(plan_path.read_text())
    plan['method'] = 'kd-minimal-owned-four-v1'
    plan['minimal_logger_policy'] = policy
    all_paths = {Path(entry['path']) for entry in plan['files']} | set(paths) | set(evidence.iterdir())
    plan['files'] = [dict(path=str(p), sha256=digest(p)) for p in sorted(all_paths)]
    plan_path.write_text(json.dumps(plan, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(dict(status='KD_MINIMAL_FILES_PREPARED', preparation=str(output),
                         files=len(plan['files']), connections=4, point_count=7,
                         product_built=False, driver_installed=False, traffic_generated=False,
                         debugger_control=False, runtime_ready=False)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--python', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.root, args.output, args.python)
