"""Pair positive callback snapshots for one tracked record; never claim full coverage."""
import re
from pb_target_retrieve_report import parse

TRACK = 'thread source ep record context size refs'.split()
ENTER = 'thread scope event nbl new_nbl layer record tag'.split()
EXIT = 'thread scope record tag status'.split()


def correlate(console):
    errors, tracks, pairs, pending = [], [], [], {}
    result = dict(status='INCOMPLETE', errors=errors, tracks=tracks, callbacks=pairs,
                  trap_coverage_verified=False, root_cause_proven=False,
                  record_lifetime_complete=False)
    for line in console.splitlines():
        if line.startswith(('PBTF_UNREADABLE', 'PBTF_DUPLICATE')):
            errors.append('DEBUGGER_CAPTURE_INCOMPLETE')
        if re.search(r'(?i)(syntax error|memory access error|unable to resolve|couldn.t resolve|80000004)', line):
            errors.append('DEBUGGER_ERROR')
        try:
            if line.startswith('PBTF TRACK '):
                item = parse(line, 'PBTF TRACK ', TRACK)
                tracks.append(item)
                if len(tracks) != 1 or not all(item[k] for k in TRACK) or item['size'] != 32:
                    raise ValueError('TRACK_INVALID_OR_REPEATED')
            elif line.startswith('PBTF ENTER '):
                item = parse(line, 'PBTF ENTER ', ENTER)
                key = item['thread'], item['scope']
                if (len(tracks) != 1 or item['record'] != tracks[0]['record'] or item['tag'] != 5 or
                        not all(item[k] for k in ('thread', 'scope', 'nbl')) or key in pending):
                    raise ValueError('ENTER_UNBOUND_OR_OVERLAPPING')
                pending[key] = item
            elif line.startswith('PBTF EXIT '):
                item = parse(line, 'PBTF EXIT ', EXIT)
                key = item['thread'], item['scope']
                if (key not in pending or item['record'] != pending[key]['record'] or
                        item['tag'] != 5 or item['status'] > 0xffffffff):
                    raise ValueError('EXIT_UNPAIRED')
                pairs.append(dict(enter=pending.pop(key), exit=item))
        except (ValueError, IndexError) as exc:
            errors.append(str(exc))
    if pending:
        errors.append('CALLBACK_EXIT_MISSING')
    if errors:
        return result
    if len(tracks) != 1:
        result['status'] = 'TRACK_NOT_OBSERVED_COVERAGE_UNPROVEN'
    elif not pairs:
        result['status'] = 'CALLBACK_NOT_OBSERVED_COVERAGE_UNPROVEN'
    elif any(p['exit']['status'] for p in pairs):
        result['status'] = 'CALLBACK_FAILURE_OBSERVED'
    else:
        result['status'] = 'CALLBACK_SUCCESS_SNAPSHOTS_OBSERVED'
    result['limitation'] = ('Callbacks paired by thread and entry-stack scope in console order. '
        'No automatic Run/SYN correlation, complete hit coverage, payload validity, or proof '
        'that CONTEXT_REMOVED freed the record. Nonzero return does not distinguish retrieve '
        'failure from association failure. No initial-association result is observed.')
    return result
