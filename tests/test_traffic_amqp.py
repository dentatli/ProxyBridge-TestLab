"""AMQP frame bounds, content and exact publisher acknowledgement gates."""
import io
import struct
import unittest
from trafficlab.amqp_client import AmqpClient
from trafficlab.amqp_wire import Fields,frame,header,method,content_header
from trafficlab.protocol import MAX_LINE


class Capture:
    def sendall(self,data):
        pass


class AmqpSafetyTests(unittest.TestCase):
    def test_frame_bounds_channels_and_heartbeat(self):
        for raw in (struct.pack('!BHI',1,1,MAX_LINE+1),struct.pack('!BHI',1,2,0),struct.pack('!BHI',8,1,0)):
            with self.assertRaises(ValueError):
                header(raw)
        fields=Fields(b'\0\0\xff\xff')
        with self.assertRaises(ValueError):
            fields.long()

    def test_content_bounds_and_properties(self):
        self.assertEqual(content_header(struct.pack('!HHQH',60,0,512,0)),512)
        for raw in (struct.pack('!HHQH',60,0,MAX_LINE+1,0),struct.pack('!HHQH',60,0,512,1),
                    struct.pack('!HHQH',60,0,512,0)+b'extra'):
            with self.assertRaises(ValueError):
                content_header(raw)

    def test_confirm_requires_current_tag_and_no_nack(self):
        for raw in (method(60,80,struct.pack('!QB',2,0)),method(60,80,struct.pack('!QB',1,1)),
                    method(60,120,struct.pack('!QB',1,0)),method(60,80,struct.pack('!QB',1,0))[:-1]+b'\0'):
            client=AmqpClient.__new__(AmqpClient)
            client.sock,client.stream,client.sequence,client.queue=Capture(),io.BytesIO(raw),0,b'testlab.flow'
            with self.assertRaises(ValueError):
                client.exchange(b'{}')


if __name__=='__main__':
    unittest.main()
