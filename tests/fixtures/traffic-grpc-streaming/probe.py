"""Opt-in official grpcio SDK interop and cancel during an unfinished bidi RPC."""
import base64,hashlib,json,queue,socket,ssl,struct,sys,threading,time,uuid
from trafficlab.application_wire import SERVER_NAME,request,verify_response
from trafficlab.grpc_streaming import PATHS
from trafficlab.http_two import grpc_encode,grpc_decode
from trafficlab.protocol import json_bytes
from trafficlab.schedule import origin_metrics
import grpc

binding=json.load(sys.stdin);secret=bytes.fromhex(binding['secret'])
def serialize(raw):return grpc_encode(raw)[5:]
def deserialize(raw):return json.loads(grpc_decode(b'\0'+struct.pack('!I',len(raw))+raw))
def inputs(job,count):
    flow_id=uuid.uuid4().hex;payloads=[bytes((index+seq)%256 for index in range(512)) for seq in range(count)]
    values=[request(secret,'grpc',job['run_id'],flow_id,seq,hashlib.sha256(payload).hexdigest()) for seq,payload in enumerate(payloads)]
    messages=[json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()}) for value,payload in zip(values,payloads)]
    return flow_id,values,payloads,messages
def verify(reply,value,payload,mode,index):
    assert reply['grpc_mode']==mode and type(reply['grpc_message_index']) is int and reply['grpc_message_index']==index and reply['grpc_message_count']==3
    assert base64.b64decode(reply['payload'])==payload
    return verify_response(secret,value,reply)
def idle(job):
    for _ in range(40):
        remote=origin_metrics(job)
        if remote['runtime_connections']==0:break
        time.sleep(.1)
    assert remote['runtime_connections']==0 and remote['proxy_connections']==0
    return remote

for mode,path in PATHS.items():
    job={**binding,'run_id':'sdk-grpc-stream-'+uuid.uuid4().hex}
    identity=origin_metrics(job)['identity']['application']
    # grpcio verifies CA/name. A separate native preflight verifies the endpoint leaf pin.
    context=ssl.create_default_context(cadata=identity['tls_ca_pem']);context.set_alpn_protocols(['h2'])
    with socket.create_connection((binding['host'],42519),timeout=2) as plain:
        with context.wrap_socket(plain,server_hostname=SERVER_NAME) as sock:
            assert sock.selected_alpn_protocol()=='h2'
            assert hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()==identity['tls_certificate_sha256']
    flow_id,values,payloads,messages=inputs(job,1 if mode=='server-stream' else 3)
    with grpc.secure_channel(binding['host']+':42519',grpc.ssl_channel_credentials(identity['tls_ca_pem'].encode()),
        options=[('grpc.ssl_target_name_override',SERVER_NAME),('grpc.max_receive_message_length',8192),('grpc.max_send_message_length',8192)]) as channel:
        if mode=='client-stream':
            rpc=channel.stream_unary(path,request_serializer=serialize,response_deserializer=deserialize)
            aggregate,call=rpc.with_call(iter(messages),timeout=5)
            assert set(aggregate)=={'messages'};replies=aggregate['messages']
        elif mode=='server-stream':
            rpc=channel.unary_stream(path,request_serializer=serialize,response_deserializer=deserialize)
            call=rpc(messages[0],timeout=5);replies=list(call)
        else:
            rpc=channel.stream_stream(path,request_serializer=serialize,response_deserializer=deserialize)
            # Release each next request only after its preceding response is verified.
            outgoing=queue.Queue();outgoing.put(messages[0])
            def requests():
                while True:
                    item=outgoing.get(timeout=5)
                    if item is None:return
                    yield item
            call=rpc(requests(),timeout=5);replies=[]
            try:
                for index,reply in enumerate(call):
                    verify(reply,values[index],payloads[index],mode,index);replies.append(reply)
                    outgoing.put(messages[index+1] if index+1<3 else None)
            finally:outgoing.put(None)
        assert call.code()==grpc.StatusCode.OK and len(replies)==3
        peers=[verify(reply,values[0 if mode=='server-stream' else index],payloads[0 if mode=='server-stream' else index],mode,index)
               for index,reply in enumerate(replies)]
        assert peers[0]==peers[1]==peers[2]
    remote=idle(job);flow=remote['application_flows'][flow_id]
    assert flow['grpc_mode']==mode and flow['grpc_rpc_count']==1 and flow['grpc_receipts']==3
    assert flow['grpc_request_messages']==len(messages) and flow['transactions']==len(messages)
    assert flow['grpc_response_messages']==(1 if mode=='client-stream' else 3) and flow['peer']==peers[0]
    print(json.dumps({'component_sdk':'grpcio '+grpc.__version__,'mode':mode,'verified':True,'signed_idle':True,
                      'bidi_reply_before_next_request':mode=='bidi-stream','CA_name':True,'separate_leaf_pin_preflight':True}),flush=True)

job={**binding,'run_id':'sdk-grpc-midstream-cancel-'+uuid.uuid4().hex}
identity=origin_metrics(job)['identity']['application'];flow_id,values,payloads,messages=inputs(job,3)
stop=threading.Event()
def partial_requests():
    yield messages[0]
    stop.wait(5)
with grpc.secure_channel(binding['host']+':42519',grpc.ssl_channel_credentials(identity['tls_ca_pem'].encode()),
    options=[('grpc.ssl_target_name_override',SERVER_NAME)]) as channel:
    rpc=channel.stream_stream(PATHS['bidi-stream'],request_serializer=serialize,response_deserializer=deserialize)
    call=rpc(partial_requests(),timeout=5)
    try:
        verify(next(call),values[0],payloads[0],'bidi-stream',0)
        assert call.cancel() and call.code()==grpc.StatusCode.CANCELLED
    finally:stop.set()
remote=idle(job);flow=remote['application_flows'][flow_id]
assert flow['transactions']==1 and flow['grpc_request_messages']==1 and flow['grpc_response_messages']==1
assert flow.get('grpc_rpc_count',0)==0
print(json.dumps({'component_negative':'SDK-cancel-before-half-close','partial_rpc_not_completed':True,'signed_idle':True}),flush=True)
