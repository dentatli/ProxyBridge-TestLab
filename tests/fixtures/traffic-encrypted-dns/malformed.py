"""Opt-in malformed/replay checks against the dedicated encrypted DNS runtime."""
import hashlib,json,socket,ssl,struct,sys,time,uuid
from trafficlab.application_client import headers
from trafficlab.application_wire import SERVER_NAME,dns_request,dns_verify,verify_response
from trafficlab.dns_http import post
from trafficlab.schedule import origin_metrics

binding=json.load(sys.stdin)
secret=bytes.fromhex(binding['secret'])
for kind,port in [('dns-tls',42533),('dns-https',42535)]:
    cases=['length-underflow','length-overflow','invalid-DNS-header','replay']
    if kind=='dns-https':
        cases+=['GET','wrong-path','wrong-MIME','wrong-Accept','duplicate-length','chunked','gzip']
    for name in cases:
        job={**binding,'run_id':'dns-malformed-'+uuid.uuid4().hex}
        flow_id=uuid.uuid4().hex
        identity=origin_metrics(job)['identity']['application']
        packet,value=dns_request(secret,job['run_id'],flow_id,0)
        context=ssl.create_default_context(cadata=identity['tls_ca_pem'])
        context.set_alpn_protocols(['dot' if kind=='dns-tls' else 'http/1.1'])
        with socket.create_connection((binding['host'],port),timeout=2) as plain:
            with context.wrap_socket(plain,server_hostname=SERVER_NAME) as sock:
                assert hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()==identity['tls_certificate_sha256']
                if name=='replay':
                    if kind=='dns-tls':
                        sock.sendall(struct.pack('!H',len(packet))+packet)
                        stream=sock.makefile('rb')
                        size=struct.unpack('!H',stream.read(2))[0]
                        reply=stream.read(size)
                        stream.close()
                    else:
                        stream=sock.makefile('rb')
                        reply=post(sock,stream,packet,SERVER_NAME,port,headers)
                        stream.close()
                    verify_response(secret,value,dns_verify(packet,reply))
                body=packet
                if name=='invalid-DNS-header':body=packet[:2]+b'\x81\x00'+packet[4:]
                if kind=='dns-tls':
                    size=16 if name=='length-underflow' else 513 if name=='length-overflow' else len(body)
                    raw=struct.pack('!H',size)+body[:size]
                else:
                    method='GET' if name=='GET' else 'POST'
                    path='/other' if name=='wrong-path' else '/dns-query'
                    mime='application/json' if name=='wrong-MIME' else 'application/dns-message'
                    accept='text/plain' if name=='wrong-Accept' else 'application/dns-message'
                    size=16 if name=='length-underflow' else 513 if name=='length-overflow' else len(body)
                    extra=f'Content-Length: {size}\r\n' if name=='duplicate-length' else 'Transfer-Encoding: chunked\r\n' if name=='chunked' else 'Content-Encoding: gzip\r\n' if name=='gzip' else ''
                    raw=f'{method} {path} HTTP/1.1\r\nHost: {SERVER_NAME}:{port}\r\nContent-Type: {mime}\r\nAccept: {accept}\r\nContent-Length: {size}\r\n{extra}\r\n'.encode()+body
                try:
                    sock.sendall(raw)
                    assert sock.recv(1)==b'',(kind,name,'invalid request returned data')
                except (ConnectionResetError,ssl.SSLEOFError):pass
        for _ in range(30):
            remote=origin_metrics(job)
            if remote['runtime_connections']==0:break
            time.sleep(.05)
        assert remote['runtime_connections']==0 and remote['proxy_connections']==0,(kind,name,'runtime not idle')
        if name=='replay':
            flow=remote['application_flows'][flow_id]
            assert flow['transactions']==1 and flow['dns_transport']==kind,(kind,name,'replay was counted')
        else:assert not remote.get('application_flows'),(kind,name,'invalid request authenticated')
        print(json.dumps({'component_malformed':name,'application':kind,'rejected':True,'signed_idle':True}),flush=True)
