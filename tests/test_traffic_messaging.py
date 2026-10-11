"""Bounds, identity and acknowledgement gates without product or network."""
import io
import unittest
from trafficlab.messaging_wire import (authenticate,auth_plain,mail_decode,mail_encode,mqtt_length,
    mqtt_packet,mqtt_publish,mqtt_string,mqtt_take,REQUEST_TOPIC)
from trafficlab.messaging_client import MqttClient
from trafficlab.protocol import MAX_LINE


class Capture:
    def sendall(self,data):
        pass


class MessagingSafetyTests(unittest.TestCase):
    def test_authentication_binds_run_and_flow(self):
        secret=b'a'*32
        self.assertEqual(authenticate(secret,auth_plain(secret,'run-1','flow-1')),('run-1','flow-1'))
        for raw in (auth_plain(b'b'*32,'run-1','flow-1'),b'\0broken\0password',b'authz\0user\0password'):
            with self.assertRaises(ValueError):
                authenticate(secret,raw)

    def test_mail_fixture_cannot_escape_or_exceed_bound(self):
        message=b'{"identity":{},"payload":"test"}'
        self.assertEqual(mail_decode(mail_encode(message)),{'identity':{},'payload':'test'})
        for raw in (b'Bcc: external@example.invalid\r\n'+mail_encode(message),mail_encode(message)+b'extra',b'a'*(MAX_LINE+1)):
            with self.assertRaises(ValueError):
                mail_decode(raw)

    def test_mqtt_lengths_and_strings_are_bounded(self):
        self.assertEqual(mqtt_length(b'\x80\x01'),128)
        for raw in (b'\x80\0',b'\xff\xff\xff\xff',b'\xff\xff\x7f',b'\x80'):
            with self.assertRaises(ValueError):
                mqtt_length(raw)
        with self.assertRaises(ValueError):
            mqtt_take(b'\0\x10tiny',0)
        with self.assertRaises(ValueError):
            mqtt_publish(mqtt_string(b'other')+b'\0\x01data',REQUEST_TOPIC)
        with self.assertRaises(ValueError):
            mqtt_publish(mqtt_string(REQUEST_TOPIC)+b'\0\0data',REQUEST_TOPIC)

    def test_mqtt_rejects_unacknowledged_or_changed_packet_id(self):
        for raw in (mqtt_packet(0x40,b'\0\x01'),mqtt_packet(0x40,b'\0\x02')*2):
            client=MqttClient.__new__(MqttClient)
            client.sock,client.stream,client.sequence=Capture(),io.BytesIO(raw),1
            with self.assertRaises((ValueError,EOFError)):
                client.exchange(b'{}')


if __name__=='__main__':
    unittest.main()
