"""Bounded real CDB fixtures for rare NULL observation, synthetic memory only."""
import json,re,subprocess,sys
from pathlib import Path
from pb_retry_chain_fixture import FIXTURE as BASE
from pb_receive_query_profile import profile,SCRIPT,SCRIPT_SHA,PROFILE_SHA
from pb_endpoint_watch_candidate import quoted
CASES=('rst_null_after_600_successes','synack_null','foreign_ioctl','null_limit')
CODE=r'''
d(ep+0x30,0x1101641);q(b+0xb008,nbl);q(b+0xb050,header)
w(header,0xda84);w(header+2,0xd9a4);z(header+13,0x12 if case=='synack_null' else 0x14)
ctypes.memmove(b+0x1900,bytes.fromhex('f0 81 4b 30 00 00 20 00 c3'),9);ctypes.memmove(b+0x1c00,b'\xc3',1)
code=bytes.fromhex('53 55 56 57 41 56 41 57 48 83 ec 28')+mov('48 be',b)+mov('49 be',source)+mov('48 bf',ep)+mov('48 b8',rec)+bytes.fromhex('cc')+call(b+0x1800)
code+=mov('48 bb',ep)+mov('48 be',b+0xb000)+call(b+0x1900)
if case=='rst_null_after_600_successes':
 for _ in range(600):code+=call(b+0x1c00)
code+=mov('48 bf',b+0xc000)+bytes.fromhex('31 d2')+mov('49 bf',0x980000de if case in ('foreign_ioctl','null_limit') else 0x980000dd)
for _ in range(17 if case=='null_limit' else 1):code+=call(b+0x1a00)
code+=call(b+0x1b00)+bytes.fromhex('48 83 c4 28 41 5f 41 5e 5f 5e 5d 5b c3')
'''
FIXTURE=BASE[:BASE.index('code=bytes.fromhex(')]+CODE+BASE[BASE.index('codebase='):]
def check(output):
    root=Path(__file__).resolve().parents[1];out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False);candidate=profile()
    (out/'candidate.json').write_text(json.dumps(candidate,indent=2)+'\n');sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');results=[]
    for case in CASES:
        p=out/case;p.mkdir();(p/'symbols').mkdir();(p/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['dx @$scriptContents.pbcInitModel(@rsi+0x1800,@rsi+0x1908,@rsi+0x1a00)','r @$t16 = @rsi+0x1908']
        for v in candidate['points']:
            action=v['action'].replace('tcpip!WfpTlShimInspectRecvTcpDatagram+0x198','@$t16')
            setup += ['bp'+str(v['id'])+' (@rsi+'+{2:'0x1800',3:'0x1908',4:'0x1a00'}[v['id']]+') '+quoted(action),'bd'+str(v['id'])]
        setup += ['.printf "PBT CONFIG writer=%p watch_limit=10 version=1\\n", @$t16','.printf "PBQ CONFIG query_null=%p query_limit=10 version=1\\n", @rsi+0x1a00','bp5 (@rsi+0x1b00) "dx @$scriptContents.pbcStop(); .printf \\"PBQ_RAW count=%I64x\\\\n\\", @$t2; gc;"','be2','g']
        # Quote the final breakpoint action with the same helper used for all actions.
        setup[-3]='bp5 (@rsi+0x1b00) '+quoted('dx @$scriptContents.pbcStop(); .printf "PBQ_RAW count=%I64x\\n", @$t2; gc;')
        (p/'setup.wdbg').write_text('\n'.join(setup)+'\n');commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q'];(p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr);text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith(('PBC ','PBT ','PBQ '))]
        queries=[l for l in lines if l.startswith('PBQ NULL ')];receives=[l for l in lines if l.startswith('PBT RECEIVE ')];final=[l for l in lines if l.startswith('PBC FINAL ')]
        passed=r.returncode==0 and len(final)==len(receives)==1 and 'PBC_FIXTURE_DONE ' in text and not any(l.startswith(('PBC SKIP ','PBC ACCEPT ')) for l in lines) and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
        if case in ('rst_null_after_600_successes','synack_null'):passed=passed and len(queries)==1 and 'error=0' in final[0] and 'PBQ_RAW count=1' in text
        elif case=='foreign_ioctl':passed=passed and not queries and 'error=0' in final[0]
        else:passed=passed and not queries and any('reason=NULL_RAW_LIMIT' in l for l in lines) and 'error=1' in final[0]
        results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='receive-query-cdb-proof-v1',profile_sha256=PROFILE_SHA,script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False,writer_symbol_replaced_with_fixture_instruction_address=True,success_branch_is_synthetic=True,vvalid_guards_replaced=False)
    (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
