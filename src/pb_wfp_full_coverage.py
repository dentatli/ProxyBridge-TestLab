"""Conservative coverage gate for owned baseline sockets, not a root-cause verdict."""
import argparse
import csv
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

TCP='2f07e2ee-15db-40f1-90ef-9d7ba282188a'
AFD='e53c6823-7bb8-44bb-90dc-3f86090d48a6'
WFP='00e7ee66-5b24-5c41-22cb-af98f63e2f90'

def read(path): return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def raw(event, name):
    p=event.get('properties',{}).get(name,{})
    if p.get('error')!=0: raise ValueError('MISSING_DECODED_PROPERTY: '+name)
    return bytes.fromhex(p['hex'])
def number(event, name):
    data=raw(event,name)
    if len(data) not in (1,2,4,8): raise ValueError('NUMERIC_PROPERTY_WIDTH: '+name)
    return int.from_bytes(data,'little')
def sockaddr(event,name):
    data=raw(event,name)
    if len(data)!=16 or data[:2]!=b'\x02\x00': raise ValueError('NON_IPV4_SOCKADDR: '+name)
    return '.'.join(str(x) for x in data[4:8]),int.from_bytes(data[2:4],'big')
def ownership(path):
    if Path(path).stat().st_size>32*1024*1024: raise ValueError('WFP_STATE_TOO_LARGE')
    # netsh may emit adjacent wfpstate and firewallState elements. Parse the
    # complete fragment document, rather than dropping its trailing content.
    text=Path(path).read_text(encoding='utf-8-sig')
    if re.search(r'<!\s*(?:DOCTYPE|ENTITY)\b',text,re.IGNORECASE):raise ValueError('WFP_STATE_DTD_NOT_ALLOWED')
    declaration=re.match(r'\A\s*(<\?xml\s[^?]*\?>)',text)
    if declaration:
        ET.fromstring(declaration.group(1)+'<declarationCheck/>')
        text=text[declaration.end():]
    document=ET.fromstring('<netshFragments>'+text+'</netshFragments>')
    roots=list(document)
    if (document.text or '').strip() or any((node.tail or '').strip() for node in roots):raise ValueError('WFP_STATE_EXTRA_TEXT')
    names=[node.tag.split('}')[-1] for node in roots]
    if names not in (['wfpstate'],['wfpstate','firewallState']):raise ValueError('WFP_STATE_ROOTS_INVALID')
    tree=roots[0];result={}
    for node in tree.iter():
        children={c.tag.split('}')[-1]:''.join(c.itertext()).strip() for c in node}
        if 'calloutKey' not in children or 'calloutId' not in children:continue
        key=children['calloutKey'].strip('{}').lower()
        if key in {'7c1b6a10-2e44-4e8b-9e21-0f9a5d3c1a0'+str(n) for n in range(3,7)}:
            text=children['calloutId'];identifier=int(text,16 if text.lower().startswith('0x') else 10)
            if identifier in result and result[identifier]!=key:raise ValueError('CALLOUT_ID_AMBIGUOUS')
            result[identifier]=key
    if not result:raise ValueError('OWN_CALLOUT_IDS_NOT_OBSERVED')
    return result

def evaluate(events, summary, baseline, cli_pid, own_ids):
    errors=[];matches=[]
    if (summary.get('method')!='saved-wfp-afd-etl-v1' or summary.get('clock_type')!=1 or summary.get('qpc_frequency',0)<=0 or
        any(summary.get(k)!=0 for k in ('events_lost','buffers_lost','process_trace_status','close_trace_status','write_error')) or summary.get('bound_exceeded')):
        errors.append('BASELINE_TRACE_CLOCK_LOSS_OR_DECODE_BOUND')
    phase=read(baseline/'phase-receipt.json');client=read(baseline/'client-launch.json')
    if phase['id']!='baseline' or phase['requested_connections']!=4 or phase['client_pid']!=client['pid'] or phase['error'] or phase['client_forced_stop'] or phase['server_forced_stop'] or not phase['snapshot_complete']:
        errors.append('OWN_BASELINE_LIFECYCLE_INCOMPLETE')
    csv_bytes=(baseline/'client.csv').read_bytes()
    if len(csv_bytes)>4*1024*1024:raise ValueError('BASELINE_CSV_TOO_LARGE')
    rows=list(csv.DictReader(csv_bytes.decode('utf-16' if csv_bytes.startswith(b'\xff\xfe') else 'utf-8-sig').splitlines()))
    if len(rows)!=4 or any(r['Result']!='Succeeded' or int(r['SendBytes'])!=524288 or r['RemoteAddress']!='127.0.0.1:54122' for r in rows):errors.append('BASELINE_NATIVE_DATA_NOT_CONFIRMED')
    ports=[int(r['LocalAddress'].rsplit(':',1)[1]) for r in rows]
    if len(set(ports))!=4:errors.append('BASELINE_NATIVE_ENDPOINT_NOT_UNIQUE')
    low=phase['start_qpc_ms']*summary.get('qpc_frequency',0)/1000
    high=phase['end_qpc_ms']*summary.get('qpc_frequency',0)/1000
    scoped=[e for e in events if low<=e['qpc']<=high]
    for port in ports:
        applies=[];accepts=[]
        for e in scoped:
            try:
                if e['provider']==WFP and e.get('event_name')=='ApplyWritableLayerData' and e.get('decode_error')==0:
                    if sockaddr(e,'PrevLocalAddress')[1]==port and sockaddr(e,'PrevRemoteAddress')==('127.0.0.1',54122) and sockaddr(e,'ModifiedRemoteAddress')==('127.0.0.1',34010) and number(e,'CalloutId') in own_ids:
                        corr=raw(e,'CorrelationId').hex()
                        # NETIO TraceLogging metadata uses UINT64 (0x0a), not a GUID.
                        if len(corr)!=16 or int(corr,16)==0:raise ValueError('INVALID_UINT64_CORRELATION_ID')
                        applies.append((corr,number(e,'CalloutId')))
                if e['provider']==AFD and e['id'] in (1024,1027) and e['pid']==cli_pid and e.get('decode_error')==0:
                    if sockaddr(e,'Address')==('127.0.0.1',port) and number(e,'Status')==0:
                        number(e,'CurrentBacklog')  # Presence/decoding required; value is not a capacity verdict.
                        pair=(number(e,'Endpoint'),number(e,'AcceptEndpoint'))
                        if all(pair):accepts.append(pair)
            except (KeyError,ValueError):continue
        apply_pairs=set(applies);accept_pairs=set(accepts)
        corr_ids={p[0] for p in apply_pairs}
        classify=[]
        for e in scoped:
            try:
                if e['provider']==WFP and e.get('event_name')=='ConnectRedirectClassify' and raw(e,'CorrelationId').hex() in corr_ids and number(e,'Protocol')==6:
                    endpoint=number(e,'TransportEndpointHandle')
                    if endpoint:classify.append(endpoint)
            except (KeyError,ValueError):continue
        if len(apply_pairs)!=1:errors.append('OWN_WFP_APPLY_MATCH_NOT_UNIQUE: '+str(port))
        if len(set(classify))!=1:errors.append('OWN_WFP_CLASSIFY_ENDPOINT_NOT_UNIQUE: '+str(port))
        if len(accept_pairs)!=1:errors.append('OWN_AFD_ACCEPT_ENDPOINT_NOT_UNIQUE: '+str(port))
        matches.append(dict(native_port=port,wfp_apply=list(sorted(apply_pairs)),wfp_transport_endpoint=list(sorted(set(classify))),afd_accept=list(sorted(accept_pairs))))
    # WPP only emits on failure; silent successful baseline is expected. Do not require a fabricated error.
    tcp_owned=[e for e in scoped if e['provider']==TCP and e['pid']==client['pid'] and e['id'] in (1017,1033)]
    if not tcp_owned:errors.append('OWN_TCP_SETUP_NOT_OBSERVED')
    return dict(method='owned-wfp-afd-baseline-coverage-v1',status='COVERAGE_CONFIRMED' if not errors else 'COVERAGE_INCOMPLETE',
                errors=errors,owned_client_pid=client['pid'],owned_cli_pid=cli_pid,matched=matches,
                identity_between_AFD_and_WFP_proven=False,private_record_transfer_free_observed=False,
                wpp_success_emission_required=False,root_cause_proven=False)

def main():
    p=argparse.ArgumentParser();p.add_argument('--events',type=Path,required=True);p.add_argument('--summary',type=Path,required=True)
    p.add_argument('--baseline',type=Path,required=True);p.add_argument('--cli-pid',type=int,required=True);p.add_argument('--state',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    try:
        if args.events.stat().st_size>512*1024*1024:raise ValueError('EVENTS_TOO_LARGE')
        with args.events.open(encoding='utf-8') as f:events=[json.loads(line) for line in f]
        result=evaluate(events,read(args.summary),args.baseline,args.cli_pid,ownership(args.state))
    except Exception as exc:result=dict(status='COVERAGE_INCOMPLETE',errors=[type(exc).__name__+': '+str(exc)],root_cause_proven=False)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(status=result['status'],errors=result['errors'])))
    return 0 if result['status']=='COVERAGE_CONFIRMED' else 1
if __name__=='__main__':raise SystemExit(main())
