"""Opt-in partial/malformed streaming RPCs must never acquire completed status."""
import base64,hashlib,json,socket,ssl,struct,sys,time,uuid
from trafficlab.application_wire import SERVER_NAME,request
from trafficlab.grpc_streaming import PATHS
from trafficlab.http_two import H2Client,grpc_encode
from trafficlab.protocol import json_bytes
from trafficlab.schedule import origin_metrics

binding=json.load(sys.stdin);secret=bytes.fromhex(binding['secret'])
for mode,path in PATHS.items():
    for name in ('compressed','declared-length-overflow','truncated-frame','too-few','too-many','replay','wrong-HMAC','oversized-payload','RST-stream'):
        job={**binding,'run_id':'grpc-malformed-'+uuid.uuid4().hex};flow_id=uuid.uuid4().hex
        identity=origin_metrics(job)['identity']['application']
        payload=b'x'*(1025 if name=='oversized-payload' else 512)
        value=request(secret,'grpc',job['run_id'],flow_id,0,hashlib.sha256(payload).hexdigest())
        if name=='wrong-HMAC':value['proof']='0'*64
        frame=grpc_encode(json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()}))
        if name=='compressed':body=b'\1'+frame[1:]
        elif name=='declared-length-overflow':body=b'\0'+struct.pack('!I',8300)
        elif name=='truncated-frame':body=frame[:-1]
        elif name=='too-few':body=b'' if mode=='server-stream' else frame
        elif name=='too-many':body=frame*(2 if mode=='server-stream' else 4)
        elif name=='replay':body=frame*2
        else:body=frame
        context=ssl.create_default_context(cadata=identity['tls_ca_pem']);context.set_alpn_protocols(['h2'])
        with socket.create_connection((binding['host'],42519),timeout=2) as plain:
            with context.wrap_socket(plain,server_hostname=SERVER_NAME) as sock:
                assert hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()==identity['tls_certificate_sha256']
                client=H2Client(sock,True);stream=client.conn.get_next_available_stream_id()
                client.conn.send_headers(stream,[(':method','POST'),(':scheme','https'),(':authority',SERVER_NAME),
                    (':path',path),('content-type','application/grpc+proto'),('te','trailers')])
                if name=='RST-stream':client.conn.reset_stream(stream)
                else:client.conn.send_data(stream,body,end_stream=True)
                sock.sendall(client.conn.data_to_send())
                try:
                    while sock.recv(16384):pass
                except (ConnectionResetError,ssl.SSLEOFError):pass
        for _ in range(30):
            remote=origin_metrics(job)
            if remote['runtime_connections']==0:break
            time.sleep(.05)
        assert remote['runtime_connections']==0 and remote['proxy_connections']==0,(mode,name,'runtime not idle')
        flow=remote.get('application_flows',{}).get(flow_id,{})
        assert flow.get('grpc_rpc_count',0)==0,(mode,name,'malformed RPC counted as complete')
        print(json.dumps({'component_malformed':name,'mode':mode,'completed_RPCs':0,'signed_idle':True}),flush=True)
