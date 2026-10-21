"""Only the changed arming behavior is exercised; the helper is unchanged."""
import json,re,subprocess,sys
from pathlib import Path
from pb_retry_chain_fixture import FIXTURE as BASE_FIXTURE
from pb_retry_chain_armed_profile import SCRIPT,SCRIPT_SHA,PROFILE_SHA,create_action,profile
from pb_endpoint_watch_candidate import quoted
CASES=('cold_before_create','create_guard','raw_limit')
FIXTURE=BASE_FIXTURE.replace("+bytes.fromhex('cc')+call(b+0x1800)","+bytes.fromhex('cc')\nif case=='cold_before_create':\n for _ in range(600):code+=call(b+0x1900)+call(b+0x1a00)\ncode+=call(b+0x1800)")
FIXTURE=FIXTURE.replace("q(nbl+8,nb);", "if case=='create_guard':q(rec+0x1e0,0)\nq(nbl+8,nb);")
if FIXTURE==BASE_FIXTURE:raise ValueError('FIXTURE_TRANSFORM_FAILED')
def check(output):
    root=Path(__file__).resolve().parents[1];out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False)
    (out/'candidate.json').write_text(json.dumps(profile(),indent=2)+'\n')
    sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');results=[]
    for case in CASES:
        p=out/case;p.mkdir();(p/'symbols').mkdir();(p/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['dx @$scriptContents.pbcInitModel(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)','dx @$scriptContents.pbcRegister(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)',
            'bp2 (@rsi+0x1800) '+quoted(create_action()),'bd2','bp5 (@rsi+0x1b00) "dx @$scriptContents.pbcStop(); gc;"','be2','g']
        (p/'setup.wdbg').write_text('\n'.join(setup)+'\n')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q']
        (p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr)
        text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBC ')]
        create=[l for l in lines if l.startswith('PBC CREATE ')];skip=[l for l in lines if l.startswith('PBC SKIP ')];accept=[l for l in lines if l.startswith('PBC ACCEPT ')];final=[l for l in lines if l.startswith('PBC FINAL ')]
        passed=r.returncode==0 and len(final)==1 and 'PBC_FIXTURE_DONE ' in text and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
        if case=='cold_before_create':passed=passed and len(create)==len(skip)==len(accept)==1 and 'skip_nbl_match=1' in accept[0] and 'error=0' in final[0]
        elif case=='create_guard':passed=passed and not create and not skip and not accept and any('reason=CREATE_CONTEXT' in l for l in lines) and 'error=1' in final[0]
        else:passed=passed and len(create)==1 and not skip and not accept and any('reason=RAW_LIMIT' in l for l in lines) and 'error=1' in final[0]
        results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='retry-chain-create-armed-cdb-proof-v1',profile_sha256=PROFILE_SHA,script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False)
    (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
