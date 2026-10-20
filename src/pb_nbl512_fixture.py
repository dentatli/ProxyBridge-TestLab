"""CDB fixtures for bounded reject diagnostics and the 512-access helper."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from pb_nbl_context_fixture import CASES as BASE_CASES,FIXTURE
from pb_endpoint_watch_candidate import quoted

CASES=BASE_CASES+('late_receive','boundary512','key_reject','consume_reject','retrieve_reject','object_reject','caller_before_key')
SCRIPT='scripts/debugger/pb_nbl_context512.js'
SCRIPT_SHA='f78b4ac191a85b30d0a7ce1e25868d77485c572b5f73bd6eeacde4782e4b6c74'


def source(case):
    s=FIXTURE.replace('CASE',repr(case)).replace("bytes.fromhex('48 8b 81 e0 00 00 00')*16", "bytes.fromhex('48 8b 81 e0 00 00 00')*512")
    if case in ('late_receive','boundary512'):
        s=s.replace("if case=='read_limit':", "if case in ('late_receive','boundary512'):code+=bytes.fromhex('48 8b 81 e0 00 00 00')*"+('20' if case=='late_receive' else '511')+"\nif case=='read_limit':")
    if case in ('key_reject','caller_before_key'):s=s.replace('be 05 00 00 00','be 04 00 00 00')
    if case=='consume_reject':s=s.replace('bd 01 00 00 00','bd 00 00 00 00')
    if case=='object_reject':
        s=s.replace('48 8b 99 e0 00 00 00','49 8b 9a e0 00 00 00')
        s=s.replace("code+=call(b+0x3000)","code+=mov('49 ba',nbl)+mov('48 b9',b+0x8000)+call(b+0x3000)")
    return s


def check(output):
    root=Path(__file__).resolve().parents[1];script=root/SCRIPT
    if hashlib.sha256(script.read_bytes()).hexdigest()!=SCRIPT_SHA:raise ValueError('NBL512_SCRIPT_CHANGED')
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=False)
    sdk=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64');cases=[]
    for case in CASES:
        child=output/case;child.mkdir();(child/'symbols').mkdir()
        (child/'target.py').write_text(source(case),encoding='ascii')
        setup=['ba3 r4 (@rsi+0x4030) "dx @$scriptContents.pbNblArm(@rbp,@rax,@rdi); gc;"','r @$t8 = 1',
            'dx @$scriptContents.pbNblInitModel(@rsi+0x200d, *(unsigned __int64*)(@rsi+0x18000), *(unsigned __int64*)(@rsi+0x18008), 0xbad0)','g']
        if case=='config_missing':setup=[s for s in setup if 'pbNblInitModel' not in s]
        if case in ('retrieve_reject','caller_before_key'):setup[2]=setup[2].replace('0x18000),','0x18000)+1,')
        if case=='external_clear':setup[0]='ba3 r4 (@rsi+0x4030) "dx @$scriptContents.pbNblArm(@rbp,@rax,@rdi); bc3; dx @$scriptContents.pbNblStop(); .printf \\"PBN_FIXTURE_RECOVERY_OK\\\\n\\"; gc;"'
        (child/'setup.wdbg').write_text('\n'.join(setup)+'\n',encoding='ascii')
        commands=['.load '+str(sdk/'winext/JsProvider.dll'),'.scriptload '+str(script),
            'sxe -c '+quoted('$$><'+str(child/'setup.wdbg'))+' bpe','g','q']
        (child/'proof.wdbg').write_text('\n'.join(commands)+'\n',encoding='ascii')
        r=subprocess.run([str(sdk/'cdb.exe'),'-sins','-y',str(child/'symbols'),'-cf',str(child/'proof.wdbg'),sys.executable,str(child/'target.py')],capture_output=True,timeout=30,creationflags=0x08000000)
        (child/'stdout.txt').write_bytes(r.stdout);(child/'stderr.txt').write_bytes(r.stderr)
        text=(r.stdout+r.stderr).decode(errors='replace');lines=[l for l in text.splitlines() if l.startswith('PBN ')]
        done=any(l.startswith('PBN DONE ') for l in lines);fail=[l for l in lines if l.startswith('PBN INCOMPLETE ')]
        reject=[l for l in lines if l.startswith('PBN REJECT ')];summary=[l for l in lines if l.startswith('PBN SUMMARY ')]
        expected={'cycle':'LIST_CYCLE','ring9':'LIST_LIMIT','unreadable':'MEMORY_OR_LAYOUT','bad_tag':'WFP_INFO_TAG','config_missing':'CONFIG_REQUIRED',
            'read_limit':'READ_LIMIT','packet_changed':'PACKET_IDENTITY_CHANGED','wrong_tuple':'ACCEPT_TUPLE'}
        reasons={'key_reject':'KEY','consume_reject':'CONSUME','retrieve_reject':'RETRIEVE_CALLER','object_reject':'OBJECT','caller_before_key':'RETRIEVE_CALLER'}
        if case in expected:ok=not done and any('reason='+expected[case] in l for l in fail)
        elif case in reasons:ok=not done and not fail and any('reason='+reasons[case]+' ' in l for l in reject)
        elif case=='external_clear':ok=not done and not fail and 'PBN_FIXTURE_RECOVERY_OK' in text
        else:ok=done and not fail
        if case in ('absent','present','removed','added','inactive_only','ring8','empty_root','bad_pointer'):
            send='absent' if case in ('absent','added','inactive_only','ring8','empty_root','bad_pointer') else 'present'
            receive='absent' if case in ('absent','removed','inactive_only','ring8','empty_root','bad_pointer') else 'present'
            ok=ok and any('STATE stage=send ' in l and 'key5='+send in l for l in lines) and any('STATE stage=receive ' in l and 'key5='+receive in l for l in lines)
        if case=='high_record':ok=ok and any('value=ffffb888c4cca260 record_match=1' in l for l in lines)
        if case=='other_high_record':ok=ok and any('value=ffffb888c4cca261 record_match=0' in l for l in lines)
        if case=='late_receive':ok=ok and any(' raw=15 key=5 ' in l for l in lines) and len(reject)==4 and any('SUMMARY total=15 ip=14 ' in l for l in summary)
        if case=='boundary512':ok=ok and any(' raw=200 key=5 ' in l for l in lines) and any('SUMMARY total=200 ip=1ff ' in l for l in summary)
        if case=='read_limit':ok=ok and len(reject)==4 and any('SUMMARY total=200 ip=200 ' in l for l in summary)
        if case=='other_caller':ok=ok and any('reason=ACCEPT_CALLER ' in l for l in reject)
        passed=bool(ok) and len(reject)<=4 and len(summary)<=1 and r.returncode==0 and 'PBN_FIXTURE_DONE ' in text and not re.search(r'(?im)^.*(?:Error:|Syntax error|Extra character error|Traceback|Single step exception).*$',text)
        cases.append(dict(case=case,passed=passed,exit_code=r.returncode,observations=lines))
        if not passed:break
    result=dict(method='selected-nbl512-js-cdb-proof-v1',script_sha256=SCRIPT_SHA,passed=len(cases)==len(CASES) and all(c['passed'] for c in cases),cases=cases,
        kernel_connection=False,product_started=False,traffic_generated=False,real_memory_watch=True,real_cpu_stack_frames=True,real_js_provider=True)
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n');return result
