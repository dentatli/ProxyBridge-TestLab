"""Pinned five-point observer for the selected client send and NBL association."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PROFILE_NAME = 'pb-kd-target-retry-disabled-candidate-20261019.json'
STAGE_NAME = 'pb-kd-target-retry-disabled-20261019.wdbg'
IDS = [2, 3, 4, 5, 6]
PROFILE_SHA = '00c87b602b1a91c3b6ff42c600656aa57267882ae6aa8462cd0690e7d069f146'


def profile():
    track = '.if ($vvalid(@r14,0x10) == 1) { .if ((wo(@r14) == 2) and (wo(@r14+2) == 0xd9a4)) { .if (($vvalid(@rax+0x1e0,0x14) == 1) and (@rax != 0)) { .if (@$t1 == 0) { r @$t1 = @rax; r @$t2 = @rdi; .printf "PBRT TRACK thread=%p source_ep=%p record=%p context=%p size=%I64x refs=%x\\n", @$thread, @rdi, @rax, poi(@rax+0x1e0), poi(@rax+0x1e8), dwo(@rax+0x1f0); } .else { .printf "PBRT_DUPLICATE capture=incomplete\\n"; } } .else { .printf "PBRT_UNREADABLE event=TRACK capture=incomplete\\n"; } } } .else { .printf "PBRT_UNREADABLE event=CREATE_SELECTOR capture=incomplete\\n"; }; gc;'
    send = '.if ($vvalid(@rdi+0x74,4) == 1) { .if ((wo(@rdi+0x74) == 0xd9a4) and (wo(@rdi+0x76) == 0xda84)) { .if ($vvalid(@rdi+0x388,8) == 1) { .printf "PBRT SEND thread=%p scope=%p tcb=%p nbl=%p source_ep=%p local_raw=%x peer_raw=%x\\n", @$thread, @rsp, @rdi, @r13, poi(@rdi+0x388), wo(@rdi+0x74), wo(@rdi+0x76); } .else { .printf "PBRT_UNREADABLE event=SEND_ENDPOINT capture=incomplete\\n"; } } } .else { .printf "PBRT_UNREADABLE event=SEND_SELECTOR capture=incomplete\\n"; }; gc;'
    entry = '.if (@$t2 != 0) { .if (@rcx == @$t2) { .if (($vvalid(@rcx+0x30,8) == 1) and ($vvalid(@rcx+0x1c0,8) == 1)) { .printf "PBRT INSPECT thread=%p scope=%p source_ep=%p nbl=%p family=%x flags30=%x flags34=%x record=%p\\n", @$thread, @rsp, @rcx, @r8, @edx, dwo(@rcx+0x30), dwo(@rcx+0x34), poi(@rcx+0x1c0); } .else { .printf "PBRT_UNREADABLE event=INSPECT capture=incomplete\\n"; } } }; gc;'
    post = '.if (@$t2 != 0) { .if (@rbx == @$t2) { .printf "PBRT ASSOC_RETURN thread=%p scope=%p source_ep=%p nbl=%p result_raw=%I64x\\n", @$thread, @rsp, @rbx, @rbp, @rax; } }; gc;'
    accept = '.if ($vvalid(@rbp-0x7c,4) == 1) { .if ((wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)) { .if ($vvalid(@rbp-0x28,8) == 1) { .printf "PBRT RETRIEVE thread=%p scope=%p ep=%p nbl=%p local_raw=%x peer_raw=%x status=%x output_raw=%p\\n", @$thread, @rsp, @rdi, @rbx, wo(@rbp-0x7c), wo(@rbp-0x7a), @eax, poi(@rbp-0x28); } .else { .printf "PBRT_UNREADABLE event=RETRIEVE capture=incomplete\\n"; } } } .else { .printf "PBRT_UNREADABLE event=ACCEPT_SELECTOR capture=incomplete\\n"; }; gc;'
    targets = ['tcpip!AlepCreateRedirectRecord+0x396', 'tcpip!TcpTcbSend+0x812',
        'tcpip!WfpTlShimInspectFastLoopbackSendDatagram',
        'tcpip!WfpTlShimInspectFastLoopbackSendDatagram+0xa0', 'tcpip!WfpAleAuthorizeAccept+0xcaf']
    return dict(method='kd-target-retry-disabled-candidate-20261019-v1',
        status='DISABLED_REGISTRATION_ONLY_NO_RUNTIME_CLAIM', registered_point_ids=IDS,
        active_point_ids=[], proposed_active_point_ids=IDS, required_inactive_point_ids=[],
        control_source_port=42201, points=[dict(id=i,target=t,action=a) for i,t,a in zip(IDS,targets,[track,send,entry,post,accept])],
        automatic_debugger_control=False, load_allowed=False,
        limitations=['SEND selects the reserved port pair; INSPECT and ASSOC_RETURN select the CREATE endpoint.',
            'A changed or null endpoint is visible in SEND but may be absent from INSPECT.',
            'No complete trap coverage, packet lifetime, object reuse exclusion, or automatic retry clock alignment.',
            'Association result is raw; failed retrieval output is not a returned record.'])


def stage(p):
    lines = ['bd2', 'bd3', 'bd4', 'bc2', 'bc3', 'bc4']
    for item in p['points']:
        action = item['action'].replace('\\', '\\\\').replace('"', '\\"')
        lines += ['bp'+str(item['id'])+' '+item['target']+' "'+action+'"', 'bd'+str(item['id'])]
    return '\n'.join(lines+['r @$t1 = 0', 'r @$t2 = 0', '.printf "PBRT_DISABLED_READY\\n"'])+'\n'


def fixture(action, case):
    # Substitute only target reads/registers. Preserve actual control grammar,
    # expressions, format strings, and debugger register assignments.
    values = dict(readable=True, selected=True, tracked=False)
    values.update(case)
    action = re.sub(r'\$vvalid\([^()]+\)', '1' if values['readable'] else '0', action)
    action = re.sub(r'\bwo\(([^()]+)\)', lambda m: ('2' if m[1]=='@r14' else ('0xda84' if m[1] in ('@rdi+0x76','@rbp-0x7c') else '0xd9a4')) if values['selected'] else '0', action)
    action = re.sub(r'(?:poi|dwo)\([^()]+\)', '0x1000', action)
    # Retain pseudo registers; start them at values needed by each branch.
    action = re.sub(r'@(?:\$thread|r14|rdi|r13|rcx|r8|edx|rbx|rbp|rax|eax|rsp)\b', '0x1000', action)
    if any(t in action for t in ('$vvalid','poi(','dwo(','wo(')):
        raise ValueError('RETRY_FIXTURE_UNSAFE_TOKEN')
    return ('r @$t1 = '+('0x1000' if values['tracked'] else '0')+'; r @$t2 = 0x1000; '+action[:-3]+'.printf "PBRT_PARSER_END\\n";')


CASES = [('selected',dict(tracked=False), {2:'TRACK',3:'SEND',4:'INSPECT',5:'ASSOC_RETURN',6:'RETRIEVE'}),
    ('unreadable',dict(readable=False), {2:'UNREADABLE',3:'UNREADABLE',4:'UNREADABLE',5:'ASSOC_RETURN',6:'UNREADABLE'}),
    ('not-selected',dict(selected=False), {2:None,3:None,4:'INSPECT',5:'ASSOC_RETURN',6:None}),
    ('duplicate',dict(tracked=True), {2:'DUPLICATE',3:'SEND',4:'INSPECT',5:'ASSOC_RETURN',6:'RETRIEVE'})]


def parser_check(root, output, debugger):
    pth=root/'scripts/debugger'/PROFILE_NAME
    p=json.loads(pth.read_text()); sha=hashlib.sha256(pth.read_bytes()).hexdigest()
    output.mkdir(parents=True, exist_ok=False)
    symbols=output/'empty-symbols';symbols.mkdir()
    result=dict(method='cdb-safe-retry-command-fixture-v1', kernel_connection=False,
        product_started=False, traffic_generated=False, profile_sha256=sha, cases=[])
    for name,values,expected in CASES:
        commands=[]
        for point in p['points']:
            commands += ['.printf "PBRT_CASE_ID_'+str(point['id'])+'\\n"',fixture(point['action'],values)]
        path=output/(name+'.wdbg');path.write_text('\n'.join(commands+['q'])+'\n',encoding='ascii',newline='\n')
        c=subprocess.run([str(debugger),'-sins','-y',str(symbols),'-cf',str(path),r'C:\Windows\System32\cmd.exe','/d','/c','exit','0'],capture_output=True,timeout=20,creationflags=0x08000000)
        (output/(name+'.stdout.txt')).write_bytes(c.stdout);(output/(name+'.stderr.txt')).write_bytes(c.stderr)
        text=(c.stdout+c.stderr).decode('utf-8',errors='replace')
        lines=[l.strip() for l in text.splitlines()]; checks=[]
        for point in p['points']:
            marker='PBRT_CASE_ID_'+str(point['id']); start=lines.index(marker) if marker in lines else -1
            end=next((i for i in range(start+1,len(lines)) if lines[i]=='PBRT_PARSER_END'),-1)
            emitted=[l for l in lines[start+1:end] if l.startswith(('PBRT ','PBRT_UNREADABLE','PBRT_DUPLICATE'))] if start>=0 and end>start else []
            token=expected[point['id']]
            checks.append(start>=0 and end>start and (any(token in l for l in emitted) if token else not emitted))
        passed=c.returncode==0 and all(checks) and not re.search(r'(?i)(syntax error|extra character error|couldn.t resolve)',text)
        result['cases'].append(dict(name=name,exit_code=c.returncode,passed=passed,point_checks=checks))
    result['passed']=all(c['passed'] for c in result['cases'])
    (output/'parser-check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    return result


def validate_parser_proof(path):
    from pb_kd_session import inventory
    path=Path(path);r=json.loads(path.read_text(encoding='utf-8-sig'))
    if (r.get('method')!='cdb-safe-retry-command-fixture-v1' or r.get('passed') is not True or
        r.get('profile_sha256')!=PROFILE_SHA or any(r.get(k) is not False for k in
        ('kernel_connection','product_started','traffic_generated')) or
        [c.get('name') for c in r.get('cases',[])]!=[c[0] for c in CASES] or
        any(c.get('passed') is not True or c.get('exit_code')!=0 or
            c.get('point_checks')!=[True]*5 for c in r['cases'])):
        raise ValueError('TARGET_RETRY_PARSER_PROOF_INVALID')
    paths=[path]+[path.parent/(c['name']+suffix) for c in r['cases']
        for suffix in ('.wdbg','.stdout.txt','.stderr.txt')]
    return dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),files=inventory(paths))


if __name__=='__main__':
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('phase',choices=['generate','parser-check']);a.add_argument('--output',type=Path)
    opt=a.parse_args(); root=Path(__file__).resolve().parents[1]
    if opt.phase=='generate':
        p=profile(); target=root/'scripts/debugger'/PROFILE_NAME
        with target.open('x',encoding='utf-8',newline='\n') as f:f.write(json.dumps(p,indent=2)+'\n')
        with (target.parent/STAGE_NAME).open('x',encoding='ascii',newline='\n') as f:f.write(stage(p))
        print(hashlib.sha256(target.read_bytes()).hexdigest())
    else:
        r=parser_check(root,opt.output,Path(r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'))
        print(json.dumps(r));raise SystemExit(not r['passed'])
