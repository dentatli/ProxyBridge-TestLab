import hashlib,http.client,json,socket,ssl,sys,time,uuid
# dnspython is an opt-in SDK dependency; production dependencies are unchanged.
import dns.message,dns.query,dns.rdatatype
from trafficlab.application_wire import SERVER_NAME,dns_request,verify_response
from trafficlab.schedule import origin_metrics
binding=json.load(sys.stdin)
for kind,port in [('dns-tls',42533),('dns-https',42535)]:
    job={**binding,'run_id':'sdk-dns-'+uuid.uuid4().hex};flow_id=uuid.uuid4().hex
    identity=origin_metrics(job)['identity']['application']
    context=ssl.create_default_context(cadata=identity['tls_ca_pem'])
    context.set_alpn_protocols(['dot' if kind=='dns-tls' else 'http/1.1'])
    packet,value=dns_request(bytes.fromhex(binding['secret']),job['run_id'],flow_id,0)
    query=dns.message.from_wire(packet)
    if kind=='dns-tls':
        with socket.create_connection((binding['host'],port),timeout=2) as plain:
            with context.wrap_socket(plain,server_hostname=SERVER_NAME) as sock:
                assert hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()==identity['tls_certificate_sha256']
                assert sock.selected_alpn_protocol()=='dot'
                sock.setblocking(False)
                answer=dns.query.tls(query,binding['host'],port=port,timeout=2,sock=sock)
                terminal,t_value=dns_request(bytes.fromhex(binding['secret']),job['run_id'],flow_id,1,True)
                terminal_query=dns.message.from_wire(terminal)
                closed=dns.query.tls(terminal_query,binding['host'],port=port,timeout=2,sock=sock)
                assert terminal_query.is_response(closed) and closed.rcode()==0 and len(closed.answer)==2
                terminal_peer=verify_response(bytes.fromhex(binding['secret']),t_value,json.loads(b''.join(closed.answer[1][0].strings)))
                sock.setblocking(True);sock.settimeout(2);assert sock.recv(1)==b'';sock.unwrap().close()
    else:
        client=http.client.HTTPSConnection(SERVER_NAME,port,timeout=2,context=context)
        client._create_connection=lambda *_args,**_kwargs:socket.create_connection((binding['host'],port),timeout=2)
        try:
            client.connect()
            assert hashlib.sha256(client.sock.getpeercert(binary_form=True)).hexdigest()==identity['tls_certificate_sha256']
            assert client.sock.selected_alpn_protocol()=='http/1.1'
            client.request('POST','/dns-query',body=query.to_wire(),headers={'Content-Type':'application/dns-message','Accept':'application/dns-message'})
            received=client.getresponse()
            assert received.status==200 and received.getheader('Content-Type')=='application/dns-message'
            assert received.getheader('Cache-Control')=='no-store'
            raw=received.read(513)
            assert 17<=len(raw)<=512 and int(received.getheader('Content-Length'))==len(raw)
            answer=dns.message.from_wire(raw)
        finally:client.close()
    assert query.is_response(answer) and answer.rcode()==0 and len(answer.answer)==2
    assert answer.answer[0].rdtype==dns.rdatatype.A and answer.answer[0][0].address=='192.0.2.10'
    assert answer.answer[1].rdtype==dns.rdatatype.TXT
    proof=json.loads(b''.join(answer.answer[1][0].strings))
    peer=verify_response(bytes.fromhex(binding['secret']),value,proof)
    if kind=='dns-tls':assert terminal_peer==peer
    for _ in range(40):
        remote=origin_metrics(job)
        if remote['runtime_connections']==0:break
        time.sleep(.1)
    flow=remote['application_flows'][flow_id]
    assert flow['dns_transport']==kind and flow['peer']==peer and flow['transactions']==1+int(kind=='dns-tls')
    assert remote['runtime_connections']==0 and remote['proxy_connections']==0
    print(json.dumps({'component_sdk':'dnspython 2.9.0 / stdlib HTTPS','application':kind,'verified':True,
        'CA_name_pin':True,'signed_idle':True}),flush=True)
