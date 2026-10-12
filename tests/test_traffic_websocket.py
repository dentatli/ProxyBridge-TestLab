"""Malformed frames, interleaved control, aggregate bounds and signed profile gates."""
import asyncio
import copy
import unittest
from trafficlab.protocol import MAX_LINE
from trafficlab.routes import stage_route
from trafficlab.websocket_wire import (PROFILE,MessageAssembler,WebSocketClient,frame,fragmented_message,
    read_frame,read_frame_async,validate_close)


class Socket:
    def __init__(self,data):
        self.data=bytearray(data)
        self.sent=bytearray()
    def recv(self,size):
        result=bytes(self.data[:size]);del self.data[:size]
        return result
    def sendall(self,data):
        self.sent.extend(data)


class WebSocketTests(unittest.TestCase):
    def test_masked_async_and_unmasked_sync_reassembly_with_ping(self):
        async def decode():
            reader=asyncio.StreamReader()
            reader.feed_data(fragmented_message(b'fragmented message',True,b'ping'))
            reader.feed_eof()
            assembler=MessageAssembler()
            received=[]
            for _ in range(4):
                item=assembler.feed(*await read_frame_async(reader))
                if item is not None:received.append(item)
            self.assertEqual(received,[(9,b'ping'),(2,b'fragmented message')])
            self.assertEqual(assembler.last_fragments,3)
        asyncio.run(decode())
        self.assertEqual(read_frame(Socket(frame(b'data',False))),(True,2,b'data'))

    def test_continuation_without_start_or_new_message_mid_fragment_rejected(self):
        with self.assertRaises(ValueError):MessageAssembler().feed(True,0,b'bad')
        parser=MessageAssembler();parser.feed(False,2,b'first')
        with self.assertRaises(ValueError):parser.feed(True,2,b'interleaved')

    def test_aggregate_size_and_fragment_count_bounded(self):
        parser=MessageAssembler();parser.feed(False,2,b'x'*MAX_LINE)
        with self.assertRaises(ValueError):parser.feed(True,0,b'x')
        parser=MessageAssembler();parser.feed(False,2,b'')
        for _ in range(63):parser.feed(False,0,b'')
        with self.assertRaises(ValueError):parser.feed(True,0,b'')

    def test_wrong_mask_rsv_noncanonical_lengths_and_control_fragments_rejected(self):
        for raw in (frame(b'x',True),b'\xc2\x00',b'\x82\x7e\x00\x01x',b'\x82\x7f',b'\x09\x00',b'\x89\x7e'):
            with self.assertRaises(ValueError):read_frame(Socket(raw))
        with self.assertRaises(ValueError):frame(b'x'*126,True,9)
        with self.assertRaises(ValueError):frame(b'x',False,10,False)

    def test_close_body_code_and_utf8_are_checked_even_mid_message(self):
        for raw in (b'x',(1005).to_bytes(2,'big'),(1015).to_bytes(2,'big'),b'\x03\xe8\xff'):
            with self.assertRaises(ValueError):validate_close(raw)
        parser=MessageAssembler();parser.feed(False,2,b'unfinished')
        self.assertEqual(parser.feed(True,8,b'\x03\xe8'),(8,b'\x03\xe8'))
        self.assertFalse(parser.active or parser.buffer)

    def test_control_only_flood_cannot_run_without_bound(self):
        parser=MessageAssembler()
        for _ in range(64):parser.feed(True,10,b'unsolicited')
        with self.assertRaises(ValueError):parser.feed(True,10,b'unsolicited')

    def test_wrong_or_missing_expected_pong_rejected(self):
        for data in (frame(b'wrong',False,10)+frame(b'reply',False),frame(b'reply',False)):
            with self.assertRaises(ValueError):WebSocketClient(Socket(data)).receive(b'expected')

    def test_fragmented_server_ping_is_answered_and_close_verified(self):
        peer=Socket(frame(b'client-ping',False,10)+fragmented_message(b'fragmented reply',False,b'server-ping'))
        client=WebSocketClient(peer)
        self.assertEqual(client.receive(b'client-ping'),(2,b'fragmented reply'))
        self.assertEqual(read_frame(Socket(peer.sent),True),(True,10,b'server-ping'))
        self.assertEqual(client.stats['ws_client_pongs_verified'],1)
        peer.data.extend(frame(b'\x03\xe8',False,8));client.close()

    def test_signed_profile_counter_mismatch_or_missing_evidence_blocks_route(self):
        flow={'flow_id':'flow','websocket_profile':PROFILE,'ws_fragmented_requests':1,'ws_fragmented_responses':1,
              'ws_client_pongs_verified':1,'ws_server_pings_answered':1,'verified_transactions':2}
        stage={'complete':True,'origin':{'application_flows':{'flow':{'ws_fragmented_requests':1,'ws_client_pings':1,
               'ws_server_pongs':1}}},'results':[{'flows':[flow]}]}
        self.assertTrue(stage_route(stage,False))
        for field in ('ws_fragmented_requests','ws_client_pings','ws_server_pongs'):
            for value in (0,True,None):
                broken=copy.deepcopy(stage);broken['origin']['application_flows']['flow'][field]=value
                self.assertFalse(stage_route(broken,False))
        broken=copy.deepcopy(stage);broken['results'][0]['flows'][0]['websocket_profile']='unknown'
        self.assertFalse(stage_route(broken,False))
        broken=copy.deepcopy(stage);broken['origin']['application_flows']={}
        self.assertFalse(stage_route(broken,False))


if __name__=='__main__':unittest.main()
