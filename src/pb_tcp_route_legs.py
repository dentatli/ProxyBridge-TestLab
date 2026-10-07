"""Link accepted Core sockets to upstream TCP and SOCKS status without payloads."""
import re, socket, struct
from pb_tcp_redirect_context_report import parse_queries

FIELDS=('stage incoming_socket upstream_socket relay_pid thread qpc frequency api_return api_error '
        'native_family native_v4 native_port native_error upstream_local_family upstream_local_v4 upstream_local_port upstream_local_error '
        'upstream_peer_family upstream_peer_v4 upstream_peer_port upstream_peer_error').split()
def ip(value):return socket.inet_ntoa(struct.pack('<I',value))

def evaluate(text, report, owned_phases):
    rows=[]
    for line in text.splitlines():
        if '[ROUTELEG]' not in line:continue
        pairs=[t.split('=',1) for t in line.split('[ROUTELEG]',1)[1].split()]
        if any(len(p)!=2 for p in pairs) or [p[0] for p in pairs]!=FIELDS:raise ValueError('ROUTE_LEG_FIELDS_INVALID')
        r={k:(v if k=='stage' else int(v)) for k,v in pairs}
        if r['stage'] not in ('proxy-connect','socks-handshake') or any(v<0 for k,v in r.items() if k not in ('stage','api_return')) or r['frequency']<=0:raise ValueError('ROUTE_LEG_VALUES_INVALID')
        rows.append(r)
    if len(rows)>4000:raise ValueError('ROUTE_LEG_LIMIT_EXCEEDED')
    queries=parse_queries(text);metrics={m['query_seq']:m for m in report['kernel_timing']['metrics']}
    phases={p['id']:p for p in owned_phases}
    by_seq={q['seq']:[] for q in queries};matches=[]
    for r in rows:
        possible=[]
        for q in queries:
            phase=phases[metrics[q['seq']]['phase_id']]
            if (q['category']=='IPV4_CONTEXT_AVAILABLE' and r['incoming_socket']==q['socket'] and r['relay_pid']==q['relay_pid'] and
                r['native_family']==2 and r['native_error']==0 and ip(r['native_v4'])==q['peer_addr'] and r['native_port']==q['peer_port'] and
                r['frequency']==q['frequency'] and q['qpc']<=r['qpc'] and r['qpc']*1000/r['frequency']<=phase['end_qpc_ms']):possible.append(q)
        if len(possible)!=1:raise ValueError('ROUTE_LEG_QUERY_MATCH_NOT_UNIQUE')
        q=possible[0];by_seq[q['seq']].append(r)
        matches.append(dict(query_seq=q['seq'],phase_id=metrics[q['seq']]['phase_id'],**r))
    for q in queries:
        leg=sorted(by_seq[q['seq']],key=lambda r:r['qpc'])
        if q['category']!='IPV4_CONTEXT_AVAILABLE':
            if leg:raise ValueError('ROUTE_LEG_AFTER_FAILED_CONTEXT')
            continue
        if [r['stage'] for r in leg]!=['proxy-connect','socks-handshake']:raise ValueError('ROUTE_LEG_STAGE_SET_INCOMPLETE')
        if leg[0]['upstream_socket']!=leg[1]['upstream_socket']:raise ValueError('ROUTE_UPSTREAM_SOCKET_DIFFERS')
        for r in leg:
            if r['api_return']!=0 or any(r[k]!=0 for k in ('upstream_local_error','upstream_peer_error')) or r['upstream_local_family']!=2 or r['upstream_peer_family']!=2 or r['upstream_local_port']<=0 or r['upstream_peer_port']!=54123:
                raise ValueError('ROUTE_UPSTREAM_OR_HANDSHAKE_FAILED')
        for key in ('upstream_local_v4','upstream_local_port','upstream_peer_v4','upstream_peer_port'):
            if leg[0][key]!=leg[1][key]:raise ValueError('ROUTE_UPSTREAM_TUPLE_CHANGED')
    return dict(records=len(rows),matched=matches,payload_recorded=False,
        owned_upstream_to_fixture_trace_correlation_pending=True,fixture_to_target_trace_correlation_pending=True)
