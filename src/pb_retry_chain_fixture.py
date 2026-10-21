"""Short real CDB/MASM/JS execution in synthetic user memory; no product/network."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
from pb_endpoint_watch_candidate import quoted
from pb_retry_chain_profile import SCRIPT,SCRIPT_SHA
CASES=('missing','background_200','source_changed','early_healthy','raw_limit')
FIXTURE=r'''import ctypes,struct,json
k=ctypes.WinDLL('kernel32',use_last_error=True);k.VirtualAlloc.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_ulong,ctypes.c_ulong];k.VirtualAlloc.restype=ctypes.c_void_p
b=k.VirtualAlloc(None,0x10000,0x3000,0x40)
if not b:raise ctypes.WinError(ctypes.get_last_error())
case=CASE
q=lambda a,v:setattr(ctypes.c_uint64.from_address(a),'value',v)
d=lambda a,v:setattr(ctypes.c_uint32.from_address(a),'value',v)
w=lambda a,v:setattr(ctypes.c_uint16.from_address(a),'value',v)
z=lambda a,v:setattr(ctypes.c_uint8.from_address(a),'value',v)
source=b+0x3800;frame=b+0x4000;ep=b+0x5000;nbl=b+0x6000;info=b+0x7000;node=b+0x7800;rec=b+0x8000;nb=b+0x9000;mdl=b+0xa000;header=mdl+0x100
w(source,2);w(source+2,0xd9a4);w(frame-0x7c,0xda84);w(frame-0x7a,0xd9a4)
q(ep+0x1c0,rec);d(ep+0x30,0x1301641);q(rec+0x1e0,b+0x8800);q(rec+0x1e8,32);d(rec+0x1f0,1)
q(nbl+0xe0,info+1 if case=='early_healthy' else 1);d(info,0x6e706657);q(info+0x10,node);q(node+8,rec);q(node+0x10,5);q(node+0x80,node+0x80)
q(nbl+8,nb);q(nb+8,mdl);d(nb+0x10,0x100);d(nb+0x18,20);w(mdl+0xa,1);q(mdl+0x18,mdl);d(mdl+0x28,0x200)
w(header,0xd9a4);w(header+2,0xda84);d(header+4,0x12345678);z(header+12,0x50);z(header+13,2)
for off in (0x1800,0x1900,0x1a00,0x1b00):ctypes.memmove(b+off,b'\xc3',1)
mov=lambda op,v:bytes.fromhex(op)+struct.pack('<Q',v)
call=lambda a:mov('49 bb',a)+bytes.fromhex('41 ff d3')
code=bytes.fromhex('53 55 56 57 41 56 48 83 ec 20')+mov('48 be',b)+mov('49 be',source)+mov('48 bf',ep)+mov('48 b8',rec)+bytes.fromhex('cc')+call(b+0x1800)
code+=mov('48 bb',ep)+mov('48 bd',nbl)+mov('49 be',2)
if case=='source_changed':code+=mov('49 ba',ep+0x1c0)+mov('48 b8',rec+0x100)+bytes.fromhex('49 89 02')
if case in ('background_200','raw_limit'):
 code+=mov('48 bb',ep+0x100)
 for _ in range(200 if case=='background_200' else 512):code+=bytes.fromhex('b8 41 16 30 01 0f ba e0 15')+call(b+0x1900)
 code+=mov('48 bb',ep)
if case!='early_healthy':code+=bytes.fromhex('b8 41 16 30 01 0f ba e0 15')+call(b+0x1900)
code+=mov('48 bb',nbl)+mov('48 bd',frame)+mov('48 bf',ep)
code+=mov('49 ba',frame-0x28)+mov('48 b8',rec if case=='early_healthy' else 0)+bytes.fromhex('49 89 02')
if case=='background_200':
 code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a5 d9')
 for _ in range(200):code+=bytes.fromhex('31 c0')+call(b+0x1a00)
 code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a4 d9')
code+=bytes.fromhex('b8')+struct.pack('<I',0 if case=='early_healthy' else 0xc0000225)+call(b+0x1a00)+call(b+0x1b00)+bytes.fromhex('48 83 c4 20 41 5e 5f 5e 5d 5b c3')
codebase=k.VirtualAlloc(None,0x10000,0x3000,0x40);assert codebase and len(code)<0x10000
ctypes.memmove(codebase,code,len(code));ctypes.WINFUNCTYPE(None)(codebase)()
print('PBC_FIXTURE_DONE',json.dumps({'case':case}))
'''
def check(output):
    root=Path(__file__).resolve().parents[1];out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False)
    if hashlib.sha256((root/SCRIPT).read_bytes()).hexdigest()!=SCRIPT_SHA:raise ValueError('SCRIPT_SHA_DIFFERS')
    sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');results=[]
    for case in CASES:
        p=out/case;p.mkdir();(p/'symbols').mkdir();(p/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['dx @$scriptContents.pbcInitModel(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)','dx @$scriptContents.pbcRegister(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)',
            'bp5 (@rsi+0x1b00) "dx @$scriptContents.pbcStop(); gc;"','be2','be3','be4','g']
        (p/'setup.wdbg').write_text('\n'.join(setup)+'\n')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q']
        (p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr)
        text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBC ')]
        create=[l for l in lines if l.startswith('PBC CREATE ')];skip=[l for l in lines if l.startswith('PBC SKIP ')];accept=[l for l in lines if l.startswith('PBC ACCEPT ')];final=[l for l in lines if l.startswith('PBC FINAL ')]
        passed=r.returncode==0 and len(create)==len(final)==1 and 'PBC_FIXTURE_DONE ' in text and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
        if case in ('missing','background_200'):passed=passed and len(skip)==len(accept)==1 and 'key5=0' in skip[0] and 'status=c0000225 ' in accept[0] and 'skip_nbl_match=1' in accept[0] and 'error=0' in final[0]
        elif case=='early_healthy':passed=passed and not skip and len(accept)==1 and 'skip_seen=0' in accept[0] and 'status=0 ' in accept[0] and 'key5=1' in accept[0] and 'error=0' in final[0]
        else:passed=passed and not skip and not accept and any('reason='+('SOURCE_RECORD_CHANGED' if case=='source_changed' else 'RAW_LIMIT') in l for l in lines) and 'error=1' in final[0]
        results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='retry-chain-cdb-proof-v1',script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False)
    (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
