"""Selected retry NBL snapshot candidate. No product execution in this module."""
import hashlib
import json
from pathlib import Path
from pb_endpoint_send_gate import create_action as source_create, read_action as source_read
from pb_endpoint_watch_candidate import CLEAR, quoted

PROFILE='scripts/debugger/pb-kd-selected-nbl-context-profile-20261020.json'
STAGE='scripts/debugger/pb-kd-selected-nbl-context-update-20261020.wdbg'
SCRIPT='scripts/debugger/pb_nbl_context.js'
SCRIPT_SHA='a596999c104cbb049dfa73fa7602dd047a30bd5b0248a05e23c5ad5a46576236'


def read_action():
    original=source_read()
    old='.if ((@$t7 & 0x200000) != 0) { '+CLEAR+' }'
    new=('.if ((@$t7 & 0x200000) != 0) { .if (@$t17 == 1) { r @$t19 = 1; '
         'dx @$scriptContents.pbNblArm(@rbp,@$t1,@$t2); }; }')
    if original.count(old)!=1:raise ValueError('NBL_SOURCE_ACTION_CHANGED')
    return ('r @$t19 = 0; '+original.replace(old,new).replace(
        '(@$t8 != 0) and (@$t4 >= 0x40)',
        '(@$t19 == 0) and (@$t8 != 0) and (@$t4 >= 0x40)'))


def create_action():
    original=source_create(True)
    old=quoted(source_read())
    if original.count(old)!=1:raise ValueError('NBL_SOURCE_CREATE_CHANGED')
    return original.replace(old,quoted(read_action()))


def profile():
    return dict(method='kd-selected-nbl-context-20261020-v1',
        registered_point_ids=[2,4],dynamic_point_ids=[3],active_point_ids=[],
        host_enable_point_ids=[2],automatic_enable_point_ids=[3],inactive_point_ids=[4],
        script=SCRIPT,script_sha256=SCRIPT_SHA,initialization='pbNblInitKernel',
        model_required=0,source_watch=dict(access='r',size=4,offset=0x30,limit=64),
        nbl_watch=dict(access='r',size=8,offset=0xe0,limit=16),
        max_total_raw_hits=96,list_node_limit=8,
        points=[dict(id=2,target='tcpip!AlepCreateRedirectRecord+0x396',action=create_action()),
                dict(id=3,target='dynamic-selected-source-then-selected-nbl',action=read_action())],
        automatic_disable=True,automatic_enable=True,
        recovery=['bd2','dx @$scriptContents.pbNblStop()',CLEAR,'bd4','g'],
        limits=['No global ACCEPT point; receive is selected by caller frames and tuple.',
                'No target writes or target function calls.',
                'Missing receive, changed identity, unreadable data or a limit means INCOMPLETE.',
                'No complete NBL lifetime, clone coverage or root cause verdict.'])


def write(root):
    root=Path(root)
    raw=(json.dumps(profile(),indent=2)+'\n').encode('utf-8')
    (root/PROFILE).write_bytes(raw)
    commands=['bd4','bc2','bp2 tcpip!AlepCreateRedirectRecord+0x396 '+quoted(create_action()),'bd2']
    if max(map(len,commands))>=4096:raise ValueError('NBL_COMMAND_TOO_LONG')
    (root/STAGE).write_bytes(('\n'.join(commands)+'\n').encode('ascii'))
    return hashlib.sha256(raw).hexdigest()
