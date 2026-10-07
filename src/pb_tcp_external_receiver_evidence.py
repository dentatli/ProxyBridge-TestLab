"""Strict owned Linux CTS phase evidence, without pretending cross-host clocks agree."""
import hashlib
import ipaddress
import json
import uuid
from pb_tcp_connections_report import read, jsonl, ENGINE

RECEIVER = '9df9708a718ab91b08d54d28676b2e96c1201e2f0bd5c81a9e40712801841011'
PAYLOAD = '164092c58aab2e780e51550c1921baa0aa0c1c1f728e7ddf33a449fa992edef1'

def require(condition, reason):
    if not condition: raise ValueError(reason)

def canonical_guid(value):
    return str(uuid.UUID(value))

def receiver_rows(folder, phase, policy):
    remote=folder/'linux-receiver'
    start=read(folder/'linux-start.json'); stop=read(folder/'linux-stop.json')
    receipt=read(remote/'collection-receipt.json'); collection=read(remote/'remote-collection.json')
    raw=(remote/'receiver.jsonl').read_bytes()
    run_id=phase['receiver_run_id']
    for entry, action in ((start,'Start'),(stop,'Stop'),(receipt,'Collect')):
        require(entry['phase']==action and entry['run_id']==run_id and entry['ssh_exit_code']==0 and
                entry['receiver_sha256']==policy['receiver_sha256']==RECEIVER and
                entry['host_key_fingerprint']==policy['host_key_fingerprint'], 'LINUX_LIFECYCLE_BINDING_DIFFERS')
    require(start['result']['status']=='RECEIVER_LISTENING' and
            stop['result']['status']=='RECEIVER_SERVICE_STOPPED' and
            collection['sha256']==hashlib.sha256(raw).hexdigest() and collection['bytes']==len(raw) and
            receipt['result']==collection, 'LINUX_COLLECTION_OR_STOP_DIFFERS')
    require(collection['status']=='RECEIVER_EVIDENCE_COLLECTED' and
            collection['service']['properties']['ActiveState']=='inactive' and
            collection['unit']==start['result']['unit']==stop['result']['unit']=='pb-testlab-cts-'+run_id+'.service',
            'LINUX_UNIT_OR_SERVICE_DIFFERS')
    exit_record=collection['exit_receipt']
    require('exit_receipt' not in collection['service'] or collection['service']['exit_receipt']==exit_record,
            'LINUX_EXIT_RECEIPTS_DIFFER')
    require(exit_record['run_id']==run_id and exit_record['receiver_sha256']==RECEIVER and
            exit_record['service_result']=='success' and exit_record['exit_code']=='exited' and
            exit_record['exit_status']=='0', 'LINUX_EXIT_NOT_CLEAN')
    events=[json.loads(line) for line in raw.decode('utf-8').splitlines() if line]
    require(events and [e['sequence'] for e in events]==list(range(1,len(events)+1)) and
            len({e['process_id'] for e in events})==1 and all(e['run_id']==run_id and e['schema_version']==1 and
            e['method']=='cts-2.0.3.9-push-receiver-v1' for e in events) and
            all(a['monotonic_ns']<=b['monotonic_ns'] for a,b in zip(events,events[1:])), 'LINUX_JOURNAL_SCOPE_DIFFERS')
    listens=[e for e in events if e['event']=='LISTENING']; stops=[e for e in events if e['event']=='STOPPED']
    require(len(listens)==len(stops)==1 and events[0]==listens[0] and events[-1]==stops[0], 'LINUX_CAPTURE_INCOMPLETE')
    listener=listens[0]; final=stops[0]; count=phase['requested_connections']
    require(listener==start['result']['listener'] and listener['receiver_sha256']==RECEIVER and
            listener['cts_client_sha256']==ENGINE and listener['bind_ipv4']==policy['host'] and
            listener['allowed_sources']==[policy['allowed_source']] and listener['port']==54122 and
            listener['transfer_bytes']==524288 and listener['max_connections']==count and
            listener['max_total_connections']==count and listener['max_duration_seconds']==720,
            'LINUX_LISTENER_POLICY_DIFFERS')
    require(final['status']=='CAPTURE_COMPLETE' and all(final[k]==0 for k in
            ('failed','rejected','forced_flow_count','active_connections','remaining_handlers','unexpected_errors')),
            'LINUX_TRANSFER_OR_CLEANUP_INCOMPLETE')
    accepted=[e for e in events if e['event']=='ACCEPTED']; verified=[e for e in events if e['event']=='TRANSFER_VERIFIED']
    ended=[e for e in events if e['event']=='FLOW_ENDED']
    require(len(accepted)==len(verified)==len(ended)==final['accepted']==final['completed'] and
            not any(e['event'] in ('TRANSFER_FAILED','REJECTED','FIXTURE_ERROR') for e in events), 'LINUX_FLOW_COUNT_DIFFERS')
    index={canonical_guid(e['connection_id']):e for e in verified}
    first={canonical_guid(e['connection_id']):e for e in accepted}; last={canonical_guid(e['connection_id']):e for e in ended}
    require(len(index)==len(first)==len(last)==len(verified) and set(index)==set(first)==set(last), 'LINUX_GUID_DUPLICATE_OR_MISSING')
    rows=[]; peers=set()
    for guid, e in index.items():
        a=first[guid]; z=last[guid]
        require(a['sequence']<e['sequence']<z['sequence'] and a['local']==e['local'] and a['peer']==e['peer'] and
                e['local']==[policy['host'],54122] and e['peer'][0]==policy['allowed_source'] and
                type(e['peer'][1]) is int and 0<e['peer'][1]<=65535 and a['requested_bytes']==524288,
                'LINUX_FLOW_IDENTITY_DIFFERS')
        require(e['bytes_received']==524288 and e['payload_sha256']==PAYLOAD and e['completion_sent'] is True and
                e['close_status'] in ('EOF','RESET_AFTER_COMPLETION'), 'LINUX_DATA_NOT_VERIFIED')
        peers.add(tuple(e['peer']))
        # Internal evidence interface only: original Linux journal remains the source, no fabricated CSV is saved.
        rows.append(dict(ConnectionId=e['connection_id'],Result='Succeeded',RecvBytes=str(e['bytes_received'])))
    require(len(peers)==len(rows), 'LINUX_PEER_NOT_UNIQUE')
    return rows

def policy_for(path):
    build=read(path.parent/'diagnostic-build.json')
    policy=build['external_receiver_policy']; manifest=read(path/'comparison-manifest.json')
    require(policy['method']=='local-linux-receiver-pair-v1' and policy['cases']==['local','linux'] and
            policy['diagnostic_only'] is True and policy['performance_comparable'] is False and
            policy['route_case']=='original' and policy['port']==54122 and policy['transfer_bytes']==524288 and
            policy['receiver_sha256']==RECEIVER, 'EXTERNAL_POLICY_DIFFERS')
    require(str(ipaddress.IPv4Address(policy['host']))==policy['host'] and
            not ipaddress.ip_address(policy['host']).is_loopback and policy['host']!='0.0.0.0', 'EXTERNAL_HOST_INVALID')
    case=manifest['receiver_case']
    require(case in policy['cases'] and manifest['external_receiver_policy']==policy and
            read(path/'proxy/benchmark-config.json')['external_receiver_policy']==policy,
            'EXTERNAL_CASE_BINDING_DIFFERS')
    return policy, case
