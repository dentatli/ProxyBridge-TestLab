"""Verify the independent .NET HTTP/2 SDK replies and signed origin counters."""
import base64,hashlib,json,subprocess,sys,time,uuid
from trafficlab.application_wire import request,verify_response
from trafficlab.protocol import json_bytes
from trafficlab.schedule import origin_metrics

binding=json.load(sys.stdin)
job={**binding,'run_id':'sdk-http2-'+uuid.uuid4().hex};flow_id=uuid.uuid4().hex
identity=origin_metrics(job)['identity']['application'];secret=bytes.fromhex(binding['secret'])
payloads=[bytes((index+sequence)%256 for index in range(512)) for sequence in range(3)]
values=[request(secret,'http2',job['run_id'],flow_id,sequence,hashlib.sha256(payload).hexdigest())
        for sequence,payload in enumerate(payloads)]
messages=[json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()}) for value,payload in zip(values,payloads)]
fixture={'host':binding['host'],'port':42518,'messages':[base64.b64encode(message).decode() for message in messages],**identity}
result=subprocess.run(['dotnet','artifacts/development-remote-wizard/http2-sdk-probe/TrafficHttp2Probe.dll'],
                      input=json.dumps(fixture),capture_output=True,text=True,timeout=20)
assert result.returncode==0,result.stderr[:1200]
returned=json.loads(result.stdout)
assert returned['tls_pin_verified'] and returned['tcp_connections']==1 and len(returned['responses'])==3
peers=[]
for raw,value,payload in zip(returned['responses'],values,payloads):
    reply=json.loads(base64.b64decode(raw));peers.append(verify_response(secret,value,reply))
    assert base64.b64decode(reply['payload'])==payload
assert peers[0]==peers[1]==peers[2]
for _ in range(40):
    remote=origin_metrics(job)
    if remote['runtime_connections']==0:break
    time.sleep(.1)
flow=remote['application_flows'][flow_id]
assert flow['http2_peak_streams']==3 and flow['http2_completed_streams']==3 and flow['transactions']==3
assert flow['last_sequence']==2 and flow['http2_pending_sequences']==[] and flow['peer']==peers[0]
assert remote['runtime_connections']==0 and remote['proxy_connections']==0
print(json.dumps({'component_sdk':'NET10 HttpClient HTTP2','verified':True,'one_TCP_connection':True,
                  'signed_peak_streams':3,'signed_idle':True}),flush=True)
