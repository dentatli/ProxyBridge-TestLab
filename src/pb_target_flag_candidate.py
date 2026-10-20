"""Non-runnable bounded flag observer candidate; never enables or runs a target."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def bounded(point, counter, body):
    stop='bd2; bd3; bd4;'
    return ('r @'+counter+' = @'+counter+' + 1; .if (@'+counter+' >= 0x10) { '+stop+
        ' .printf "PBFG_LIMIT point='+str(point)+' capture=incomplete\\n"; } .else { '+body+' }; gc;')


def candidate():
    create='.if ($vvalid(@r14,0x10) == 1) { .if ((wo(@r14) == 2) and (wo(@r14+2) == 0xd9a4)) { bd2; .if (($vvalid(@rax+0x1e0,0x14) == 1) and (@rax != 0)) { r @$t1 = @rax; r @$t2 = @rdi; .printf "PBFG TRACK ep=%p record=%p context=%p size=%I64x refs=%x\\n", @rdi, @rax, poi(@rax+0x1e0), poi(@rax+0x1e8), dwo(@rax+0x1f0); } .else { bd3; bd4; .printf "PBFG_UNREADABLE event=TRACK capture=incomplete\\n"; } } }'
    setter='.if (@$t2 != 0) { .if (@rbx == @$t2) { bd3; .if (($vvalid(@rbx+0x30,8) == 1) and ($vvalid(@rbx+0x1c0,8) == 1)) { .printf "PBFG SET_PRE thread=%p ep=%p flags30=%x flags34=%x record=%p classify_raw=%x arg12_raw=%x arg13_raw=%x arg15_raw=%x\\n", @$thread, @rbx, dwo(@rbx+0x30), dwo(@rbx+0x34), poi(@rbx+0x1c0), @edi, @r12d, @r13d, @r15d; } .else { bd2; bd4; .printf "PBFG_UNREADABLE event=SET_PRE capture=incomplete\\n"; }; .printf "PBFG STACK_BEGIN\\n"; k 8; .printf "PBFG STACK_END\\n"; } }'
    accept='.if ($vvalid(@rbp-0x7c,4) == 1) { .if ((wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)) { bd2; bd3; bd4; .if ($vvalid(@rbp-0x28,8) == 1) { .printf "PBFG RETRIEVE ep=%p nbl=%p status=%x output_raw=%p\\n", @rdi, @rbx, @eax, poi(@rbp-0x28); } .else { .printf "PBFG_UNREADABLE event=RETRIEVE capture=incomplete\\n"; } } }'
    targets=['tcpip!AlepCreateRedirectRecord+0x396','tcpip!WfpTlShimInspectRecvTcpDatagram+0x190','tcpip!WfpAleAuthorizeAccept+0xcaf']
    return dict(method='bounded-flag-observer-candidate-v1',status='DISABLED_CANDIDATE_CODE_REVIEWED_NOT_RUNNABLE',
        load_allowed=False,automatic_enable=False,automatic_disable=True,
        registered_point_ids=[2,3,4,5,6],active_point_ids=[],
        proposed_active_point_ids=[2,3,4],required_inactive_point_ids=[5,6],
        raw_hit_limit_per_point=16,max_total_raw_hits=48,max_selected_snapshots_per_point=1,
        stack_count_max=1,stack_frames_max=8,
        points=[dict(id=i,target=t,action=bounded(i,'$t'+str(i+1),body)) for i,t,body in zip([2,3,4],targets,[create,setter,accept])],
        limitations=['Caps bound debugger hits, not wall-clock pause time.',
            'Cap exhaustion disables all three points and means incomplete coverage.',
            'No unselected-memory warning output before tuple or endpoint identification.',
            'One setter snapshot does not prove a transition or identify every writer.',
            'No new workload authorized by this candidate; previous incomplete run remains unresolved.'])


def registration_stage():
    p=candidate()
    lines=['bd'+str(i) for i in range(2,7)]+['bc2','bc3','bc4']
    for point in p['points']:
        escaped=point['action'].replace('\\','\\\\').replace('"','\\"')
        lines+=['bp'+str(point['id'])+' '+point['target']+' "'+escaped+'"','bd'+str(point['id'])]
    lines+=['r @$t'+str(i)+' = 0' for i in range(1,6)]
    lines+=['.printf "PBFG_DISABLED_READY\\n"']
    # Pin instruction bytes, but do not treat them as a boot/registration proof.
    guard='(wo(tcpip!AlepCreateRedirectRecord+0x396) == 0x65eb) and (dwo(tcpip!WfpTlShimInspectRecvTcpDatagram+0x190) == 0x304b81f0) and (dwo(tcpip!WfpTlShimInspectRecvTcpDatagram+0x194) == 0x00200000) and (wo(tcpip!WfpAleAuthorizeAccept+0xcaf) == 0xc085)'
    return '.if ('+guard+') { '+'; '.join(lines)+'; } .else { .printf "PBFG_CODE_MISMATCH_NO_CHANGE\\n"; }\n'


def fixture(action, kind):
    action=re.sub(r'\$vvalid\(([^()]+)\)',lambda m:'0' if kind=='unreadable' and m[1] not in ('@r14,0x10','@rbp-0x7c,4') else '1',action)
    action=re.sub(r'\bwo\(([^()]+)\)',lambda m:'0' if kind=='nonselected' else ('2' if m[1]=='@r14' else '0xda84' if m[1]=='@rbp-0x7c' else '0xd9a4'),action)
    action=re.sub(r'\b(?:poi|dwo)\([^()]+\)','0x1000',action)
    action=re.sub(r'@(?:\$thread|r14|rdi|rax|rbx|rbp|eax|edi|r12d|r13d|r15d)\b','0x1000',action)
    if any(x in action for x in ('$vvalid','poi(','wo(')):raise ValueError('UNSAFE_FIXTURE')
    if not action.endswith('gc;'):raise ValueError('GC_SUFFIX')
    return action[:-3]+'.printf "PBFG_PARSER_END\\n";'


def check(output, profile=None):
    p=candidate() if profile is None else profile
    output.mkdir(parents=True,exist_ok=False)
    raw=json.dumps(p,indent=2)+'\n';(output/'candidate.json').write_text(raw,encoding='utf-8',newline='\n')
    result=dict(method='cdb-safe-bounded-flag-candidate-v1',kernel_connection=False,product_started=False,traffic_generated=False,cases=[])
    debugger=Path(r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe')
    symbols=output/'empty-symbols';symbols.mkdir()
    for kind in ('selected','nonselected','unreadable','limit'):
        commands=[]
        for pt in p['points']:
            n=pt['id'];counter='$t'+str(n+1)
            commands += ['bp'+str(n)+' @$ip+0x'+str(n)+'0 "gc"',
                'r @$t1 = 0; r @$t2 = '+('0' if kind=='nonselected' else '0x1000'),
                'r @'+counter+' = '+('0xf' if kind=='limit' else '0'),
                '.printf "PBFG_ID_'+str(n)+'\\n"',fixture(pt['action'],kind),
                '.printf "PBFG_ID_END_'+str(n)+'\\n"',
                '.printf "PBFG_STATE_BEGIN_'+str(n)+'\\n"','.bpcmds',
                '.printf "PBFG_STATE_END_'+str(n)+'\\n"']
            # All bd commands refer to actual safe dummy breakpoints.
        commands=['bp2 @$ip+0x20 "gc"','bp3 @$ip+0x30 "gc"','bp4 @$ip+0x40 "gc"']+commands+['q']
        path=output/(kind+'.wdbg');path.write_text('\n'.join(commands)+'\n',encoding='ascii',newline='\n')
        c=subprocess.run([str(debugger),'-sins','-y',str(symbols),'-cf',str(path),r'C:\Windows\System32\cmd.exe','/d','/c','exit','0'],capture_output=True,timeout=20,creationflags=0x08000000)
        (output/(kind+'.stdout.txt')).write_bytes(c.stdout);(output/(kind+'.stderr.txt')).write_bytes(c.stderr)
        text=(c.stdout+c.stderr).decode('utf-8',errors='replace');lines=[l.strip() for l in text.splitlines()]
        checks=[];disable_checks=[]
        for pt in p['points']:
            n=pt['id'];start=lines.index('PBFG_ID_'+str(n));end=lines.index('PBFG_ID_END_'+str(n))
            part=lines[start+1:end];actual=[l for l in part if l.startswith(('PBFG ','PBFG_'))]
            checks.append('PBFG_PARSER_END' in part and (any(l.startswith('PBFG_LIMIT') for l in actual) if kind=='limit' else
                any(l.startswith('PBFG_UNREADABLE') for l in actual) if kind=='unreadable' else
                len(actual)==1 if kind=='nonselected' else any(l.startswith('PBFG ') for l in actual)))
            state_start=lines.index('PBFG_STATE_BEGIN_'+str(n));state_end=lines.index('PBFG_STATE_END_'+str(n))
            disabled=any(re.fullmatch(r'bd\s+'+str(n)+r';',l) for l in lines[state_start+1:state_end])
            disable_checks.append(disabled==(kind!='nonselected'))
        passed=c.returncode==0 and all(checks+disable_checks) and not re.search(r'(?i)(syntax error|extra character error|couldn.t resolve)',text)
        result['cases'].append(dict(name=kind,passed=passed,checks=checks,disable_checks=disable_checks,exit_code=c.returncode))
    result['passed']=all(c['passed'] for c in result['cases'])
    (output/'parser-check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();r=check(a.output);print(json.dumps(r));raise SystemExit(not r['passed'])
