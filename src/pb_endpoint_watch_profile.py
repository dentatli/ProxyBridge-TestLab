"""Exact bindings for the selected endpoint data watch; no target execution."""
from pathlib import Path
import re
from pb_kd_session import read,checked,inventory,boot_identity
from pb_prepare_kd_baseline import plain,digest

PROFILE_SHA='3ec1f5f5fbc50c7265e10c14735879f3076237d8ed3d438f467e2dcec7629624'
PROFILE='scripts/debugger/pb-kd-selected-endpoint-watch-profile-20261020.json'
STAGE='scripts/debugger/pb-kd-selected-endpoint-watch-disabled-20261020.wdbg'


def policy(target=False):
    from pb_target_flag_binding import policy as flag_policy
    p=flag_policy(target,True,True,not target)
    p.update(endpoint_data_watch=True,dynamic_debugger_points=[3],initial_debugger_points=[2,4] if not target else [],
             watch_size=4,watch_access='w',watch_field='selected-source-endpoint+0x30',
             automatic_debugger_install_after_create=[3],
             automatic_enable_authorization='user-selected-endpoint-observation-20261020')
    del p['selected_snapshots_per_point']
    p['selected_snapshot_limits_per_point']={'2':1,'3':16,'4':1}
    if target:
        # The failing API query is recorded natively; a global ACCEPT trap is unnecessary.
        p.update(debugger_points=[2,3],host_enable_debugger_points=[2],inactive_debugger_points=[4],max_total_raw_hits=32)
        p['selected_snapshot_limits_per_point']['4']=0
    return p


def registration(profile,receipt,receipt_sha,boot):
    p=read(checked(profile,PROFILE_SHA));r=read(checked(receipt,receipt_sha))
    if (p['method']!='kd-selected-endpoint-write-watch-20261020-v1' or p['registered_point_ids']!=[2,4] or
        p['dynamic_point_ids']!=[3] or p['active_point_ids']!=[] or p['watch_size']!=4):
        raise ValueError('ENDPOINT_WATCH_PROFILE_INVALID')
    if (r['method']!='target-flow-prepared-commands-v1' or
        r['source']!='prepared-command-awaiting-user-attestation' or r['profile_sha256']!=PROFILE_SHA or
        r['expected_disabled_ids']!=[2,4] or r['expected_absent_ids']!=[3] or
        r['host_registration_observed'] is not False or boot_identity(r['boot'])!=boot_identity(boot)):
        raise ValueError('ENDPOINT_WATCH_REGISTRATION_DIFFERS')
    return p


def parser_proof(path):
    from pb_endpoint_watch_candidate import create_action,quoted
    path=plain(Path(path));r=read(path)
    if (r.get('method')!='endpoint-data-watch-proof-suite-v1' or r.get('profile_sha256')!=PROFILE_SHA or
        r.get('passed') is not True or any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        [c.get('case') for c in r.get('cases',[])]!=['transition','cap','identity'] or
        any(c.get('passed') is not True or c.get('exit_code')!=0 or
            c.get('guard_expressions_replaced_with_true') is not True or c.get('kernel_thread_replaced_with_tid') is not True or
            any(c.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) for c in r['cases'])):
        raise ValueError('ENDPOINT_WATCH_PROOF_INVALID')
    checked(path.parent/'candidate.json',PROFILE_SHA)
    files=[path,path.parent/'candidate.json']
    action=re.sub(r'\$vvalid\([^()]*\)','1',create_action()).replace('@$thread','@$tid')
    expected='sxe -c '+quoted(action)+' bpe'
    for c in r['cases']:
        child=path.parent/c['case']
        if expected not in (child/'proof.wdbg').read_text(encoding='ascii').splitlines():
            raise ValueError('ENDPOINT_WATCH_PROOF_ACTION_DIFFERS')
        if read(child/'proof.json')!=c:raise ValueError('ENDPOINT_WATCH_PROOF_CASE_DIFFERS')
        files += [child/n for n in ('proof.json','proof.wdbg','proof.stdout.txt','proof.stderr.txt','target.py')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))
