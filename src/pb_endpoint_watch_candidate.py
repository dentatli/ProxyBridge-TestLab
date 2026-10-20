"""Selected endpoint data-watch candidate and isolated user-mode CDB proof."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def quoted(command):
    return '"'+command.replace('\\','\\\\').replace('"','\\"')+'"'


CLEAR='.if (@$t8 != 0) { bc3; r @$t8 = 0; };'
STOP='bd2; '+CLEAR+' bd4;'


def watch_action():
    return ('r @$t4 = @$t4 + 1; '
        '.if (($vvalid(@$t2+0x30,4) == 1) and ($vvalid(@$t2+0x1c0,8) == 1)) { '
        '.if (poi(@$t2+0x1c0) == @$t1) { r @$t7 = dwo(@$t2+0x30); '
        '.printf "PBW WRITE hit=%I64x thread=%p ep=%p record=%p old=%x new=%x ip=%p\\n", '
        '@$t4, @$thread, @$t2, @$t1, @$t6, @$t7, @rip; '
        '.if (((@$t6 & 0x200000) == 0) and ((@$t7 & 0x200000) != 0)) { '+CLEAR+' '
        '.printf "PBW TRANSITION_BEGIN\\n"; k 8; .printf "PBW TRANSITION_END\\n"; '
        '} .else { .if (@$t4 >= 0x10) { '+STOP+' .printf "PBW_LIMIT point=3 capture=incomplete\\n"; } }; '
        'r @$t6 = @$t7; '
        '} .else { '+STOP+' .printf "PBW_IDENTITY_CHANGED capture=incomplete\\n"; } '
        '} .else { '+STOP+' .printf "PBW_UNREADABLE event=WRITE capture=incomplete\\n"; }; gc;')


def create_action():
    arm='r @$t8 = 1; ba3 w4 (@$t2+0x30) '+quoted(watch_action())+';'
    return ('r @$t3 = @$t3 + 1; .if (@$t3 >= 0x10) { '+STOP+
        ' .printf "PBW_LIMIT point=2 capture=incomplete\\n"; } .else { '
        '.if ($vvalid(@r14,0x10) == 1) { .if ((wo(@r14) == 2) and (wo(@r14+2) == 0xd9a4)) { bd2; '
        '.if (($vvalid(@rdi+0x30,4) == 1) and ($vvalid(@rdi+0x1c0,8) == 1) and '
        '($vvalid(@rax+0x1e0,0x14) == 1) and (@rax != 0) and ((@rdi & 3) == 0)) { '
        'r @$t1 = @rax; r @$t2 = @rdi; r @$t6 = dwo(@rdi+0x30); r @$t4 = 0; '
        '.printf "PBW TRACK ep=%p record=%p context=%p size=%I64x refs=%x flags30=%x\\n", '
        '@rdi, @rax, poi(@rax+0x1e0), poi(@rax+0x1e8), dwo(@rax+0x1f0), @$t6; '
        +arm+' .printf "PBW ARMED address=%p\\n", @$t2+0x30; '
        '} .else { '+STOP+' .printf "PBW_UNREADABLE event=TRACK capture=incomplete\\n"; } } } }; gc;')


FIXTURE=r'''import ctypes,struct,json
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.VirtualAlloc.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_ulong,ctypes.c_ulong]
k.VirtualAlloc.restype=ctypes.c_void_p
base=k.VirtualAlloc(None,0x2000,0x3000,0x40)
if not base:raise ctypes.WinError(ctypes.get_last_error())
ep=base+0x400;record=base+0x800;selector=base+0xc00;other=base+0x1000
ctypes.c_uint64.from_address(ep+0x1c0).value=record
ctypes.c_uint32.from_address(ep+0x30).value=0x1101641
ctypes.c_uint64.from_address(record+0x1e0).value=base+0xe00
ctypes.c_uint64.from_address(record+0x1e8).value=32
ctypes.c_uint32.from_address(record+0x1f0).value=1
ctypes.c_uint32.from_address(selector).value=0xd9a40002
# Preserve Windows x64 nonvolatile registers. INT3 invokes the synthetic CREATE handler.
mov=lambda prefix,value:bytes.fromhex(prefix)+struct.pack('<Q',value)
code=bytes.fromhex('57 41 56')+mov('49 be',selector)+mov('48 bf',ep)+mov('48 b8',record)+bytes.fromhex('cc')
# Unrelated endpoint write must not hit; then write selected flags twice.
code+=mov('49 ba',other)+bytes.fromhex('41 83 4a 30 01')
code+=bytes.fromhex('81 4f 30 00 00 20 00 83 4f 30 02 41 5e 5f c3')
ctypes.memmove(base,code,len(code))
ctypes.WINFUNCTYPE(None)(base)()
print('PBW_FIXTURE_DONE',json.dumps(dict(flags=ctypes.c_uint32.from_address(ep+0x30).value,other=ctypes.c_uint32.from_address(other+0x30).value)))
'''


def check_case(output,kind):
    output.mkdir(parents=True,exist_ok=False)
    source=FIXTURE
    write="code+=bytes.fromhex('81 4f 30 00 00 20 00 83 4f 30 02 41 5e 5f c3')"
    if kind=='cap':
        source=source.replace(write,"code+=bytes.fromhex('83 4f 30 02')*17+bytes.fromhex('41 5e 5f c3')")
    elif kind=='identity':
        source=source.replace(write,"code+=bytes.fromhex('48 c7 87 c0 01 00 00 00 00 00 00 81 4f 30 00 00 20 00 41 5e 5f c3')")
    compile(source,'watch-fixture','exec')
    target=output/'target.py';target.write_text(source,encoding='ascii',newline='\n')
    action=re.sub(r'\$vvalid\([^()]*\)','1',create_action()).replace('@$thread','@$tid')
    commands=['bp2 @$ip+0x20 "gc"','bd2','bp4 @$ip+0x40 "gc"','bd4']
    commands += ['r @$t'+str(i)+' = 0' for i in range(1,9)]
    commands += ['sxe -c '+quoted(action)+' bpe','g','q']
    path=output/'proof.wdbg';path.write_text('\n'.join(commands)+'\n',encoding='ascii',newline='\n')
    debugger=r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'
    symbols=output/'empty-symbols';symbols.mkdir()
    c=subprocess.run([debugger,'-sins','-y',str(symbols),'-cf',str(path),sys.executable,str(target)],capture_output=True,timeout=30,creationflags=0x08000000)
    (output/'proof.stdout.txt').write_bytes(c.stdout);(output/'proof.stderr.txt').write_bytes(c.stderr)
    text=(c.stdout+c.stderr).decode('utf-8',errors='replace')
    lines=[x.strip() for x in text.splitlines()]
    writes=[x for x in lines if x.startswith('PBW WRITE ')]
    verdict=(len(writes)==1 and 'old=1101641 new=1301641' in writes[0] and
             'PBW TRANSITION_BEGIN' in lines and 'PBW TRANSITION_END' in lines) if kind=='transition' else (
             len(writes)==16 and 'PBW_LIMIT point=3 capture=incomplete' in lines if kind=='cap' else
             not writes and 'PBW_IDENTITY_CHANGED capture=incomplete' in lines)
    passed=(c.returncode==0 and verdict and any(x.startswith('PBW_FIXTURE_DONE') for x in lines) and
            not re.search(r'(?i)(syntax error|extra character error|couldn.t resolve|Traceback)',text))
    result=dict(method='endpoint-data-watch-real-user-mode-proof-v1',case=kind,passed=passed,exit_code=c.returncode,
                kernel_connection=False,product_started=False,traffic_generated=False,write_events=writes,
                guard_expressions_replaced_with_true=True,kernel_thread_replaced_with_tid=True)
    (output/'proof.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result


def check(output):
    import hashlib
    output.mkdir(parents=True,exist_ok=False)
    profile=Path(__file__).resolve().parents[1]/'scripts/debugger/pb-kd-selected-endpoint-watch-profile-20261020.json'
    raw=profile.read_bytes();p=json.loads(raw)
    if p['points'][0]['action']!=create_action() or p['points'][1]['action']!=watch_action():
        raise ValueError('WATCH_PROFILE_ACTIONS_DIFFER')
    (output/'candidate.json').write_bytes(raw)
    cases=[check_case(output/k,k) for k in ('transition','cap','identity')]
    result=dict(method='endpoint-data-watch-proof-suite-v1',profile_sha256=hashlib.sha256(raw).hexdigest(),
                kernel_connection=False,product_started=False,traffic_generated=False,
                cases=cases,passed=all(c['passed'] for c in cases))
    (output/'proof-suite.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();r=check(a.output);print(json.dumps(r));raise SystemExit(not r['passed'])
