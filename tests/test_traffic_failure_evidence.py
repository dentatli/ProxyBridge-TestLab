"""Regression checks for evidence previously lost in full50 failures."""
import unittest
import json
import socket
import threading
from unittest.mock import patch
from trafficlab.diagnostics import datagram_source, require_datagram_source, invalid_datagram
from trafficlab.worker import flow_churn, udp_flow
from trafficlab.protocol import json_bytes, mac, verify_mac


class FailureEvidenceTests(unittest.TestCase):
    def test_failed_churn_after_sample_cap_is_retained(self):
        clock = [0.0]
        def flow(_job, _task, flow_id):
            clock[0] += .01
            ok = not flow_id.endswith('.65')
            return {'flow_id':flow_id, 'complete':ok, 'connect_ms':1, 'tx_bytes':0, 'rx_bytes':0,
                    'peer_observed_by_origin':['127.0.0.1',42501],
                    'errors':[] if ok else ['ConnectionResetError:TRANSPORT_FAILED'], 'socket_winerror':10054}
        with patch('trafficlab.worker.time.perf_counter', side_effect=lambda:clock[0]), \
             patch('trafficlab.worker.tcp_flow', side_effect=flow), patch('trafficlab.worker.pace'):
            result = flow_churn({'seconds':.7, 'run_id':'late-failure'}, 0)
        self.assertFalse(result['complete'])
        self.assertEqual(result['failures'], 1)
        self.assertEqual(len(result['route_samples']), 64)
        self.assertTrue(all(row['complete'] for row in result['route_samples']))
        self.assertEqual(result['failure_samples'][0]['socket_winerror'], 10054)
        self.assertFalse(result['failure_samples_truncated'])

    def test_endpoint_failure_retains_bounded_expected_actual_and_phase(self):
        result = {}
        self.assertTrue(datagram_source(result, ('::1',42,0,0), ('::1',42), phase='udp-response'))
        self.assertEqual(result, {})
        for code in ('APPLICATION_DNS_SOURCE_INVALID', 'APPLICATION_QUIC_DATAGRAM_SOURCE_INVALID'):
            with self.assertRaisesRegex(ValueError, code):
                require_datagram_source(result, ('127.0.0.1',34011), ('127.0.0.1',42515), code, phase='response')
        self.assertEqual(result['unexpected_source_packets'], 2)
        self.assertEqual(result['first_source_mismatch'],
                         {'actual':['127.0.0.1',34011], 'expected':['127.0.0.1',42515], 'phase':'response'})

    def test_invalid_packet_reasons_are_counted_without_payload_or_exception_text(self):
        result = {}
        for error in (ValueError('TRAFFIC_AUTHENTICATION_FAILED'), ValueError('TRAFFIC_DATAGRAM_FLOW_MISMATCH'),
                      ValueError('untrusted packet contents'), KeyError('payload')):
            invalid_datagram(result, error)
        self.assertEqual(result['invalid_reasons'], {'TRAFFIC_AUTHENTICATION_FAILED':1,
                         'TRAFFIC_DATAGRAM_FLOW_MISMATCH':1, 'TRAFFIC_DATAGRAM_MALFORMED':2})

    def test_signed_udp_response_from_wrong_port_cannot_pass(self):
        secret = b'x' * 32
        for wrong_source in (False, True):
            with self.subTest(wrong_source=wrong_source), socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as origin, \
                 socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as other:
                origin.bind(('127.0.0.1',0)); origin.settimeout(2)
                other.bind(('127.0.0.1',0))
                errors = []
                def reply():
                    try:
                        data, peer = origin.recvfrom(65535)
                        header, payload = data.split(b'\n',1)
                        request = json.loads(header); proof = request.pop('proof')
                        verify_mac(secret, b'udp-client:', json_bytes(request) + payload, proof)
                        response = {**request, 'peer':list(peer)}
                        response['proof'] = mac(secret, b'udp-server:', json_bytes(response) + payload)
                        (other if wrong_source else origin).sendto(json_bytes(response) + b'\n' + payload, peer)
                    except Exception as error:
                        errors.append(error)
                thread = threading.Thread(target=reply); thread.start()
                try:
                    result = udp_flow({'host':'127.0.0.1','port':origin.getsockname()[1], 'secret':secret.hex(),
                        'run_id':'source-test','udp_connected':False,'seconds':.06,'rate_packets_per_second':1}, 'flow')
                finally:
                    thread.join(timeout=3)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors, [])
                self.assertEqual(result['received'], 1)
                self.assertEqual(result['complete'], not wrong_source)
                if wrong_source:
                    self.assertIn('TRAFFIC_UDP_SOURCE_INVALID', result['errors'])
                    self.assertEqual(result['first_source_mismatch']['actual'], list(other.getsockname()))
