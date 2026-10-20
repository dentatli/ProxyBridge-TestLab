"""Real CDB/JsProvider memory-watch fixtures. No kernel connection or traffic."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

CASES=('absent','present','high_record','other_high_record','removed','added','inactive','inactive_only','empty_root','bad_pointer','bad_tag','ring8','cycle','ring9','config_missing','external_clear',
       'unreadable','read_limit','other_caller','packet_changed','wrong_tuple')
FIXTURE=r'''import ctypes,struct,json
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.VirtualAlloc.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_ulong,ctypes.c_ulong]
k.VirtualAlloc.restype=ctypes.c_void_p
b=k.VirtualAlloc(None,0x20000,0x3000,0x40)
if not b:raise ctypes.WinError(ctypes.get_last_error())
case=CASE
put64=lambda a,v:setattr(ctypes.c_uint64.from_address(a),'value',v)
put32=lambda a,v:setattr(ctypes.c_uint32.from_address(a),'value',v)
put16=lambda a,v:setattr(ctypes.c_uint16.from_address(a),'value',v)
ep=b+0x4000;record=b+0x4800;frame=b+0x5800;accepted=b+0x6000
if case in ('high_record','other_high_record'):record=0xffffb888c4cca260
nbl=b+0x7000;nb=nbl+0x100;mdl=nbl+0x200;data=nbl+0x300;info=b+0x9000;root=b+0xa000
put64(ep+0x1c0,record);put16(frame-0x7c,0xda84);put16(frame-0x7a,0xd9a4)
put64(nbl+8,nb);put64(nb+8,mdl);put32(nb+0x10,0);put32(nb+0x18,20)
put16(mdl+0xa,1);put64(mdl+0x18,data);put32(mdl+0x28,20)
header=struct.pack('!HHIIBBHHH',42201,34010,123,0,0x50,2,1024,0,0)
ctypes.memmove(data,header,20);put32(info,0x6e706657);put64(info+0x10,root)
nodes=8 if case=='ring8' else 9 if case=='ring9' else 2 if case in ('cycle','inactive') else 1
for i in range(nodes):
 node=root+i*0x100;put64(node+8,record);put64(node+0x10,4 if case in ('ring8','ring9','cycle') else 5)
 put64(node+0x80,root+((i+1)%nodes)*0x100+0x80)
if case=='inactive':ctypes.c_ubyte.from_address(root+0xb8).value=1
if case=='inactive_only':ctypes.c_ubyte.from_address(root+0xb8).value=1
if case=='empty_root':put64(info+0x10,0)
if case=='bad_tag':put32(info,0)
if case=='other_high_record':put64(root+8,record+1)
if case=='cycle':put64(root+0x180,root+0x180)
put64(nbl+0xe0,0 if case in ('absent','added') else 0x12345 if case=='unreadable' else info+1)
if case=='bad_pointer':put64(nbl+0xe0,0xbad1)
mov=lambda op,v:bytes.fromhex(op)+struct.pack('<Q',v)
call=lambda a:mov('48 b8',a)+bytes.fromhex('ff d0')
netio=bytes.fromhex('40 53 48 83 ec 30 48 8b 99 e0 00 00 00 48 83 e3 fc 48 8b c3 48 83 c4 30 5b c3')
ctypes.memmove(b+0x2000,netio,len(netio))
wrapper=bytes.fromhex('53 55 56 48 83 ec 50 48 89 7c 24 78 be 05 00 00 00 bd 01 00 00 00')
wrapper+=call(b+0x2000);wrapper_return=0x3000+len(wrapper)
wrapper+=bytes.fromhex('48 83 c4 50 5e 5d 5b c3');ctypes.memmove(b+0x3000,wrapper,len(wrapper))
code=bytes.fromhex('53 55 56 57 41 56 48 83 ec 60')
code+=mov('48 be',b)+mov('48 bf',ep)+mov('48 b8',record)+mov('48 bd',nbl)
# Return addresses are passed through scratch memory to the isolated setup.
code+=bytes.fromhex('cc')
code+=bytes.fromhex('44 8b 57 30') # The SOURCE watch callback must replace itself.
code+=mov('48 bf',accepted)+mov('48 bd',frame)+mov('48 b9',nbl)
# Unrelated NBL access must never consume the selected-object budget.
code+=mov('49 ba',b+0x8000)+bytes.fromhex('49 8b 82 e0 00 00 00')
if case in ('removed','added'):
 code+=mov('49 ba',nbl+0xe0)+mov('48 b8',0 if case=='removed' else info+1)+bytes.fromhex('49 89 02')
if case=='packet_changed':code+=mov('49 ba',data+4)+bytes.fromhex('41 c7 02 01 00 00 00')
if case=='wrong_tuple':code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a5 d9')
if case=='read_limit':code+=bytes.fromhex('48 8b 81 e0 00 00 00')*16
if case=='other_caller':code+=call(b+0x3000)
code+=call(b+0x3000);accept_return=len(code)
code+=mov('48 b9',nbl)+bytes.fromhex('48 8b 81 e0 00 00 00')*3
code+=bytes.fromhex('48 83 c4 60 41 5e 5f 5e 5d 5b c3')
put64(b+0x18000,b+wrapper_return);put64(b+0x18008,b+accept_return)
ctypes.memmove(b,code,len(code));ctypes.WINFUNCTYPE(None)(b)()
print('PBN_FIXTURE_DONE',json.dumps({'case':case}))
'''


def check(output):
    from pb_endpoint_watch_candidate import quoted
    root=Path(__file__).resolve().parents[1]
    script=root/'scripts/debugger/pb_nbl_context.js'
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=False)
    sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64')
    cases=[]
    for case in CASES:
        child=output/case;child.mkdir()
        (child/'empty-symbols').mkdir()
        (child/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['ba3 r4 (@rsi+0x4030) "dx @$scriptContents.pbNblArm(@rbp,@rax,@rdi); gc;"','r @$t8 = 1',
            '.printf "PBN_FIXTURE_REGS nbl=%p record=%p source=%p\\n", @rbp,@rax,@rdi',
            'dx @$scriptContents.pbNblInitModel(@rsi+0x200d, *(unsigned __int64*)(@rsi+0x18000), *(unsigned __int64*)(@rsi+0x18008), 0xbad0)',
            'g']
        if case=='config_missing':setup=[s for s in setup if 'pbNblInitModel' not in s]
        if case=='external_clear':setup[0]='ba3 r4 (@rsi+0x4030) "dx @$scriptContents.pbNblArm(@rbp,@rax,@rdi); bc3; dx @$scriptContents.pbNblStop(); .printf \\"PBN_FIXTURE_RECOVERY_OK\\\\n\\"; gc;"'
        (child/'setup.wdbg').write_text('\n'.join(setup)+'\n',encoding='ascii')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(script),
            'sxe -c '+quoted('$$><'+str(child/'setup.wdbg'))+' bpe','g','q']
        (child/'proof.wdbg').write_text('\n'.join(commands)+'\n',encoding='ascii')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(child/'empty-symbols'),'-cf',str(child/'proof.wdbg'),sys.executable,str(child/'target.py')],
            capture_output=True,timeout=30,creationflags=0x08000000)
        (child/'stdout.txt').write_bytes(r.stdout);(child/'stderr.txt').write_bytes(r.stderr)
        text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBN ')]
        complete=any(l.startswith('PBN DONE ') for l in lines)
        failures=[l for l in lines if l.startswith('PBN INCOMPLETE ')]
        send=next((l for l in lines if l.startswith('PBN STATE stage=send ')),None)
        receive=next((l for l in lines if l.startswith('PBN STATE stage=receive ')),None)
        expected_errors={'cycle':'LIST_CYCLE','ring9':'LIST_LIMIT','unreadable':'MEMORY_OR_LAYOUT','bad_tag':'WFP_INFO_TAG','config_missing':'CONFIG_REQUIRED',
            'read_limit':'READ_LIMIT','packet_changed':'PACKET_IDENTITY_CHANGED','wrong_tuple':'ACCEPT_TUPLE'}
        if case=='external_clear':ok=not complete and not failures and bool(send) and 'PBN_FIXTURE_RECOVERY_OK' in text
        elif case in expected_errors:ok=not complete and any('reason='+expected_errors[case] in f for f in failures)
        else:
            send_state='absent' if case in ('absent','added','ring8','inactive_only','empty_root','bad_pointer') else 'present'
            receive_state='absent' if case in ('absent','removed','ring8','inactive_only','empty_root','bad_pointer') else 'present'
            ok=complete and not failures and send and receive and 'key5='+send_state in send and 'key5='+receive_state in receive
            if case=='high_record':ok=ok and 'value=ffffb888c4cca260 record_match=1' in send and 'record_match=1' in receive
            if case=='other_high_record':ok=ok and 'value=ffffb888c4cca261 record_match=0' in send and 'record_match=0' in receive
            if case=='other_caller':ok=ok and any(' raw=2 key=5 ' in l for l in lines)
        passed=r.returncode==0 and 'PBN_FIXTURE_DONE ' in text and bool(ok) and not re.search(r'(?im)^.*(?:Error:|Syntax error|Extra character error|Traceback|Single step exception).*$',text)
        cases.append(dict(case=case,passed=passed,exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='selected-nbl-js-cdb-proof-v1',script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(),
        passed=len(cases)==len(CASES) and all(c['passed'] for c in cases),cases=cases,
        kernel_connection=False,product_started=False,traffic_generated=False,kernel_symbols_replaced_with_fixture_addresses=True,
        real_cpu_stack_frames=True,real_memory_watch=True,real_watch_replacement_from_callback=True,real_js_provider=True)
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n')
    return result
