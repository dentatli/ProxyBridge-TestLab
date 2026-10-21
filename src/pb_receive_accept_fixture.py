"""Actual CDB hardware writes in synthetic user memory, no product or network."""
import json,re,subprocess,sys
from pathlib import Path
from pb_retry_chain_fixture import FIXTURE as BASE
from pb_receive_accept_profile import profile,SCRIPT,SCRIPT_SHA,PROFILE_SHA
from pb_endpoint_watch_candidate import quoted
CASES=('rst_ack','syn_ack','wrong_tuple','write_limit','accept_before_transition')
CODE=r'''
d(ep+0x30,0x1101641);q(b+0xb008,nbl);q(b+0xb050,header)
w(header,0xda85 if case=='wrong_tuple' else 0xda84);w(header+2,0xd9a4);z(header+13,0x12 if case=='syn_ack' else 0x14)
ctypes.memmove(b+0x1900,bytes.fromhex('f0 81 4b 30 00 00 20 00 c3'),9)
code=bytes.fromhex('53 55 56 57 41 56 48 83 ec 20')+mov('48 be',b)+mov('49 be',source)+mov('48 bf',ep)+mov('48 b8',rec)+bytes.fromhex('cc')+call(b+0x1800)
code+=mov('48 bb',ep)+mov('48 be',b+0xb000)
if case=='write_limit':code+=bytes.fromhex('83 4b 30 02')*17
elif case!='accept_before_transition':code+=call(b+0x1900)
code+=mov('48 bb',nbl)+mov('48 bd',frame)+mov('48 bf',ep)+mov('49 ba',frame-0x28)+mov('48 b8',0)+bytes.fromhex('49 89 02')
code+=bytes.fromhex('b8 25 02 00 c0')+call(b+0x1a00)+call(b+0x1b00)+bytes.fromhex('48 83 c4 20 41 5e 5f 5e 5d 5b c3')
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
        setup += ['.printf "PBT CONFIG writer=%p watch_limit=10 version=1\\n", @$t16','bp5 (@rsi+0x1b00) "dx @$scriptContents.pbcStop(); gc;"','be2','g']
        (p/'setup.wdbg').write_text('\n'.join(setup)+'\n');commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q'];(p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr);text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith(('PBC ','PBT '))]
        receives=[l for l in lines if l.startswith('PBT RECEIVE ')];accepts=[l for l in lines if l.startswith('PBC ACCEPT ')];final=[l for l in lines if l.startswith('PBC FINAL ')]
        passed=r.returncode==0 and len(final)==1 and 'PBC_FIXTURE_DONE ' in text and not any(l.startswith('PBC SKIP ') for l in lines) and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
        if case in ('rst_ack','syn_ack'):passed=passed and len(receives)==len(accepts)==1 and 'tcp_flags='+('14' if case=='rst_ack' else '12')+' ' in receives[0] and 'error=0' in final[0]
        elif case=='accept_before_transition':passed=passed and not receives and len(accepts)==1 and 'error=0' in final[0]
        else:passed=passed and not receives and not accepts and any('PBT INCOMPLETE reason='+('WATCH_LIMIT' if case=='write_limit' else 'WATCH_IDENTITY_OR_HEADER') in l for l in lines) and 'error=1' in final[0]
        results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='receive-accept-cdb-proof-v1',profile_sha256=PROFILE_SHA,script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False,writer_symbol_replaced_with_fixture_instruction_address=True,vvalid_guards_replaced=False)
    (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
