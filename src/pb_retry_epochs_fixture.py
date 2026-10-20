"""Nine real CDB scenarios for per-SEND watch switching and cleanup. No traffic."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from pb_endpoint_watch_candidate import quoted

SCRIPT='scripts/debugger/pb_retry_epochs_v3.js'
SCRIPT_SHA='6171487904ad9a317487531bd98a184f4f3e37cdf156d7ae78e7e6ce92ff2cd6'
CASES=('normal','replaced','reused_storage','budget','stopped','non_syn','selector_mismatch','cursor_advanced','header_changed')
FIXTURE=r'''import ctypes,struct,json
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.VirtualAlloc.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_ulong,ctypes.c_ulong]
k.VirtualAlloc.restype=ctypes.c_void_p
b=k.VirtualAlloc(None,0x40000,0x3000,0x40)
if not b:raise ctypes.WinError(ctypes.get_last_error())
case=CASE
q=lambda a,v:setattr(ctypes.c_uint64.from_address(a),'value',v)
d=lambda a,v:setattr(ctypes.c_uint32.from_address(a),'value',v)
w=lambda a,v:setattr(ctypes.c_uint16.from_address(a),'value',v)
ep=b+0x8000;rec=b+0x8800;frame=b+0xa000;accepted=b+0xb000;selector=b+0xc000
q(ep+0x1c0,rec);d(ep+0x30,0x1101641);q(rec+0x1e0,b+0x8e00);q(rec+0x1e8,32)
d(selector,0xd9a40002);w(frame-0x7c,0xda84);w(frame-0x7a,0xd9a4)
packets=[]
for i in range(8):
 n=b+0x10000+i*0x1000;nb=n+0x100;mdl=n+0x200;data=n+0x300;info=n+0x600;node=n+0x700
 q(n+8,nb);q(nb+8,mdl);d(nb+0x10,0);d(nb+0x18,20);q(nb+0x20,mdl);d(nb+0x28,0)
 w(mdl+0xa,1);q(mdl+0x18,data);d(mdl+0x28,20)
 ctypes.memmove(data,struct.pack('!HHIIBBHHH',42201,34010,123,0,0x50,2,1024,0,0),20)
 d(info,0x6e706657);q(info+0x10,node);q(node+8,rec);q(node+0x10,5);q(node+0x80,node+0x80)
 q(n+0xe0,info+1 if i==0 else 1);packets.append(n)
mov=lambda op,v:bytes.fromhex(op)+struct.pack('<Q',v)
call=lambda a:mov('49 bb',a)+bytes.fromhex('41 ff d3')
ctypes.memmove(b+0x1000,bytes.fromhex('8b 41 30 0f ba e0 15 c3'),8)
ctypes.memmove(b+0x1800,bytes.fromhex('90 c3'),2)
ctypes.memmove(b+0x5000,bytes.fromhex('90 c3'),2)
netio=bytes.fromhex('40 53 48 83 ec 30 48 8b 99 e0 00 00 00 48 83 e3 fc 48 8b c3 48 83 c4 30 5b c3')
ctypes.memmove(b+0x2000,netio,len(netio))
wrapper=bytes.fromhex('53 55 56 48 83 ec 50 48 89 7c 24 78 be 05 00 00 00 bd 01 00 00 00')+call(b+0x2000)
ret=b+0x3000+len(wrapper)
wrapper+=bytes.fromhex('48 83 c4 50 5e 5d 5b c3');ctypes.memmove(b+0x3000,wrapper,len(wrapper))
accept=bytes.fromhex('48 83 ec 28')+call(b+0x3000);accept_ret=b+0x4000+len(accept)
accept+=bytes.fromhex('48 83 c4 28 c3');ctypes.memmove(b+0x4000,accept,len(accept))
q(b+0x30000,ret);q(b+0x30008,accept_ret)
code=bytes.fromhex('53 55 56 57 41 56 48 83 ec 60')
code+=mov('48 be',b)+mov('48 bf',ep)+mov('48 b8',rec)+mov('49 be',selector)+bytes.fromhex('cc')+call(b+0x1800)
def send(n):return mov('48 b9',ep)+mov('48 bb',ep)+mov('48 bd',n)+mov('49 be',2)+call(b+0x1000)
def recv(n):return mov('48 b9',n)+mov('48 bf',accepted)+mov('48 bd',frame)+call(b+0x4000)
if case=='budget':
 for n in packets:code+=send(n)+mov('48 b9',n)+bytes.fromhex('41 ba 40 00 00 00 48 8b 81 e0 00 00 00 41 ff ca 75 f4')
elif case=='stopped':code+=send(packets[0])
else:
 code+=send(packets[0])
 if case in ('normal','non_syn'):code+=recv(packets[0])
 if case=='non_syn':
  code+=mov('49 ba',packets[2]+0x300+13)+bytes.fromhex('41 c6 02 10')+send(packets[2])
 if case=='selector_mismatch':
  code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a5 d9')+recv(packets[0])
  code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a4 d9')
 if case=='cursor_advanced':
  code+=mov('49 ba',packets[0]+0x100+8)+bytes.fromhex('49 c7 02 00 00 00 00')
  code+=mov('49 ba',packets[0]+0x100+0x18)+bytes.fromhex('41 c7 02 00 00 00 00')
  code+=mov('49 ba',packets[0]+0x100+0x28)+bytes.fromhex('41 c7 02 14 00 00 00')+recv(packets[0])
 if case=='header_changed':
  code+=mov('49 ba',packets[0]+0x300+4)+bytes.fromhex('41 c7 02 ef be ad de')+recv(packets[0])
 if case=='reused_storage':
  code+=mov('49 ba',packets[0]+8)+mov('48 b8',packets[2]+0x100)+bytes.fromhex('49 89 02')+recv(packets[0])
 code+=mov('48 b9',ep)+bytes.fromhex('81 49 30 00 00 20 00')+send(packets[1])
 if case=='replaced':code+=recv(packets[0])
 code+=recv(packets[1])
code+=call(b+0x5000)+mov('48 b9',ep)+bytes.fromhex('8b 41 30')
code+=mov('48 b9',packets[0])+bytes.fromhex('48 8b 99 e0 00 00 00')
code+=bytes.fromhex('48 83 c4 60 41 5e 5f 5e 5d 5b c3')
assert len(code)<0x1000
ctypes.memmove(b,code,len(code));ctypes.WINFUNCTYPE(None)(b)()
print('PBR_FIXTURE_DONE',json.dumps({'case':case}))
'''


def check(output):
    root=Path(__file__).resolve().parents[1];script=root/SCRIPT
    if hashlib.sha256(script.read_bytes()).hexdigest()!=SCRIPT_SHA:raise ValueError('RETRY_SCRIPT_CHANGED')
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=False)
    sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');cases=[]
    for case in CASES:
        child=output/case;child.mkdir();(child/'symbols').mkdir()
        (child/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['bp2 (@rsi+0x1800) "!pbrcreate @r14, @rdi, @rax; gc;"','bd2',
            'bp5 (@rsi+0x5000) "dx @$scriptContents.pbRetryStop(); .printf \\"PBR_FIXTURE_CLEAN source=%x packet=%x\\\\n\\", @$t8,@$t9; gc;"',
            'r @$t8 = 0','r @$t9 = 0',
            'dx @$scriptContents.pbRetryInitModel(@rsi+0x200d, *(unsigned __int64*)(@rsi+0x30000), *(unsigned __int64*)(@rsi+0x30008), 0xbad0, @rsi+0x1003)',
            'be2','g']
        (child/'setup.wdbg').write_text('\n'.join(setup)+'\n',encoding='ascii')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(script),'sxe -c '+quoted('$$><'+str(child/'setup.wdbg'))+' bpe','g','q']
        (child/'proof.wdbg').write_text('\n'.join(commands)+'\n',encoding='ascii')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(child/'symbols'),'-cf',str(child/'proof.wdbg'),sys.executable,str(child/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (child/'stdout.txt').write_bytes(r.stdout);(child/'stderr.txt').write_bytes(r.stderr)
        text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBR ')]
        recv=[l for l in lines if l.startswith('PBR RECEIVE ')];sends=[l for l in lines if l.startswith('PBR SEND ')]
        final=[l for l in lines if l.startswith('PBR FINAL ')];bad=[l for l in lines if l.startswith('PBR INCOMPLETE ')]
        ok=len(final)==1 and 'PBR_FIXTURE_CLEAN source=0 packet=0' in text
        if case in ('normal','non_syn'):ok=ok and len(recv)==2 and len(sends)==2 and not bad
        elif case=='selector_mismatch':ok=ok and len(recv)==1 and 'epoch=2 ' in recv[0] and any('peer_raw=d9a5' in l for l in lines) and any('reason=OTHER_TUPLE ' in l for l in lines) and not bad
        elif case=='replaced':ok=ok and len(recv)==1 and 'epoch=2 ' in recv[0] and any('reason=REPLACED ' in l for l in lines) and not bad
        elif case=='reused_storage':ok=ok and len(recv)==1 and 'epoch=2 ' in recv[0] and any('reason=PACKET_STORAGE_CHANGED ' in l for l in lines) and not bad
        elif case=='cursor_advanced':ok=ok and len(recv)==1 and 'epoch=2 ' in recv[0] and any('reason=PACKET_STORAGE_CHANGED ' in l for l in lines) and any('BUFFER stage=selected epoch=1 ' in l and 'current_mdl=0 ' in l and 'length=0 ' in l and 'nb28_raw=14 ' in l and 'header_match=1' in l for l in lines) and any('STATE stage=selected epoch=1 ' in l and 'key5=present' in l for l in lines) and not bad
        elif case=='header_changed':ok=ok and len(recv)==1 and 'epoch=2 ' in recv[0] and any('reason=PACKET_IDENTITY_CHANGED ' in l for l in lines) and any('BUFFER stage=selected epoch=1 ' in l and 'header_match=0' in l for l in lines) and not bad
        elif case=='budget':ok=ok and len(sends)==8 and not recv and any('reason=TOTAL_LIMIT' in l for l in bad) and ' reads=200 ' in final[0]
        else:ok=ok and not recv and any('reason=STOPPED ' in l for l in lines) and not bad
        if case=='non_syn':ok=ok and any('SKIP reason=NON_SYN ' in l for l in lines)
        ok=ok and not re.search(r'(?m)^@\$(?:scriptContents\.pbRetry(?:Source|Read)|pbr(?:source|read))\(',text)
        passed=bool(ok) and r.returncode==0 and 'PBR_FIXTURE_DONE ' in text and not re.search(r'(?im)^.*(?:Error:|Syntax error|Extra character error|Traceback|Single step exception).*$',text)
        cases.append(dict(case=case,passed=passed,exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='per-send-nbl-cdb-proof-v1',script_sha256=SCRIPT_SHA,passed=len(cases)==len(CASES) and all(c['passed'] for c in cases),cases=cases,kernel_connection=False,product_started=False,traffic_generated=False,real_memory_watch=True)
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
