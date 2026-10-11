"""QUIC framing and all-flow evidence boundaries, without network or product execution."""
import unittest
from trafficlab.protocol import MAX_LINE
from trafficlab.quic_wire import append_body, h3_headers
from trafficlab.routes import stage_route


class QuicSafetyTests(unittest.TestCase):
    def test_body_limit_before_append(self):
        body = bytearray(b'a' * MAX_LINE)
        with self.assertRaisesRegex(ValueError, 'BODY_TOO_LARGE'):
            append_body(body, b'b')
        self.assertEqual(len(body), MAX_LINE)

    def test_h3_rejects_duplicate_and_invalid_response(self):
        valid = [(b':status',b'200'),(b'content-type',b'application/json')]
        self.assertEqual(h3_headers(valid, True)[b':status'], b'200')
        for headers in (valid + [(b':status',b'200')], [(b':status',b'500'),valid[1]], [valid[0]],
                        valid + [(b'x-long', b'a' * 2049)]):
            with self.subTest(headers=headers), self.assertRaises(ValueError):
                h3_headers(headers, True)

    def test_quic_route_requires_wire_datagrams_and_each_flow(self):
        stage = {'complete':True,'origin':{'proxy':{'tcp_flows':0,'tcp_origin_fingerprint':'0',
            'udp_flows':1,'udp_origin_fingerprint':'123','udp_sent':17}},'results':[{
            'task':'udp','successful_tcp_flows':0,'tcp_origin_fingerprint':'0','udp_origin_fingerprint':'123',
            'flows':[{'received':3,'sent':3,'quic_datagrams_sent':17}]}]}
        self.assertTrue(stage_route(stage,True))
        stage['origin']['proxy']['udp_sent']=3
        self.assertFalse(stage_route(stage,True))
        stage['origin']['proxy']['udp_sent']=17
        stage['origin']['proxy']['udp_flows']=0
        self.assertFalse(stage_route(stage,True))


if __name__ == '__main__':
    unittest.main()
