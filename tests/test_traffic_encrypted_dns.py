"""DoH framing and encrypted DNS evidence gates; no network or services."""
import copy
import io
import json
import unittest
from pathlib import Path
from trafficlab.dns_http import MIME,body_length,post
from trafficlab.routes import stage_route
from trafficlab.application_wire import APPLICATION_PORTS,dns_request,dns_verify,dns_response,response,verify_response,dns_decode


class Socket:
    def __init__(self):self.sent=bytearray()
    def sendall(self,raw):self.sent.extend(raw)


class EncryptedDnsTests(unittest.TestCase):
    def test_application_ports_do_not_overlap_legacy_protocol_allocations(self):
        legacy=json.loads((Path(__file__).resolve().parents[1]/'config/server-protocol-ports.json').read_text())['ports']
        reserved=set(legacy.values())|set(range(legacy['ftp_data_start'],legacy['ftp_data_end']+1))|set(range(legacy['realtime_start'],legacy['realtime_end']+1))
        self.assertFalse(set(APPLICATION_PORTS.values())&reserved)

    def test_doh_media_framing_and_dns_body_bounds(self):
        for size in (17,512):self.assertEqual(body_length({'content-type':MIME,'content-length':str(size)}),size)
        for headers in ({},{'content-type':'application/json','content-length':'17'},
            {'content-type':MIME,'content-length':'16'},{'content-type':MIME,'content-length':'513'},
            {'content-type':MIME,'content-length':'+17'},{'content-type':MIME,'content-length':'17','transfer-encoding':'chunked'},
            {'content-type':MIME,'content-length':'17','content-encoding':'gzip'}):
            with self.assertRaises(ValueError):body_length(headers)

    def test_doh_post_and_terminal_connection_header(self):
        sock=Socket();packet=b'x'*17
        parse=lambda _:('HTTP/1.1 200 OK',{'content-type':MIME,'content-length':'17','cache-control':'no-store'})
        self.assertEqual(post(sock,io.BytesIO(packet),packet,'traffic.testlab.invalid',42535,parse,True),packet)
        self.assertIn(b'POST /dns-query HTTP/1.1\r\n',sock.sent)
        self.assertIn(b'Connection: close\r\n',sock.sent)

    def test_wrong_status_cache_policy_or_truncated_reply_rejected(self):
        good={'content-type':MIME,'content-length':'17','cache-control':'no-store'}
        for status,header,data in [('HTTP/1.1 403 Forbidden',good,b'x'*17),
            ('HTTP/1.1 200 OK',{**good,'cache-control':'max-age=10'},b'x'*17),
            ('HTTP/1.1 200 OK',good,b'x'*16)]:
            with self.assertRaises(ValueError):post(Socket(),io.BytesIO(data),b'x'*17,'host',42535,lambda _:(status,header))

    def test_signed_transport_certificate_close_and_count_are_required(self):
        for kind in ('dns-tls','dns-https'):
            count=3
            flow={'flow_id':'flow','dns_encrypted_protocol':kind,'certificate_verified':True,'close_verified':True,
                  'verified_transactions':2}
            stage={'complete':True,'results':[{'flows':[flow]}],
                   'origin':{'application_flows':{'flow':{'dns_transport':kind,'transactions':count}}}}
            self.assertTrue(stage_route(stage,False))
            for change in ({'dns_transport':'dns-tcp'},{'transactions':True},{'transactions':count+1}):
                bad=copy.deepcopy(stage);bad['origin']['application_flows']['flow'].update(change)
                self.assertFalse(stage_route(bad,False))
            for key in ('certificate_verified','close_verified'):
                bad=copy.deepcopy(stage);bad['results'][0]['flows'][0][key]=1
                self.assertFalse(stage_route(bad,False))

    def test_dns_transaction_id_and_authenticated_proof_are_checked(self):
        secret=b's'*32
        packet,value=dns_request(secret,'dns-unit-run','dns-unit-flow',0)
        proof=response(secret,{key:item for key,item in value.items() if key!='proof'},['192.0.2.1',12345])
        wire=dns_response(packet,packet[12:],proof)
        self.assertEqual(verify_response(secret,value,dns_verify(packet,wire)),['192.0.2.1',12345])
        with self.assertRaises(ValueError):dns_verify(packet,bytes([wire[0]^1])+wire[1:])
        bad={**proof,'proof':'0'*64}
        with self.assertRaises(ValueError):verify_response(secret,value,dns_verify(packet,dns_response(packet,packet[12:],bad)))

    def test_terminal_txt_query_is_authenticated_and_not_an_A_query_replay(self):
        secret=b's'*32
        packet,value=dns_request(secret,'dns-unit-run','dns-unit-flow',1,True)
        parsed,_=dns_decode(packet,{'dns-unit-run':{}})
        self.assertEqual(parsed,value)
        self.assertEqual(packet[-4:],b'\0\x10\0\1')
        _,ordinary=dns_request(secret,'dns-unit-run','dns-unit-flow',1)
        self.assertNotEqual(ordinary['proof'],value['proof'])


if __name__=='__main__':unittest.main()
