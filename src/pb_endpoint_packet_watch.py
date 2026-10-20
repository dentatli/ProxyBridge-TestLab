"""Read one TCP header at the selected endpoint's observed receive transition."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from pb_endpoint_watch_candidate import create_action as base_create,watch_action as base_watch,quoted,FIXTURE

PROFILE='scripts/debugger/pb-kd-selected-endpoint-packet-watch-profile-20261020.json'
STAGE='scripts/debugger/pb-kd-selected-endpoint-packet-watch-disabled-20261020.wdbg'
PROFILE_SHA='cd4eeec74667d42d0065027514375a702a41b8bcb89269df4272b8a07c98b378'


def packet_action():
    bad='.printf "PBW_UNREADABLE event=RECEIVE_HEADER capture=incomplete\\n";'
    return ('.if ((@rip == tcpip!WfpTlShimInspectRecvTcpDatagram+0x198) and (@rbx == @$t2)) { '
        '.if ($vvalid(@rsi,0x58) == 1) { r @$t9 = poi(@rsi+0x50); '
        '.if ($vvalid(@$t9,0x14) == 1) { '
        '.if ((wo(@$t9) == 0xda84) and (wo(@$t9+2) == 0xd9a4) and ((by(@$t9+0xc) & 0xf0) >= 0x50)) { '
        '.printf "PBW RECEIVE_HEADER ep=%p record=%p nbl=%p header=%p src_raw=%x dst_raw=%x flags=%x h0=%I64x h1=%I64x h2=%x\\n", '
        '@$t2, @$t1, poi(@rsi+8), @$t9, wo(@$t9), wo(@$t9+2), by(@$t9+0xd), poi(@$t9), poi(@$t9+8), dwo(@$t9+0x10); '
        '} .else { '+bad+' } } .else { '+bad+' } } .else { '+bad+' } } .else { '+bad+' }; ')


def watch_action():
    marker='.printf "PBW TRANSITION_BEGIN\\n";'
    return base_watch().replace(marker,packet_action()+marker)


def create_action():
    return base_create().replace(quoted(base_watch()),quoted(watch_action()))


def profile_sha():
    return PROFILE_SHA


def policy(target=True):
    from pb_endpoint_watch_profile import policy as base
    if not target:raise ValueError('PACKET_WATCH_TARGET_ONLY')
    return dict(base(True),endpoint_packet_header=True,packet_header_bytes=20,packet_header_count_max=1)


def fixture_action():
    action=re.sub(r'\$vvalid\([^()]*\)','1',create_action()).replace('@$thread','@$tid')
    return action.replace('@rip == tcpip!WfpTlShimInspectRecvTcpDatagram+0x198','1 == 1')


def check(output):
    output=Path(output);output.mkdir(parents=True,exist_ok=False)
    root=Path(__file__).resolve().parents[1];raw=(root/PROFILE).read_bytes();p=json.loads(raw)
    if hashlib.sha256(raw).hexdigest()!=PROFILE_SHA or p['points'][0]['action']!=create_action() or p['points'][1]['action']!=watch_action():
        raise ValueError('PACKET_PROFILE_ACTION_DIFFERS')
    (output/'candidate.json').write_bytes(raw)
    cases=[]
    for name,flags,ports in [('rst_ack',0x14,True),('syn_ack',0x12,True),('wrong_tuple',0x14,False)]:
        child=output/name;child.mkdir();source=FIXTURE
        source=source.replace("code=bytes.fromhex('57 41 56')", "code=bytes.fromhex('57 41 56 56 53')")
        source=source.replace("+bytes.fromhex('cc')", "+mov('48 be',base+0x1200)+mov('48 bb',ep)+bytes.fromhex('cc')")
        source=source.replace("ctypes.memmove(base,code,len(code))", "code=code.replace(bytes.fromhex('41 5e 5f c3'),bytes.fromhex('5b 5e 41 5e 5f c3'))\nctypes.c_uint64.from_address(base+0x1250).value=base+0x1300\nctypes.c_uint64.from_address(base+0x1208).value=other\nheader=struct.pack('!HHIIBBHHH',"+('34010' if ports else '34011')+",42201,123,456,0x50,"+str(flags)+",1024,0,0)\nctypes.memmove(base+0x1300,header,len(header))\nctypes.memmove(base,code,len(code))")
        compile(source,'packet-fixture','exec');(child/'target.py').write_text(source,encoding='ascii')
        commands=['bp2 @$ip+0x20 "gc"','bd2','bp4 @$ip+0x40 "gc"','bd4']
        commands+=['r @$t'+str(i)+' = 0' for i in range(1,10)]
        commands+=['sxe -c '+quoted(fixture_action())+' bpe','g','q']
        (child/'proof.wdbg').write_text('\n'.join(commands)+'\n',encoding='ascii')
        symbols=child/'empty-symbols';symbols.mkdir()
        c=subprocess.run([r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe','-sins','-y',str(symbols),'-cf',str(child/'proof.wdbg'),sys.executable,str(child/'target.py')],capture_output=True,timeout=30,creationflags=0x08000000)
        (child/'proof.stdout.txt').write_bytes(c.stdout);(child/'proof.stderr.txt').write_bytes(c.stderr)
        lines=(c.stdout+c.stderr).decode(errors='replace').splitlines();headers=[l for l in lines if l.startswith('PBW RECEIVE_HEADER ')]
        good=(len(headers)==1 and 'flags='+format(flags,'x')+' ' in headers[0]) if ports else (not headers and any(l.startswith('PBW_UNREADABLE event=RECEIVE_HEADER') for l in lines))
        passed=c.returncode==0 and good and sum(l.startswith('PBW WRITE ') for l in lines)==1 and any(l.startswith('PBW_FIXTURE_DONE') for l in lines) and not re.search(r'(?i)(syntax error|extra character error|couldn.t resolve|Traceback)','\n'.join(lines))
        cases.append(dict(case=name,passed=passed,exit_code=c.returncode,headers=headers))
    result=dict(method='endpoint-packet-watch-proof-v1',profile_sha256=profile_sha(),passed=all(c['passed'] for c in cases),cases=cases,kernel_connection=False,product_started=False,traffic_generated=False,guard_expressions_replaced_with_true=True,kernel_thread_replaced_with_tid=True,writer_symbol_guard_replaced_with_true=True)
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def registration(profile,receipt,receipt_sha,boot):
    from pb_kd_session import read,checked,boot_identity
    p=read(checked(profile,profile_sha()));r=read(checked(receipt,receipt_sha))
    if (p['method']!='kd-selected-endpoint-packet-watch-20261020-v1' or p['points'][0]['action']!=create_action() or p['points'][1]['action']!=watch_action() or
        r['method']!='target-flow-prepared-commands-v1' or r['source']!='prepared-command-awaiting-user-attestation' or
        r['profile_sha256']!=profile_sha() or r['expected_disabled_ids']!=[2,4] or r['expected_absent_ids']!=[3] or r['host_registration_observed'] is not False or boot_identity(r['boot'])!=boot_identity(boot)):
        raise ValueError('PACKET_WATCH_REGISTRATION_DIFFERS')
    return p


def parser_proof(path):
    from pb_kd_session import read,checked,inventory
    from pb_prepare_kd_baseline import plain,digest
    path=plain(Path(path));r=read(path)
    if (r.get('method')!='endpoint-packet-watch-proof-v1' or r.get('profile_sha256')!=profile_sha() or r.get('passed') is not True or
        any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        any(r.get(k) is not True for k in ('guard_expressions_replaced_with_true','kernel_thread_replaced_with_tid','writer_symbol_guard_replaced_with_true')) or
        [c.get('case') for c in r['cases']]!=['rst_ack','syn_ack','wrong_tuple'] or any(c.get('passed') is not True or c['exit_code']!=0 for c in r['cases'])):
        raise ValueError('PACKET_WATCH_PROOF_INVALID')
    checked(path.parent/'candidate.json',profile_sha());files=[path,path.parent/'candidate.json']
    for c in r['cases']:
        child=path.parent/c['case']
        if 'sxe -c '+quoted(fixture_action())+' bpe' not in (child/'proof.wdbg').read_text().splitlines():raise ValueError('PACKET_WATCH_PROOF_ACTION_DIFFERS')
        files += [child/n for n in ('proof.wdbg','proof.stdout.txt','proof.stderr.txt','target.py')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))
