"""Real CDB checks of multi-observation matching, bounds and cold arming."""
import json,re,subprocess,sys
from pathlib import Path
from pb_retry_chain_fixture import FIXTURE as BASE
from pb_retry_history_profile import SCRIPT,SCRIPT_SHA,PROFILE_SHA,profile
from pb_endpoint_watch_candidate import quoted
CASES=('later_nbl','window_limit','cold_before_create','source_changed','raw_limit')
CODE=r'''
for i in range(9):q(nbl+i*0x100+8,nb);q(nbl+i*0x100+0xe0,1)
code=bytes.fromhex('53 55 56 57 41 56 48 83 ec 20')+mov('48 be',b)+mov('49 be',source)+mov('48 bf',ep)+mov('48 b8',rec)+bytes.fromhex('cc')
if case=='cold_before_create':
 for _ in range(600):code+=call(b+0x1900)+call(b+0x1a00)
code+=call(b+0x1800)+mov('49 be',2)
if case=='raw_limit':
 code+=mov('48 bb',ep+0x100)+mov('48 bd',nbl)
 for _ in range(512):code+=bytes.fromhex('b8 41 16 30 01 0f ba e0 15')+call(b+0x1900)
count=9 if case=='window_limit' else 2 if case in ('later_nbl','source_changed') else 1
for i in range(count):
 if case=='source_changed' and i==1:code+=mov('49 ba',ep+0x1c0)+mov('48 b8',rec+0x100)+bytes.fromhex('49 89 02')
 code+=mov('48 bb',ep)+mov('48 bd',nbl+i*0x100)+bytes.fromhex('b8 41 16 30 01 0f ba e0 15')+call(b+0x1900)
code+=mov('48 bb',nbl+(count-1)*0x100)+mov('48 bd',frame)+mov('48 bf',ep)+mov('49 ba',frame-0x28)+mov('48 b8',0)+bytes.fromhex('49 89 02')
code+=bytes.fromhex('b8 25 02 00 c0')+call(b+0x1a00)+call(b+0x1b00)+bytes.fromhex('48 83 c4 20 41 5e 5f 5e 5d 5b c3')
'''
FIXTURE=BASE[:BASE.index("code=bytes.fromhex(")]+CODE+BASE[BASE.index('codebase='):]
def check(output):
    root=Path(__file__).resolve().parents[1];out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False)
    (out/'candidate.json').write_text(json.dumps(profile(),indent=2)+'\n');sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');results=[]
    for case in CASES:
        p=out/case;p.mkdir();(p/'symbols').mkdir();(p/'target.py').write_text(FIXTURE.replace('CASE',repr(case)),encoding='ascii')
        setup=['dx @$scriptContents.pbcInitModel(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)','dx @$scriptContents.pbcRegister(@rsi+0x1800,@rsi+0x1900,@rsi+0x1a00)',
            'bp5 (@rsi+0x1b00) "dx @$scriptContents.pbcStop(); gc;"','be2','g']
        (p/'setup.wdbg').write_text('\n'.join(setup)+'\n')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(root/SCRIPT),'sxe -c '+quoted('$$><'+str(p/'setup.wdbg'))+' bpe','g','q'];(p/'commands.wdbg').write_text('\n'.join(commands)+'\n')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(p/'symbols'),'-cf',str(p/'commands.wdbg'),sys.executable,str(p/'target.py')],capture_output=True,timeout=40,creationflags=0x08000000)
        (p/'stdout.txt').write_bytes(r.stdout);(p/'stderr.txt').write_bytes(r.stderr);text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBC ')]
        create=[l for l in lines if l.startswith('PBC CREATE ')];skip=[l for l in lines if l.startswith('PBC SKIP ')];accept=[l for l in lines if l.startswith('PBC ACCEPT ')];final=[l for l in lines if l.startswith('PBC FINAL ')]
        passed=r.returncode==0 and len(create)==len(final)==1 and 'PBC_FIXTURE_DONE ' in text and not re.search(r'(?im)(Error:|Syntax error|Extra character error|Traceback|Single step exception)',text)
        if case=='later_nbl':passed=passed and len(skip)==2 and len(accept)==1 and 'skip_count=2 match_hit=2 match_count=1' in accept[0] and 'error=0' in final[0]
        elif case=='window_limit':passed=passed and len(skip)==8 and len(accept)==1 and 'match_hit=0 match_count=0' in accept[0] and 'skip=8 skip_limit_reached=1' in final[0] and 'error=0' in final[0]
        elif case=='cold_before_create':passed=passed and len(skip)==len(accept)==1 and 'match_hit=1 match_count=1' in accept[0] and 'error=0' in final[0]
        else:passed=passed and len(skip)==(1 if case=='source_changed' else 0) and not accept and any('reason='+('SOURCE_RECORD_CHANGED' if case=='source_changed' else 'RAW_LIMIT') in l for l in lines) and 'error=1' in final[0]
        results.append(dict(case=case,passed=bool(passed),exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='retry-history-cdb-proof-v1',profile_sha256=PROFILE_SHA,script_sha256=SCRIPT_SHA,passed=len(results)==len(CASES) and all(c['passed'] for c in results),cases=results,kernel_connection=False,product_started=False,traffic_generated=False)
    (out/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
