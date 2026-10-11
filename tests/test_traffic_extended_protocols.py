"""Protocol safety boundaries; no product, services or external network."""
import asyncio
import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from trafficlab.dependencies import extract
from trafficlab.http_two import H2Client, grpc_decode, grpc_encode
from trafficlab.ssh_wire import read_line
from trafficlab.protocol import MAX_LINE
from h2.config import H2Configuration
from h2.connection import H2Connection
from h2.events import StreamEnded


class Peer:
    def __init__(self, status='0', reset=False):
        self.conn = H2Connection(config=H2Configuration(client_side=False))
        self.conn.initiate_connection()
        self.received = bytearray(self.conn.data_to_send())
        self.status, self.reset = status, reset

    def sendall(self, raw):
        for event in self.conn.receive_data(raw):
            if isinstance(event, StreamEnded):
                if self.reset:
                    self.conn.reset_stream(event.stream_id)
                    continue
                self.conn.send_headers(event.stream_id, [(':status','200'),('content-type','application/grpc+proto')])
                self.conn.send_data(event.stream_id, grpc_encode(b'{"okay":true}'), end_stream=self.status is None)
                if self.status is not None:
                    self.conn.send_headers(event.stream_id, [('grpc-status',self.status)], end_stream=True)
        self.received.extend(self.conn.data_to_send())

    def recv(self, size):
        result = bytes(self.received[:size]); del self.received[:size]
        return result


class ProtocolSafetyTests(unittest.TestCase):
    def test_grpc_requires_zero_status_trailer(self):
        self.assertEqual(H2Client(Peer(), True).exchange(b'{}'), {'okay':True})
        for status in (None, '7', 'garbage'):
            with self.subTest(status=status), self.assertRaisesRegex(ValueError, 'GRPC_STATUS_UNVERIFIED'):
                H2Client(Peer(status), True).exchange(b'{}')

    def test_http2_reset_cannot_be_a_successful_exchange(self):
        with self.assertRaisesRegex(ValueError, 'HTTP2_RESET'):
            H2Client(Peer(reset=True), True).exchange(b'{}')

    def test_grpc_rejects_compression_truncation_and_extra_messages(self):
        encoded = grpc_encode(b'{"json":true}')
        self.assertEqual(grpc_decode(encoded), b'{"json":true}')
        for malformed in (b'\x01'+encoded[1:], encoded[:-1], encoded+encoded, b'\0\0\0\0\x02\x0a\xff'):
            with self.subTest(length=len(malformed)), self.assertRaises(ValueError):
                grpc_decode(malformed)

    def test_ssh_line_reader_is_bounded_and_rejects_partial_lines(self):
        class Reader:
            def __init__(self, raw): self.raw=raw
            async def read(self, size):
                result,self.raw=self.raw[:size],self.raw[size:]
                return result
        self.assertEqual(asyncio.run(read_line(Reader(b'{}\n'))), b'{}\n')
        for data in (b'x'*(MAX_LINE+1), b'{}', b'{}\n{}\n'):
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                asyncio.run(read_line(Reader(data)))

    def test_offline_extraction_rejects_verified_archive_path_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); wheel=root/'escape.whl'
            with zipfile.ZipFile(wheel,'w') as archive: archive.writestr('../escaped.py','bad')
            lock={'schema_version':1,'network_installation_allowed':False,'packages':[{'name':'escape'}],
                  'artifacts':[{'platform':'test','file':wheel.name,'bytes':wheel.stat().st_size,
                                'sha256':hashlib.sha256(wheel.read_bytes()).hexdigest()}]}
            (root/'lock.json').write_text(json.dumps(lock))
            with self.assertRaisesRegex(ValueError, 'DEPENDENCY_PATH_INVALID'):
                extract(root/'lock.json',root,root/'dependencies','test')
            self.assertFalse((root/'escaped.py').exists())


if __name__ == '__main__': unittest.main()
