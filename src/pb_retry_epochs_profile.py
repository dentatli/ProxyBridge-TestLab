"""A source watch plus a bounded replaceable per-SEND NBL watch."""
import hashlib
import json
from pathlib import Path
from pb_retry_epochs_fixture import SCRIPT,SCRIPT_SHA,CASES,FIXTURE

PROFILE='scripts/debugger/pb-kd-per-send-nbl-profile-20261021-v3.json'
STAGE='scripts/debugger/pb-kd-per-send-nbl-update-20261021-v3.wdbg'
PROFILE_SHA='2b96749edd71a04b7c2d638c611c720af592b39e29f0db55b8e36fe42ae4502e'
ACTION='!pbrcreate @r14, @rdi, @rax; gc;'


def profile():
    return dict(method='kd-per-send-nbl-20261021-v3',registered_point_ids=[2],dynamic_point_ids=[3,4],active_point_ids=[],
        host_enable_point_ids=[2],script=SCRIPT,script_sha256=SCRIPT_SHA,initialization='pbRetryInitKernel',model_required=0,
        raw_hit_limits_per_point={'2':16,'3':128,'4':512},max_total_raw_hits=656,max_send_observations=8,per_send_read_limit=64,
        pre_identity_context_snapshot=True,buffer_raw_offsets=[8,16,24,32,40],
        points=[dict(id=2,target='tcpip!AlepCreateRedirectRecord+0x396',action=ACTION)],
        automatic_disable=True,automatic_enable=True,recovery=['bd2','dx @$scriptContents.pbRetryStop()','g'],
        limits=['Epoch is one helper SEND observation, not a network retransmission number.',
                'Receive storage and packet identity remain mandatory; no global ACCEPT point.',
                'A replaced or expired epoch is a gap, not proof of context absence.',
                'Last observed SEND must have a verified receive snapshot; no kernel endpoint/socket join is claimed.',
                'Selected-flow snapshots precede packet guards and never prove physical-packet identity.'])


def policy(target=True):
    from pb_endpoint_send_gate import policy as base
    if not target:raise ValueError('PER_SEND_REQUIRES_TARGET')
    p=base(True,0)
    p.update(endpoint_retry_epochs=True,nbl_script_sha256=SCRIPT_SHA,nbl_model=0,debugger_points=[2,3,4],
        inactive_debugger_points=[],dynamic_debugger_points=[3,4],automatic_debugger_enable_after_create=[3],
        automatic_debugger_enable_after_send=[4],raw_hit_limits_per_point={'2':16,'3':128,'4':512},max_total_raw_hits=656,
        max_send_observations=8,per_send_read_limit=64,nbl_watch_size=8,list_node_limit=8,
        watch_field='selected-source-endpoint+0x30-and-replaceable-per-send-nbl+0xe0',
        selected_snapshot_limits_per_point={'2':1,'3':8,'4':16},packet_header_count_max=8,
        pre_identity_context_snapshot=True,buffer_snapshot_count_max=16,buffer_raw_offsets=[8,16,24,32,40])
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if (p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or
        r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('profile_sha256')!=PROFILE_SHA or
        r.get('expected_disabled_ids')!=[2] or r.get('expected_absent_ids')!=[3,4] or
        r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or
        boot_identity(r['boot'])!=boot_identity(boot)):raise ValueError('PER_SEND_REGISTRATION_DIFFERS')
    return p


def parser_proof(path):
    from pb_kd_session import read,checked,inventory
    from pb_prepare_kd_baseline import plain,digest
    path=plain(Path(path));r=read(path);root=Path(__file__).resolve().parents[1]
    checked(root/SCRIPT,SCRIPT_SHA)
    if (r.get('method')!='per-send-nbl-cdb-proof-v1' or r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or
        any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        r.get('real_memory_watch') is not True or [c['case'] for c in r['cases']]!=list(CASES) or
        any(c.get('passed') is not True or c.get('exit_code')!=0 for c in r['cases'])):raise ValueError('PER_SEND_PROOF_INVALID')
    files=[path,root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('PER_SEND_FIXTURE_DIFFERS')
        if not (child/'setup.wdbg').read_text().startswith('bp2 (@rsi+0x1800) "'+ACTION+'"\n'):raise ValueError('PER_SEND_ACTION_DIFFERS')
        files += [child/n for n in ('target.py','setup.wdbg','proof.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))


def write(root):
    root=Path(root);raw=(json.dumps(profile(),indent=2)+'\n').encode()
    (root/PROFILE).write_bytes(raw)
    (root/STAGE).write_bytes(('bc2\nbc4\nbp2 tcpip!AlepCreateRedirectRecord+0x396 "'+ACTION+'"\nbd2\n').encode('ascii'))
    return hashlib.sha256(raw).hexdigest()
