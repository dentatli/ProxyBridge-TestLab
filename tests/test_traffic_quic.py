"""QUIC framing and all-flow evidence boundaries, without network or product execution."""
import unittest
from types import SimpleNamespace
from trafficlab.protocol import MAX_LINE
from trafficlab.quic_wire import append_body, h3_headers
from trafficlab.routes import stage_route
from trafficlab.proxy import SocksProxy, fingerprint
from trafficlab.quic_client import finish_close, CLOSE_WAIT_LIMIT


class QuicSafetyTests(unittest.TestCase):
    def close_fixture(self, duration, terminate=True, cancel=False):
        state = {'now': 100., 'closing': False, 'closed': False}
        conn = SimpleNamespace(close=lambda: state.update(closing=True),
                               get_timer=lambda: 100.+duration)
        def pump(delay):
            state['now'] += delay
            if terminate and state['now'] >= 100.+duration:
                state['closed'] = True
        result = {}
        return conn, pump, lambda: state['closed'], lambda: cancel and state['now']>=101., result, lambda: state['now']

    def test_close_follows_library_timer_beyond_two_seconds(self):
        for duration in (0., .1, 3.3):
            with self.subTest(duration=duration):
                conn,pump,closed,cancelled,result,clock = self.close_fixture(duration)
                finish_close(conn,pump,closed,cancelled,result,clock=clock)
                self.assertTrue(result['close_verified'])
                self.assertGreaterEqual(result['close_wait_elapsed_seconds']+1e-9,duration)
                self.assertLess(result['close_wait_elapsed_seconds'],duration+.25)

    def test_close_failure_and_cancellation_never_become_success(self):
        for duration,terminate,cancel,code in ((30.,True,False,'BUDGET_EXCEEDED'),
                                              (3.,False,False,'TIMER_EXCEEDED'),
                                              (3.,True,True,'TRAFFIC_CANCELLED')):
            with self.subTest(code=code):
                conn,pump,closed,cancelled,result,clock = self.close_fixture(duration,terminate,cancel)
                with self.assertRaisesRegex(ValueError,code):
                    finish_close(conn,pump,closed,cancelled,result,clock=clock)
                self.assertFalse(result['close_verified'])
                self.assertLessEqual(result['close_wait_elapsed_seconds'],CLOSE_WAIT_LIMIT+.001)

    def test_shared_association_binds_counters_only_to_authenticated_connections(self):
        rows = {}
        agent = SimpleNamespace(max_connections=4, metrics=lambda run: rows.setdefault(run, {}))
        proxy = SocksProxy(agent, 42501, ['127.0.0.1'])
        peer = ['127.0.0.1', 50000]
        association = {'username': 'queue', 'run_id': 'queue.previous-udp',
                       'transport': SimpleNamespace(get_extra_info=lambda name: peer)}
        proxy.associations[('127.0.0.1', 12345)] = association
        for port, cid, run, flow, sent in [(42520, b'client01', 'queue.http3', 'flow-a', 7),
                                          (42520, b'client02', 'queue.http3', 'flow-b', 9),
                                          (42521, b'client01', 'queue.quic', 'flow-c', 11)]:
            key = (id(association), port, cid)
            route = {'key': key, 'identity': None, 'sent': sent, 'received': 3,
                     'server_ids': set(), 'client_ids': set()}
            proxy.quic.routes[key] = route
            with self.assertRaisesRegex(ValueError, 'IDENTITY_INVALID'):
                proxy.observe_quic('another-queue.run', flow, peer, port, cid)
            self.assertIsNone(route['identity'])
            proxy.observe_quic(run, flow, peer, port, cid)
            with self.assertRaisesRegex(ValueError, 'IDENTITY_INVALID'):
                proxy.observe_quic(run, flow, peer, port, cid)
        self.assertEqual(rows['queue.http3']['proxy']['udp_flows'], 2)
        self.assertEqual(rows['queue.http3']['proxy']['udp_sent'], 16)
        self.assertEqual(rows['queue.quic']['proxy']['udp_sent'], 11)
        expected = fingerprint('flow-a', peer) ^ fingerprint('flow-b', peer)
        self.assertEqual(int(rows['queue.http3']['proxy']['udp_origin_fingerprint'], 16), expected)
        self.assertNotIn('queue.previous-udp', rows)
        proxy.quic.forget(association)
        self.assertFalse(proxy.quic.routes)

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
