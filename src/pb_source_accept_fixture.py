"""Exercise the new source snapshot without product/network/kernel execution."""
import json,re,subprocess,sys
from pathlib import Path
from pb_retry_chain_fixture import FIXTURE as BASE
from pb_source_accept_profile import SCRIPT,SCRIPT_SHA,PROFILE_SHA,profile
from pb_endpoint_watch_candidate import quoted
CASES=('present_cold_and_600_sends','source_gone','record_unreadable','accept_raw_limit')
CODE=r'''
code=bytes.fromhex('53 55 56 57 41 56 48 83 ec 20')+mov('48 be',b)+mov('49 be',source)+mov('48 bf',ep)+mov('48 b8',rec)+bytes.fromhex('cc')
if case=='present_cold_and_600_sends':
 for _ in range(600):code+=call(b+0x1900)+call(b+0x1a00)
code+=call(b+0x1800)+mov('49 be',2)+mov('48 bb',ep)+mov('48 bd',nbl)
if case=='present_cold_and_600_sends':
 for _ in range(600):code+=bytes.fromhex('b8 41 16 30 01 0f ba e0 15')+call(b+0x1900)
if case in ('source_gone','record_unreadable'):code+=mov('49 ba',ep+0x1c0)+mov('48 b8',0 if case=='source_gone' else 1)+bytes.fromhex('49 89 02')
code+=mov('48 bb',nbl)+mov('48 bd',frame)+mov('48 bf',ep)+mov('49 ba',frame-0x28)+mov('48 b8',0)+bytes.fromhex('49 89 02')
if case=='accept_raw_limit':
 code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a5 d9')
 for _ in range(512):code+=bytes.fromhex('b8 25 02 00 c0')+call(b+0x1a00)
 code+=mov('49 ba',frame-0x7a)+bytes.fromhex('66 41 c7 02 a4 d9')
code+=bytes.fromhex('b8 25 02 00 c0')+call(b+0x1a00)+call(b+0x1b00)+bytes.fromhex('48 83 c4 20 41 5e 5f 5e 5d 5b c3')
'''
FIXTURE=BASE[:BASE.index('code=bytes.fromhex(')]+CODE+BASE[BASE.index('codebase='):]
def check(output):
    root=Path(__file__).resolve().parents[1];out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False);candidate=profile()
    (out/'candidate.json').write_text(json.dumps(candidate,indent=2)+'\n');sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');results=[]
    for case in CASES:
        p=out/case;p.mkdir();(p/'symbols').mkdir();(p/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['dx @$scriptContents.pbcInitModel(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)','dx @$scriptContents.pbcRegister(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)',
            'bp2 (@rsi+0x1800) '+quoted(candidate['points'][0]['action']),'bd2','bp4 (@rsi+0x1a00) '+quoted(candidate['points'][2]['action']),'bd4','bd3',
            'bp5 (@rsi+0x1b00) "dx @$scriptContents.pbcStop(); gc;"','be2','g']
        (p/'setup.wdbg').write_text('\n'.join(setup)+'\n');commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q'];(p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr);text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBC ')]
        sources=[l for l in lines if l.startswith('PBC SOURCE ')];accepts=[l for l in lines if l.startswith('PBC ACCEPT ')];final=[l for l in lines if l.startswith('PBC FINAL ')]
        passed=r.returncode==0 and len(final)==1 and 'PBC_FIXTURE_DONE ' in text and not any(l.startswith('PBC SKIP ') for l in lines) and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
        if case=='present_cold_and_600_sends':passed=passed and len(sources)==len(accepts)==1 and 'size=20 flags30=1301641' in sources[0] and 'error=0' in final[0]
        elif case=='source_gone':passed=passed and len(sources)==len(accepts)==1 and 'record_now=0 context=0 size=0' in sources[0] and 'error=0' in final[0]
        elif case=='record_unreadable':passed=passed and not sources and len(accepts)==1 and any('SOURCE_UNREADABLE reason=RECORD' in l for l in lines) and 'error=0' in final[0]
        else:passed=passed and not sources and not accepts and any('reason=RAW_LIMIT' in l for l in lines) and 'error=1' in final[0]
        results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='source-accept-cdb-proof-v1',profile_sha256=PROFILE_SHA,script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False)
    (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
