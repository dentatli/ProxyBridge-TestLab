"""Isolated real CPU read-watch proofs; never connect to the kernel or generate traffic."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from pb_endpoint_send_gate import create_action,accept_action,GATE,quoted,PROFILE

CASES=('healthy_tcp','retry_tcp','retry_ipv4','raw_limit','unmapped','split_header','wrong_tuple','identity_change')
ACCEPT256_CASES=CASES+('accept_200_fillers','accept_254_fillers','accept_255_limit')

FIXTURE=r'''import ctypes,struct,json
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.VirtualAlloc.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_ulong,ctypes.c_ulong]
k.VirtualAlloc.restype=ctypes.c_void_p
b=k.VirtualAlloc(None,0x10000,0x3000,0x40)
if not b:raise ctypes.WinError(ctypes.get_last_error())
ep=b+0x4000;rec=b+0x4800;selector=b+0x5000;frame=b+0x5800;accept_ep=b+0x6000
case=CASE
put64=lambda a,v:setattr(ctypes.c_uint64.from_address(a),'value',v)
put32=lambda a,v:setattr(ctypes.c_uint32.from_address(a),'value',v)
put16=lambda a,v:setattr(ctypes.c_uint16.from_address(a),'value',v)
put64(ep+0x1c0,rec);put32(ep+0x30,0x1101641)
put64(rec+0x1e0,b+0x4e00);put64(rec+0x1e8,32);put32(rec+0x1f0,1)
put32(selector,0xd9a40002);put16(frame-0x7c,0xda84);put16(frame-0x7a,0xd9a4)
put64(frame-0x28,rec if case=='healthy_tcp' else 0)
def packet(o):
 nbl=b+o;nb=nbl+0x100;mdl=nbl+0x200;data=nbl+0x300
 put64(nbl+8,nb);put64(nb+8,mdl);put32(nb+0x10,0)
 header=struct.pack('!HHIIBBHHH',42201 if case!='wrong_tuple' else 42202,34010,123,0,0x50,2,1024,0,0)
 if case=='retry_ipv4':header=bytes.fromhex('4500002800004000400600007f0000017f000001')+header
 put32(nb+0x18,len(header));put16(mdl+0xa,0 if case=='unmapped' else 1)
 put64(mdl+0x18,data);put32(mdl+0x28,8 if case=='split_header' else len(header))
 ctypes.memmove(data,header,len(header));return nbl
n1=packet(0x7000);n2=packet(0x8000)
mov=lambda op,v:bytes.fromhex(op)+struct.pack('<Q',v)
call=lambda a:mov('49 bb',a)+bytes.fromhex('41 ff d3')
# Gate exactly models mov eax,[rcx+30]; the data trap reports gate+3, before BT.
gate=bytes.fromhex('8b 41 30 0f ba e0 15 72 0e')
gate+=mov('49 bb',b+0x9000)+bytes.fromhex('41 ff 03 c3')
gate+=mov('49 bb',b+0x9004)+bytes.fromhex('41 ff 03 c3')
ctypes.memmove(b+0x1000,gate,len(gate));ctypes.memmove(b+0x2000,bytes.fromhex('90 c3'),2)
code=bytes.fromhex('53 55 56 57 41 56')
code+=mov('48 be',b)+mov('49 be',selector)+mov('48 bf',ep)+mov('48 b8',rec)+bytes.fromhex('cc 90 cc')
code+=mov('48 b9',ep)+mov('48 bb',ep)+mov('49 be',2)+mov('48 bd',n1)
# An unrelated object's read/write must not consume the selected watch budget.
code+=mov('49 ba',b+0xa000)+bytes.fromhex('41 8b 42 30 41 83 4a 30 01')
if case=='raw_limit':code+=bytes.fromhex('8b 41 30')*65
elif case=='identity_change':code+=bytes.fromhex('48 c7 81 c0 01 00 00 00 00 00 00')+call(b+0x1000)
else:
 code+=bytes.fromhex('8b 41 30')+call(b+0x1000)
 if case in ('retry_tcp','retry_ipv4'):
  code+=bytes.fromhex('81 49 30 00 00 20 00')+mov('48 bd',n2)+call(b+0x1000)
  code+=bytes.fromhex('8b 41 30') # ignored after first skip clears the watch
code+=mov('48 bd',frame)+mov('48 bf',accept_ep)+mov('48 bb',n1 if case=='healthy_tcp' else n2)
code+=bytes.fromhex('31 c0') if case=='healthy_tcp' else bytes.fromhex('b8 25 02 00 c0')
if case.startswith('accept_'):
 code+=bytes.fromhex('66 c7 45 86 a5 d9')
 code+=call(b+0x2000)*int(case.split('_')[1])
 code+=bytes.fromhex('66 c7 45 86 a4 d9 b8 25 02 00 c0')
code+=call(b+0x2000)+bytes.fromhex('41 5e 5f 5e 5d 5b c3')
ctypes.memmove(b,code,len(code));ctypes.WINFUNCTYPE(None)(b)()
print('PBSD_FIXTURE_DONE',json.dumps(dict(associate=ctypes.c_uint32.from_address(b+0x9000).value,skip=ctypes.c_uint32.from_address(b+0x9004).value)))
'''


def transform(action):
    return re.sub(r'\$vvalid\([^()]*\)','1',action).replace('@$thread','@$tid').replace(GATE,'@$t0')


def fixture_setup(accept_limit=64):
    # CDB truncates a command line at 4096 bytes. Install the independent handlers separately.
    return ['r @$t0 = @rsi+0x1003','bp4 (@rsi+0x2000) '+quoted(transform(accept_action(64 if accept_limit==0 else accept_limit))),
        'bd4','sxe -c '+quoted(transform(create_action(accept_limit==0)))+' bpe','g']


def check(output,accept_limit=64):
    from pb_endpoint_send_gate import profile,PROFILE_SHA,ACCEPT256_PROFILE,ACCEPT256_SHA,NATIVE_PROFILE,NATIVE_SHA
    sha=NATIVE_SHA if accept_limit==0 else ACCEPT256_SHA if accept_limit==256 else PROFILE_SHA
    output=Path(output);output.mkdir(parents=True,exist_ok=False)
    raw=(Path(__file__).resolve().parents[1]/(NATIVE_PROFILE if accept_limit==0 else ACCEPT256_PROFILE if accept_limit==256 else PROFILE)).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=sha or json.loads(raw)!=profile(accept_limit):raise ValueError('SEND_PROFILE_ACTION_DIFFERS')
    (output/'candidate.json').write_bytes(raw);cases=[]
    for case in (ACCEPT256_CASES if accept_limit==256 else CASES):
        child=output/case;child.mkdir();source=FIXTURE.replace('CASE',repr(case));compile(source,'send-fixture','exec')
        (child/'target.py').write_text(source,encoding='ascii')
        (child/'setup.wdbg').write_text('\n'.join(fixture_setup(accept_limit))+'\n',encoding='ascii')
        cmds=['bp2 @$ip+0x20 "gc"','bd2']+['r @$t'+str(i)+' = 0' for i in range(1,18)]+['sxe -c '+quoted('$$><'+str(child/'setup.wdbg'))+' bpe','g','q']
        (child/'proof.wdbg').write_text('\n'.join(cmds)+'\n',encoding='ascii');symbols=child/'empty-symbols';symbols.mkdir()
        c=subprocess.run([r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe','-sins','-y',str(symbols),'-cf',str(child/'proof.wdbg'),sys.executable,str(child/'target.py')],capture_output=True,timeout=30,creationflags=0x08000000)
        (child/'proof.stdout.txt').write_bytes(c.stdout);(child/'proof.stderr.txt').write_bytes(c.stderr)
        text=(c.stdout+c.stderr).decode(errors='replace');lines=text.splitlines();gates=[l for l in lines if l.startswith('PBSD SEND_GATE ')];headers=[l for l in lines if l.startswith('PBSD SEND_HEADER ')]
        accepts=[l for l in lines if l.startswith('PBSD ACCEPT ')];done=next((l for l in lines if l.startswith('PBSD_FIXTURE_DONE ')),None)
        stats=json.loads(done.split(' ',1)[1]) if done else None
        if case=='healthy_tcp':ok=len(gates)==len(headers)==1 and len(accepts)==(0 if accept_limit==0 else 1) and 'flags_reg=1101641 ' in gates[0] and stats==dict(associate=1,skip=0)
        elif case in ('retry_tcp','retry_ipv4'):ok=len(gates)==len(headers)==2 and len(accepts)==(0 if accept_limit==0 else 1) and 'raw=4 ' in gates[-1] and 'flags_reg=1301641 ' in gates[-1] and stats==dict(associate=1,skip=1)
        elif case=='raw_limit':ok=not gates and not accepts and any(l.startswith('PBSD_LIMIT point=3 stage=raw_reads') for l in lines)
        elif case=='identity_change':ok=not gates and not accepts and 'PBSD_IDENTITY_CHANGED capture=incomplete' in lines
        elif case in ('accept_200_fillers','accept_254_fillers'):ok=len(gates)==len(headers)==len(accepts)==1 and 'PBSD_LIMIT point=4 capture=incomplete' not in lines
        elif case=='accept_255_limit':ok=len(gates)==len(headers)==1 and not accepts and 'PBSD_LIMIT point=4 capture=incomplete' in lines
        else:ok=len(gates)==1 and not headers and not accepts and 'PBSD_UNREADABLE event=SEND_HEADER capture=incomplete' in lines
        passed=c.returncode==0 and bool(done) and ok and not re.search(r'(?i)(syntax error|extra character error|couldn.t resolve|Traceback|command too long)',text)
        cases.append(dict(case=case,passed=passed,exit_code=c.returncode,gates=gates,headers=headers,accepts=accepts,stats=stats))
        if not passed:break
    result=dict(method='endpoint-send-gate-proof-v1',profile_sha256=sha,passed=all(c['passed'] for c in cases),cases=cases,
        kernel_connection=False,product_started=False,traffic_generated=False,guard_expressions_replaced_with_true=True,
        kernel_thread_replaced_with_tid=True,gate_symbol_replaced_with_fixture_address=True)
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result


def parser_proof(path,accept_limit=64):
    from pb_kd_session import read,checked,inventory
    from pb_prepare_kd_baseline import plain,digest
    from pb_endpoint_send_gate import PROFILE_SHA,ACCEPT256_SHA,NATIVE_SHA
    sha=NATIVE_SHA if accept_limit==0 else ACCEPT256_SHA if accept_limit==256 else PROFILE_SHA
    path=plain(Path(path));r=read(path)
    if (r.get('method')!='endpoint-send-gate-proof-v1' or r.get('profile_sha256')!=sha or r.get('passed') is not True or
        any(r.get(k) is not False for k in ('kernel_connection','product_started','traffic_generated')) or
        any(r.get(k) is not True for k in ('guard_expressions_replaced_with_true','kernel_thread_replaced_with_tid','gate_symbol_replaced_with_fixture_address')) or
        [c.get('case') for c in r['cases']]!=list(ACCEPT256_CASES if accept_limit==256 else CASES) or any(c.get('passed') is not True or c['exit_code']!=0 for c in r['cases'])):raise ValueError('SEND_GATE_PROOF_INVALID')
    checked(path.parent/'candidate.json',sha);files=[path,path.parent/'candidate.json']
    for c in r['cases']:
        child=path.parent/c['case']
        if (child/'setup.wdbg').read_text().splitlines()!=fixture_setup(accept_limit):raise ValueError('SEND_GATE_PROOF_ACTION_DIFFERS')
        files += [child/n for n in ('setup.wdbg','proof.wdbg','proof.stdout.txt','proof.stderr.txt','target.py')]
    return dict(path=str(path),sha256=digest(path),files=inventory(files))
