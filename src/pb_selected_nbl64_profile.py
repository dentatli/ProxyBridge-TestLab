"""Separate immutable profile for the 64-read helper; registered actions stay identical."""
import hashlib
import json
from pathlib import Path
from pb_selected_nbl_profile import profile as base_profile,policy as base_policy,STAGE
from pb_nbl64_fixture import SCRIPT,SCRIPT_SHA

PROFILE='scripts/debugger/pb-kd-selected-nbl64-context-profile-20261020.json'
PROFILE_SHA='fdfebfccb1f24d0a7e79e2618010b1e1ca7628c33e7b44dda5c02db1ba4374c5'


def profile():
    p=base_profile()
    p.update(method='kd-selected-nbl64-context-20261020-v2',script=SCRIPT,script_sha256=SCRIPT_SHA,max_total_raw_hits=144,reject_sample_limit=4)
    p['nbl_watch']['limit']=64
    return p


def policy(target=True):
    p=base_policy(target)
    p.update(endpoint_nbl64_context=True,nbl_script_sha256=SCRIPT_SHA,nbl_watch_limit=64,
        max_total_raw_hits=144,raw_hit_limits_per_point={'2':16,'3':128},reject_sample_limit=4)
    return p


def registration(profile_path,receipt_path,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile_path,PROFILE_SHA));r=read(checked(receipt_path,receipt_sha))
    if (p!=profile() or r.get('method')!='target-flow-prepared-commands-v1' or
        r.get('source')!='prepared-command-awaiting-user-attestation' or r.get('profile_sha256')!=PROFILE_SHA or
        r.get('expected_disabled_ids')!=[2,4] or r.get('expected_absent_ids')!=[3] or
        r.get('host_registration_observed') is not False or r.get('script_sha256')!=SCRIPT_SHA or
        r.get('script_model')!=0 or boot_identity(r['boot'])!=boot_identity(boot)):
        raise ValueError('NBL64_REGISTRATION_DIFFERS')
    return p


def parser_proof(path):
    from pb_selected_nbl_profile import parser_proof as base
    from pb_nbl64_fixture import CASES
    return base(path,PROFILE_SHA,SCRIPT,SCRIPT_SHA,'selected-nbl64-js-cdb-proof-v1',CASES,64)


def write(root):
    raw=(json.dumps(profile(),indent=2)+'\n').encode('utf-8')
    (Path(root)/PROFILE).write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()
