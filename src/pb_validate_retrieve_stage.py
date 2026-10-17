"""Check the four-line retrieve/query staging contract without executing WinDbg."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


class StageRejected(ValueError):
    pass


def check(stage: Path, profile: Path) -> dict:
    raw = stage.read_bytes()
    issues = []
    try:
        text = raw.decode('ascii')
    except UnicodeDecodeError:
        raise StageRejected('ASCII_WITHOUT_BOM_REQUIRED') from None
    lines = text.splitlines()
    if any(line.lstrip().startswith(('$$', '*', '.echo')) for line in lines):
        issues.append('COMMENTS_FORBIDDEN: put instructions in README, not in executable stage')
    if raw.count(b'\r\n') != 4 or b'\n' in raw.replace(b'\r\n', b'') or b'\r' in raw.replace(b'\r\n', b''):
        issues.append('FOUR_CRLF_COMMAND_LINES_REQUIRED')
    if b'\x00' in raw or len(lines) != 4 or not raw.endswith(b'\r\n'):
        issues.append('FOUR_NONEMPTY_LINES_WITH_FINAL_CRLF_REQUIRED')
    meta = json.loads(profile.read_text(encoding='utf-8-sig'))
    point = next((p for p in meta['points'] if p['id'] == 2), None)
    if point is None or point['target'] != 'tcpip!WfpAleAuthorizeAccept+0xcaf':
        issues.append('RETRIEVE_RETURN_POINT2_REQUIRED')
    else:
        action = point['action']
        quote = '"' + action.replace('\\', '\\\\').replace('"', '\\"') + '"'
        command = 'bp2 ' + point['target'] + ' ' + quote
        if point['registration_command'] != command or lines != [command, 'bd2', 'bl', '.bpcmds']:
            issues.append('ONLY_BP2_BD2_BL_BPCMDS_ALLOWED')
        if not action.endswith('; gc;'):
            issues.append('FINAL_GC_OUTSIDE_ACTION_GUARDS_REQUIRED')
        if '$vvalid(@rbp-0x28,8)' not in action or 'poi(@rbp-0x28)' not in action:
            issues.append('OUTPUT_SLOT_GUARD_REQUIRED')
        elif action.index('$vvalid(@rbp-0x28,8)') >= action.index('poi(@rbp-0x28)'):
            issues.append('OUTPUT_SLOT_GUARD_MUST_PRECEDE_READ')
    actual_sha = hashlib.sha256(raw).hexdigest()
    if actual_sha != meta['stage_sha256']:
        issues.append('PROFILE_STAGE_SHA_MISMATCH')
    if issues:
        raise StageRejected('; '.join(issues))
    return dict(status='KD_RETRIEVE_STAGE_BYTES_VALIDATED', stage_sha256=actual_sha,
                command_lines=4, comments=False, encoding='ASCII', line_endings='CRLF',
                windbg_parser_executed=False, runtime_verified=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--archive', type=Path, help='Create a fresh ZIP only after validation')
    parser.add_argument('--readme', type=Path, help='Separate instructions included with --archive')
    args = parser.parse_args()
    try:
        result = check(args.stage, args.profile)
        if bool(args.archive) != bool(args.readme):
            raise StageRejected('ARCHIVE_AND_README_REQUIRED_TOGETHER')
        if args.archive:
            inputs = [args.stage, args.profile, args.readme]
            if len({p.name for p in inputs}) != len(inputs):
                raise StageRejected('ARCHIVE_ENTRY_NAMES_MUST_BE_DISTINCT')
            contents = {p.name: p.read_bytes() for p in inputs}
            with zipfile.ZipFile(args.archive, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
                for name, content in contents.items():
                    archive.writestr(name, content)
            with zipfile.ZipFile(args.archive) as archive:
                if archive.testzip() is not None or any(
                    archive.read(name) != content for name, content in contents.items()
                ):
                    raise StageRejected('ARCHIVE_BYTE_VERIFICATION_FAILED')
            result['archive_sha256'] = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('Error: KD_RETRIEVE_STAGE_PREFLIGHT_REJECTED: ' + str(exc))
        return 2
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
