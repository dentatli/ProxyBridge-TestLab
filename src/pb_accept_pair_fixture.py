"""Isolated CDB call-site proofs. No kernel connection, driver or network traffic."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
from pb_endpoint_watch_candidate import quoted
from pb_accept_pair_profile import SCRIPT,SCRIPT_SHA
CASES=('healthy','failure','fillers_200','raw_limit','identity_change')
FIXTURE=r'''import ctypes,struct,json
k=ctypes.WinDLL('kernel32',use_last_error=True);k.VirtualAlloc.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_ulong,ctypes.c_ulong];k.VirtualAlloc.restype=ctypes.c_void_p
b=k.VirtualAlloc(None,0x10000,0x3000,0x40)
if not b:raise ctypes.WinError(ctypes.get_last_error())
case=CASE
q=lambda a,v:setattr(ctypes.c_uint64.from_address(a),'value',v)
d=lambda a,v:setattr(ctypes.c_uint32.from_address(a),'value',v)
w=lambda a,v:setattr(ctypes.c_uint16.from_address(a),'value',v)
frame=b+0x4000;ep=b+0x5000;nbl=b+0x6000;info=b+0x7000;node=b+0x7800;rec=b+0x8000
w(frame-0x7c,0xda84);w(frame-0x7a,0xd9a4)
q(nbl+0xe0,1 if case=='failure' else info+1)
d(info,0x6e706657);q(info+0x10,node);q(node+8,rec);q(node+0x10,5);q(node+0x80,node+0x80);q(rec+0x1e0,b+0x8800);q(rec+0x1e8,32)
for off in (0x1800,0x1900,0x1a00):ctypes.memmove(b+off,b'\xc3',1)
mov=lambda op,v:bytes.fromhex(op)+struct.pack('<Q',v)
call=lambda a:mov('49 bb',a)+bytes.fromhex('41 ff d3')
code=bytes.fromhex('53 55 56 57 48 83 ec 28')+mov('48 be',b)+mov('48 bd',frame)+mov('48 bf',ep)+mov('48 bb',nbl)+mov('48 b9',nbl)+bytes.fromhex('cc')
if case in ('fillers_200','raw_limit'):
 code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a5 d9')
 for _ in range(200 if case=='fillers_200' else 256):code+=call(b+0x1800)+call(b+0x1900)
 code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a4 d9')
code+=call(b+0x1800)
code+=mov('48 b8',0 if case=='failure' else rec)+mov('49 ba',frame-0x28)+bytes.fromhex('49 89 02')
code+=bytes.fromhex('b8')+struct.pack('<I',0xc0000225 if case=='failure' else 0)
if case=='identity_change':code+=mov('48 bb',nbl+0x100)
code+=call(b+0x1900)+call(b+0x1a00)+bytes.fromhex('48 83 c4 28 5f 5e 5d 5b c3')
assert len(code)<0x10000 and len(code)<0x1800 if case!='raw_limit' else len(code)<0x4000
# Large fixtures use a separate code allocation so call sites/data remain intact.
codebase=k.VirtualAlloc(None,0x10000,0x3000,0x40)
ctypes.memmove(codebase,code,len(code));ctypes.WINFUNCTYPE(None)(codebase)()
print('PBA_FIXTURE_DONE',json.dumps({'case':case}))
'''
def check(output):
 root=Path(__file__).resolve().parents[1];out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False)
 if hashlib.sha256((root/SCRIPT).read_bytes()).hexdigest()!=SCRIPT_SHA:raise ValueError('SCRIPT_SHA_DIFFERS')
 sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');results=[]
 for case in CASES:
  p=out/case;p.mkdir();(p/'symbols').mkdir();(p/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
  setup=['dx @$scriptContents.pbaInitModel(@rsi+0x1800,@rsi+0x1900)','dx @$scriptContents.pbaRegister(@rsi+0x1800,@rsi+0x1900)',
   'bp5 (@rsi+0x1a00) "dx @$scriptContents.pbaStop(); gc;"','be2','be3','g']
  (p/'setup.wdbg').write_text('\n'.join(setup)+'\n')
  commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q']
  (p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
  r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
  (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr)
  text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBA ')]
  pre=[l for l in lines if l.startswith('PBA PRE ')];post=[l for l in lines if l.startswith('PBA POST ')];final=[l for l in lines if l.startswith('PBA FINAL ')]
  passed=r.returncode==0 and len(final)==1 and 'PBA_FIXTURE_DONE ' in text and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
  if case=='raw_limit':passed=passed and not pre and not post and any('reason=RAW_LIMIT' in l for l in lines)
  elif case=='identity_change':passed=passed and len(pre)==1 and not post and any('reason=PAIR_IDENTITY' in l for l in lines) and 'error=1' in final[0]
  else:
   passed=passed and len(pre)==len(post)==1 and 'error=0' in final[0] and not any('PBA INCOMPLETE' in l for l in lines)
   passed=passed and ('key5=0' in pre[0] and 'status=c0000225 record=0' in post[0] if case=='failure' else 'key5=1' in pre[0] and 'status=0 ' in post[0] and 'size=20' in post[0])
  results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
  if not passed:break
 result=dict(method='accept-pair-cdb-proof-v1',script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False)
 (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
