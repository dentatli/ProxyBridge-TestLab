"""User-authorized512 selected-NBL accesses; caller verification precedes key/consume."""
import hashlib
import json
from pathlib import Path
from pb_selected_nbl_profile import profile as base_profile,policy as base_policy,STAGE
from pb_nbl512_fixture import SCRIPT,SCRIPT_SHA

PROFILE='scripts/debugger/pb-kd-selected-nbl512-context-profile-20261020.json'
PROFILE_SHA='12a6e813b3513d9e4d923c8952df0bc94433794550cb1031960c71fa234d9ece'


def profile():
    p=base_profile()
    p.update(method='kd-selected-nbl512-context-20261020-v3',script=SCRIPT,script_sha256=SCRIPT_SHA,
        max_total_raw_hits=592,reject_sample_limit=4,caller_before_key=True)
    p['nbl_watch']['limit']=512
    return p


def policy(target=True):
    p=base_policy(target)
    p.update(endpoint_nbl512_context=True,nbl_script_sha256=SCRIPT_SHA,nbl_watch_limit=512,
        max_total_raw_hits=592,raw_hit_limits_per_point={'2':16,'3':576},reject_sample_limit=4,caller_before_key=True)
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if (p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or
        r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('profile_sha256')!=PROFILE_SHA or
        r.get('expected_disabled_ids')!=[2,4] or r.get('expected_absent_ids')!=[3] or
        r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or
        r.get('script_model')!=0 or boot_identity(r['boot'])!=boot_identity(boot)):
        raise ValueError('NBL512_REGISTRATION_DIFFERS')
    return p


def parser_proof(path):
    from pb_selected_nbl_profile import parser_proof as base
    from pb_nbl512_fixture import CASES
    return base(path,PROFILE_SHA,SCRIPT,SCRIPT_SHA,'selected-nbl512-js-cdb-proof-v1',CASES,512)


def write(root):
    raw=(json.dumps(profile(),indent=2)+'\n').encode('utf-8')
    (Path(root)/PROFILE).write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()
