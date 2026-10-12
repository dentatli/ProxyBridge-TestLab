"""Bounded HTTP framing, gzip decompression and signed mode coverage."""
import asyncio
import copy
import gzip
import io
import unittest
from trafficlab.http_body import PROFILE,MODES,decode,encode,framing,read,read_async
from trafficlab.protocol import MAX_LINE
from trafficlab.routes import stage_route


def fields(raw):
    return {key.lower():value.strip() for key,value in (line.split(':',1) for line in raw.decode().splitlines())}


class HttpBodyTests(unittest.TestCase):
    def test_four_modes_roundtrip_in_both_sync_and_async_readers(self):
        payload=b'HTTP framing payload'*100
        async def exercise():
            for chunked,compressed in MODES:
                header,body=encode(payload,chunked,compressed)
                expected=(payload,chunked,compressed)
                self.assertEqual(read(io.BytesIO(body),fields(header)),expected)
                reader=asyncio.StreamReader();reader.feed_data(body);reader.feed_eof()
                self.assertEqual(await read_async(reader,fields(header)),expected)
        asyncio.run(exercise())

    def test_ambiguous_or_missing_length_and_unknown_codings_rejected(self):
        for header in ({},{'content-length':'0'},{'content-length':'+1'},{'content-length':'-1'},
                {'content-length':'8193'},{'transfer-encoding':'chunked','content-length':'1'},
                {'transfer-encoding':'gzip, chunked'},{'content-length':'1','content-encoding':'br'}):
            with self.assertRaises(ValueError):framing(header)

    def test_malformed_chunk_framing_or_trailers_rejected(self):
        for body in (b'z\r\n',b'1;foo=bar\r\nx\r\n0\r\n\r\n',b'1\r\nx\n0\r\n\r\n',
                b'1\r\n',b'2001\r\n',b'0\r\nX-Trailer: no\r\n\r\n',b'0\r\n'):
            with self.assertRaises(ValueError):read(io.BytesIO(body),{'transfer-encoding':'chunked'})

    def test_aggregate_size_and_chunk_count_bounded(self):
        for body in (b'1000\r\n'+b'x'*4096+b'\r\n1001\r\n',b'1\r\nx\r\n'*65+b'0\r\n\r\n'):
            with self.assertRaises(ValueError):read(io.BytesIO(body),{'transfer-encoding':'chunked'})
        legal=b'1\r\nx\r\n'*64+b'0\r\n\r\n'
        self.assertEqual(read(io.BytesIO(legal),{'transfer-encoding':'chunked'})[0],b'x'*64)

    def test_gzip_bomb_crc_truncation_and_extra_members_rejected(self):
        valid=gzip.compress(b'payload')
        corrupt=valid[:-1]+bytes([valid[-1]^1])
        for data in (gzip.compress(b'x'*(MAX_LINE+1)),valid[:-1],corrupt,valid+valid,valid+b'extra'):
            with self.assertRaises(ValueError):decode(data,True)
        self.assertEqual(decode(gzip.compress(b'x'*MAX_LINE),True),b'x'*MAX_LINE)

    def test_keepalive_reader_stops_at_own_body(self):
        for chunked,compressed in MODES:
            header,body=encode(b'payload',chunked,compressed)
            stream=io.BytesIO(body+b'NEXT RESPONSE')
            self.assertEqual(read(stream,fields(header))[0],b'payload')
            self.assertEqual(stream.read(),b'NEXT RESPONSE')

    def test_truncated_content_length_body_rejected(self):
        with self.assertRaises(ValueError):read(io.BytesIO(b'partial'),{'content-length':'8'})

    def test_signed_counter_mismatch_missing_or_bool_blocks_route(self):
        counters={'http_chunked_requests':2,'http_gzip_requests':2,'http_chunked_responses':2,'http_gzip_responses':2}
        flow={'flow_id':'flow','http_profile':PROFILE,'verified_transactions':4,**counters}
        stage={'complete':True,'origin':{'application_flows':{'flow':counters}},'results':[{'flows':[flow]}]}
        self.assertTrue(stage_route(stage,False))
        for key in counters:
            for value in (0,True,None):
                broken=copy.deepcopy(stage);broken['origin']['application_flows']['flow'][key]=value
                self.assertFalse(stage_route(broken,False))
        broken=copy.deepcopy(stage);broken['origin']['application_flows']={}
        self.assertFalse(stage_route(broken,False))


if __name__=='__main__':unittest.main()
