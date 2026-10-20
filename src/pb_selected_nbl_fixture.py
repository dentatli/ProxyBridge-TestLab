"""Real CDB proof of CREATE -> SEND -> JS NBL watch handover; no traffic."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from pb_nbl_context_fixture import FIXTURE
from pb_endpoint_send_gate_fixture import transform
from pb_endpoint_watch_candidate import quoted
from pb_selected_nbl_profile import create_action,profile,PROFILE,SCRIPT,SCRIPT_SHA

CASES=('absent','present','removed','packet_changed','read_limit','source_read_boundary','bad_header')


def source(case,read_limit=16):
    s=FIXTURE.replace('CASE',repr(case))
    s=s.replace("mov=lambda op,v:","put32(b+0x5000,0xd9a40002);put32(ep+0x30,0x1101641)\nput64(record+0x1e0,b+0x4e00);put64(record+0x1e8,32);put32(record+0x1f0,1)\nmov=lambda op,v:")
    s=s.replace("code+=bytes.fromhex('cc')", "ctypes.memmove(b+0x1800,bytes.fromhex('90 c3'),2)\ncode+=mov('49 be',b+0x5000)+bytes.fromhex('cc')+mov('49 bb',b+0x1800)+bytes.fromhex('41 ff d3')")
    old="code+=bytes.fromhex('44 8b 57 30') # The SOURCE watch callback must replace itself."
    new="""ctypes.memmove(b+0x1000,bytes.fromhex('8b 41 30 0f ba e0 15 c3'),8)
code+=mov('48 b9',ep)+mov('48 bb',ep)+mov('49 be',2)+call(b+0x1000)
code+=bytes.fromhex('81 49 30 00 00 20 00')+call(b+0x1000)"""
    if s.count(old)!=1:raise ValueError('NBL_FIXTURE_CHANGED')
    s=s.replace(old,new)
    if case=='source_read_boundary':
        s=s.replace("code+=bytes.fromhex('81 49 30 00 00 20 00')+call(b+0x1000)",
            "code+=bytes.fromhex('81 49 30 00 00 20 00')+bytes.fromhex('8b 41 30')*61+call(b+0x1000)")
    if case=='bad_header':s=s.replace('42201,34010,123','42202,34010,123')
    if read_limit!=16:s=s.replace("bytes.fromhex('48 8b 81 e0 00 00 00')*16", "bytes.fromhex('48 8b 81 e0 00 00 00')*"+str(read_limit))
    return s


def check(output,script_relative=SCRIPT,script_sha=SCRIPT_SHA,profile_relative=PROFILE,expected_profile=None,read_limit=16):
    root=Path(__file__).resolve().parents[1];output=Path(output).resolve()
    output.mkdir(parents=True,exist_ok=False)
    script=root/script_relative;raw=(root/profile_relative).read_bytes()
    if hashlib.sha256(script.read_bytes()).hexdigest()!=script_sha or json.loads(raw)!=(profile() if expected_profile is None else expected_profile):raise ValueError('NBL_CANDIDATE_CHANGED')
    (output/'candidate.json').write_bytes(raw)
    sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');cases=[]
    for case in CASES:
        child=output/case;child.mkdir();(child/'symbols').mkdir()
        (child/'target.py').write_text(source(case,read_limit),encoding='ascii')
        setup=['r @$t0 = @rsi+0x1003','bp2 (@rsi+0x1100) "gc"','bd2','bp4 (@rsi+0x1200) "gc"','bd4',
            'r @$t1 = 0','r @$t3 = 0','r @$t8 = 0',
            'dx @$scriptContents.pbNblInitModel(@rsi+0x200d, *(unsigned __int64*)(@rsi+0x18000), *(unsigned __int64*)(@rsi+0x18008), 0xbad0)',
            'bp2 (@rsi+0x1800) '+quoted(transform(create_action())), 'bd2', 'be2', 'g']
        (child/'setup.wdbg').write_text('\n'.join(setup)+'\n',encoding='ascii')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(script),
            'sxe -c '+quoted('$$><'+str(child/'setup.wdbg'))+' bpe','g','q']
        (child/'proof.wdbg').write_text('\n'.join(commands)+'\n',encoding='ascii')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(child/'symbols'),'-cf',str(child/'proof.wdbg'),sys.executable,str(child/'target.py')],capture_output=True,timeout=30,creationflags=0x08000000)
        (child/'stdout.txt').write_bytes(r.stdout);(child/'stderr.txt').write_bytes(r.stderr)
        text=(r.stdout+r.stderr).decode(errors='replace')
        lines=[l for l in text.splitlines() if l.startswith(('PBN ','PBSD '))]
        done=any(l.startswith('PBN DONE ') for l in lines)
        failure='PACKET_IDENTITY_CHANGED' if case=='packet_changed' else 'READ_LIMIT'
        ok=(done and not any('INCOMPLETE' in l for l in lines)) if case in ('absent','present','removed') else (not done and any('reason='+failure in l for l in lines))
        if case=='source_read_boundary':ok=done and not any('INCOMPLETE' in l for l in lines) and any(' raw=40 ' in l for l in lines)
        if case=='bad_header':ok=not done and not any(l.startswith('PBN ARMED ') for l in lines) and any(l.startswith('PBSD_UNREADABLE event=SEND_HEADER') for l in text.splitlines())
        ok=ok and sum(l.startswith('PBSD TRACK ') for l in lines)==1 and sum(l.startswith('PBSD SEND_GATE ') for l in lines)==(1 if case=='bad_header' else 2) and (case=='bad_header' or any('flags_reg=1301641 ' in l for l in lines))
        passed=bool(ok) and r.returncode==0 and 'PBN_FIXTURE_DONE ' in text and not re.search(r'(?im)^.*(?:Error:|Syntax error|Extra character error|Traceback|Single step exception).*$',text)
        cases.append(dict(case=case,passed=passed,exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='selected-nbl-integrated-cdb-proof-v1',script_sha256=script_sha,profile_sha256=hashlib.sha256(raw).hexdigest(),
        passed=len(cases)==len(CASES) and all(c['passed'] for c in cases),cases=cases,
        kernel_connection=False,product_started=False,traffic_generated=False,
        guard_expressions_replaced_with_true=True,kernel_thread_replaced_with_tid=True,gate_symbol_replaced_with_fixture_address=True)
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n')
    return result
