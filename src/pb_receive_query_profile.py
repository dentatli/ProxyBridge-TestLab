"""Receive transition plus the rare redirect-query NULL branch, no ACCEPT trap."""
import hashlib,json
from pathlib import Path
from pb_receive_accept_profile import profile as base_profile,policy as base_policy,SCRIPT,SCRIPT_SHA,PINS as RECEIVE_PINS
PROFILE='scripts/debugger/pb-kd-receive-query-profile-20261021.json'
STAGE='scripts/debugger/pb-kd-receive-query-update-20261021.wdbg'
QUERY='tcpip!WfpAleProcessSocketOption'
PINS=RECEIVE_PINS+' and '+ ' and '.join('('+expr+' == '+value+')' for expr,value in ((f'poi({QUERY}+0x2c4)','0x48000001c0978b48'),(f'dwo({QUERY}+0x2cc)','0x0b75d285'),(f'dwo({QUERY}+0x2d0)','0x0225b841'),(f'wo({QUERY}+0x2d4)','0xc000')))
def query_action():
    return ('r @$t2 = @$t2 + 1; .if (@$t2 >= 0x10) { .printf "PBQ INCOMPLETE reason=NULL_RAW_LIMIT\\n"; !pbcabort; } .else { '
        '.if (@r15d == 0x980000dd) { .if ((@rdx == 0) and (@$t10 != 0) and ($vvalid(@$t10+0x1c0,8) == 1) and ($vvalid(@$t10+0x30,4) == 1)) { '
        '.if (poi(@$t10+0x1c0) == @$t11) { .if ($vvalid(@$t11+0x1e0,0x10) == 1) { '
        '.printf "PBQ NULL ep=%p record_reg=%p ioctl=%x pid=%x tid=%x source_ep=%p source_record=%p context=%p size=%I64x flags30=%x\\n", '
        '@rdi, @rdx, @r15d, @$tpid, @$tid, @$t10, @$t11, poi(@$t11+0x1e0), poi(@$t11+0x1e8), dwo(@$t10+0x30); '
        'dx @$scriptContents.pbcStop(); '
        '} .else { .printf "PBQ INCOMPLETE reason=SOURCE_UNREADABLE\\n"; !pbcabort; } '
        '} .else { .printf "PBQ INCOMPLETE reason=SOURCE_CHANGED\\n"; !pbcabort; } '
        '} .else { .printf "PBQ INCOMPLETE reason=NULL_OR_SOURCE_GUARD\\n"; !pbcabort; } } }; gc;')
def profile():
    p=base_profile();p.update(method='kd-receive-query-null-20261021-v1',registration='manual-receive-query-null-actions',raw_hit_limits_per_point={'2':32,'3':16,'4':16},max_total_raw_hits=64,query_code_pin=PINS)
    p['points'][2]=dict(id=4,target=QUERY+'+0x2d0',action=query_action())
    p['limits']=['No ACCEPT or SEND breakpoint. Point4 lies only on the query record-NULL path.','QUERY_NULL precedes status assignment; it is not a measured query-return NTSTATUS.','PID/TID and one unique original native query join are required; independent SOCKET/packet lifetime remains unverified.']
    return p
def encoded():return (json.dumps(profile(),indent=2)+'\n').encode()
PROFILE_SHA=hashlib.sha256(encoded()).hexdigest()
def policy(target=True):
    p=base_policy(target);p.pop('receive_accept_snapshot',None)
    p.update(receive_query_snapshot=True,query_code_pin=PINS,raw_hit_limits_per_point={'2':32,'3':16,'4':16},max_total_raw_hits=64,accepted_nbl_observed=False,query_return_ntstatus_observed=False)
    return p
def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('expected_disabled_ids')!=[2,3,4] or r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or boot_identity(r['boot'])!=boot_identity(boot):raise ValueError('RECEIVE_QUERY_REGISTRATION_INVALID')
    return p
def parser_proof(path):
    from pb_receive_query_fixture import CASES,FIXTURE
    from pb_kd_session import read,checked,inventory
    path=Path(path);r=read(path);root=Path(__file__).resolve().parents[1];checked(root/SCRIPT,SCRIPT_SHA)
    if r.get('method')!='receive-query-cdb-proof-v1' or r.get('profile_sha256')!=PROFILE_SHA or r.get('script_sha256')!=SCRIPT_SHA or r.get('passed') is not True or any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or [c['case'] for c in r['cases']]!=list(CASES) or any(not c['passed'] or c['exit_code'] for c in r['cases']):raise ValueError('RECEIVE_QUERY_PROOF_INVALID')
    if read(path.parent/'candidate.json')!=profile():raise ValueError('RECEIVE_QUERY_CANDIDATE_DIFFERS')
    files=[path,path.parent/'candidate.json',root/SCRIPT]
    for case in CASES:
        child=path.parent/case
        if (child/'target.py').read_text()!=FIXTURE.replace('CASE',repr(case)):raise ValueError('RECEIVE_QUERY_FIXTURE_DIFFERS')
        files += [child/n for n in ('target.py','commands.wdbg','setup.wdbg','stdout.txt','stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(files))
def write(root):
    root=Path(root);(root/PROFILE).write_bytes(encoded())
    text='.if ('+PINS+') { bp4 '+QUERY+'+0x2d0 '+json.dumps(query_action())+'; bd4; .printf "PBQ CONFIG query_null=%p query_limit=10 version=1\\n", '+QUERY+'+0x2d0; } .else { .printf "PBQ CODE_PIN_FAILED no_runtime\\n"; };\n'
    (root/STAGE).write_bytes(text.encode());return PROFILE_SHA
