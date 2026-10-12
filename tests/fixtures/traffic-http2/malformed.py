"""Opt-in HTTP/2 origin bounds/replay/reset checks; dedicated runtime only."""
import base64,hashlib,json,socket,ssl,sys,time,uuid
from trafficlab.application_wire import SERVER_NAME,request,verify_response
from trafficlab.http_two import H2Client
from trafficlab.protocol import json_bytes
from trafficlab.schedule import origin_metrics

binding=json.load(sys.stdin);secret=bytes.fromhex(binding['secret'])
for name in ('wrong-path','wrong-MIME','duplicate-MIME','oversized-header','oversized-body',
             'too-many-streams','RST-stream','replay','sequence-window'):
    job={**binding,'run_id':'http2-malformed-'+uuid.uuid4().hex};flow_id=uuid.uuid4().hex
    identity=origin_metrics(job)['identity']['application'];payload=b'checked'
    value=request(secret,'http2',job['run_id'],flow_id,16 if name=='sequence-window' else 0,hashlib.sha256(payload).hexdigest())
    message=json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()})
    context=ssl.create_default_context(cadata=identity['tls_ca_pem']);context.set_alpn_protocols(['h2'])
    with socket.create_connection((binding['host'],42518),timeout=2) as plain:
        with context.wrap_socket(plain,server_hostname=SERVER_NAME) as sock:
            assert hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()==identity['tls_certificate_sha256']
            client=H2Client(sock,False)
            if name in ('replay','sequence-window'):
                if name=='replay':verify_response(secret,value,client.exchange(message))
                try:client.exchange(message)
                except (EOFError,ConnectionResetError,ssl.SSLEOFError):pass
                else:raise AssertionError('Replay/window query accepted')
            else:
                headers=[(':method','POST'),(':scheme','https'),(':authority',SERVER_NAME),
                         (':path','/other' if name=='wrong-path' else '/testlab'),
                         ('content-type','application/octet-stream' if name=='wrong-MIME' else 'application/json')]
                if name=='duplicate-MIME':headers.append(('content-type','application/json'))
                if name=='oversized-header':headers.append(('large','x'*8192))
                streams=[]
                for _ in range(17 if name=='too-many-streams' else 1):
                    stream=client.conn.get_next_available_stream_id();streams.append(stream)
                    client.conn.send_headers(stream,headers)
                if name=='RST-stream':client.conn.reset_stream(streams[0])
                elif name!='too-many-streams':client.conn.send_data(streams[0],b'x'*8210 if name=='oversized-body' else message,end_stream=True)
                sock.sendall(client.conn.data_to_send())
                try:
                    while sock.recv(16384):pass
                except (ConnectionResetError,ssl.SSLEOFError):pass
    for _ in range(30):
        remote=origin_metrics(job)
        if remote['runtime_connections']==0:break
        time.sleep(.05)
    assert remote['runtime_connections']==0 and remote['proxy_connections']==0,(name,'not idle')
    if name=='replay':assert remote['application_flows'][flow_id]['transactions']==1
    else:assert not remote.get('application_flows'),(name,'authenticated invalid request')
    print(json.dumps({'component_malformed':name,'application':'http2','rejected':True,'signed_idle':True}),flush=True)
