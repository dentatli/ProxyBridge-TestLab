"""Streaming framing, full-duplex progress, HMAC and exact signed evidence."""
import base64,copy,hashlib,json,struct,unittest
from types import SimpleNamespace
from trafficlab.application_origin import ApplicationOrigins
from trafficlab.application_wire import request,verify_response
from trafficlab.grpc_streaming import MessageReader,PATHS,ServerStream,exchange
from trafficlab.http_two import H2Client,grpc_encode
from trafficlab.protocol import json_bytes
from trafficlab.routes import stage_route
from h2.config import H2Configuration
from h2.connection import H2Connection
from h2.events import ConnectionTerminated,DataReceived,RequestReceived,StreamEnded


class Connection:
    def __init__(self,conn,status):self.conn=conn;self.status=status
    def send_headers(self,stream,headers,**kwargs):
        if headers==[('grpc-status','0')]:
            if self.status is None:
                self.conn.send_data(stream,b'',end_stream=True);return
            headers=[('grpc-status',self.status)]
        self.conn.send_headers(stream,headers,**kwargs)
    def send_data(self,*args,**kwargs):self.conn.send_data(*args,**kwargs)


class Peer:
    def __init__(self,secret,status='0'):
        self.conn=H2Connection(config=H2Configuration(client_side=False,header_encoding='ascii'))
        self.conn.initiate_connection();self.received=bytearray(self.conn.data_to_send())
        self.row={'accepted':0,'active':0,'tcp_active_peak':0,'rx_bytes':0,'tx_bytes':0}
        self.agent=SimpleNamespace(secret=secret,metrics=lambda _:self.row,proxy=SimpleNamespace(observe_application=lambda *_:None))
        self.origins=ApplicationOrigins(self.agent,{});self.session={};self.streams={};self.status=status
        self.early_responses=0
    def sendall(self,raw):
        for event in self.conn.receive_data(raw):
            if isinstance(event,RequestReceived):
                path=dict(event.headers)[':path'];mode=next(mode for mode,item in PATHS.items() if item==path)
                self.streams[event.stream_id]=ServerStream(self.origins,Connection(self.conn,self.status),event.stream_id,mode,self.session,['192.0.2.1',12345])
            elif isinstance(event,DataReceived):
                item=self.streams[event.stream_id];item.feed(event.data)
                self.conn.acknowledge_received_data(event.flow_controlled_length,event.stream_id)
                if item.mode=='bidi-stream' and event.stream_ended is None:self.early_responses+=1
            elif isinstance(event,StreamEnded):self.streams.pop(event.stream_id).end()
            elif isinstance(event,ConnectionTerminated):pass
        self.received.extend(self.conn.data_to_send())
    def recv(self,size):
        raw=bytes(self.received[:min(size,37)]);del self.received[:len(raw)];return raw


class StreamingTests(unittest.TestCase):
    secret=b's'*32
    def messages(self,count):
        payload=b'checked'
        values=[request(self.secret,'grpc','unit-run','unit-flow',index,hashlib.sha256(payload).hexdigest()) for index in range(count)]
        return values,[json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()}) for value in values]

    def test_incremental_and_coalesced_frames(self):
        wire=b''.join(grpc_encode(json_bytes({'index':index})) for index in range(3))
        for chunks in ([wire],[bytes([item]) for item in wire]):
            reader=MessageReader();messages=[]
            for chunk in chunks:messages.extend(reader.feed(chunk))
            reader.finish()
            self.assertEqual([json.loads(item) for item in messages],[{'index':index} for index in range(3)])

    def test_compression_count_oversize_and_partial_frames_are_rejected(self):
        frame=grpc_encode(b'{}')
        for raw in (b'\1'+frame[1:],b'\0'+struct.pack('!I',8200),frame*4):
            with self.assertRaises(ValueError):MessageReader().feed(raw)
        reader=MessageReader();reader.feed(frame[:-1])
        with self.assertRaisesRegex(ValueError,'FRAME_TRUNCATED'):reader.finish()

    def test_all_three_modes_verify_receipts_and_bidi_progress_before_half_close(self):
        for mode in PATHS:
            with self.subTest(mode=mode):
                values,messages=self.messages(1 if mode=='server-stream' else 3)
                peer=Peer(self.secret);replies,rtts=exchange(H2Client(peer,True),mode,messages)
                self.assertEqual(len(replies),3);self.assertEqual(len(rtts),3)
                for index,reply in enumerate(replies):
                    self.assertEqual(reply['grpc_message_index'],index)
                    self.assertEqual(reply['grpc_mode'],mode)
                    self.assertEqual(verify_response(self.secret,values[0 if mode=='server-stream' else index],reply),['192.0.2.1',12345])
                flow=peer.row['application_flows']['unit-flow']
                self.assertEqual(flow['grpc_request_messages'],len(messages))
                self.assertEqual(flow['grpc_response_messages'],1 if mode=='client-stream' else 3)
                self.assertEqual(flow['grpc_rpc_count'],1)
                if mode=='bidi-stream':self.assertEqual(peer.early_responses,2)

    def test_missing_or_nonzero_final_status_is_failure(self):
        _,messages=self.messages(3)
        for mode in PATHS:
            for status in (None,'7'):
                with self.subTest(mode=mode,status=status),self.assertRaisesRegex(ValueError,'GRPC_STATUS_UNVERIFIED'):
                    exchange(H2Client(Peer(self.secret,status),True),mode,messages[:1] if mode=='server-stream' else messages)

    def test_receipt_index_is_inside_authenticated_proof(self):
        values,messages=self.messages(1)
        replies,_=exchange(H2Client(Peer(self.secret),True),'server-stream',messages)
        changed={**replies[0],'grpc_message_index':1}
        with self.assertRaises(ValueError):verify_response(self.secret,values[0],changed)

    def test_rpc_request_count_is_fixed_and_partial_server_stream_is_not_success(self):
        _,messages=self.messages(3)
        for mode in PATHS:
            with self.assertRaisesRegex(ValueError,'MESSAGE_COUNT_INVALID'):
                exchange(H2Client(Peer(self.secret),True),mode,messages[:2])
        with self.assertRaisesRegex(ValueError,'MESSAGE_COUNT_INVALID'):
            exchange(H2Client(Peer(self.secret),True),'server-stream',[b'x'*8193])

    def test_signed_counts_status_certificate_and_mode_are_required(self):
        for mode in PATHS:
            requests=2 if mode=='server-stream' else 6;responses=2 if mode=='client-stream' else 6
            flow={'flow_id':'flow','grpc_streaming_mode':mode,'grpc_rpc_count':2,'grpc_request_messages':requests,
                  'grpc_response_messages':responses,'grpc_receipts':6,'verified_transactions':requests,
                  'certificate_verified':True,'close_verified':True,'grpc_status_verified':True}
            observed={key:flow[key] for key in ('grpc_rpc_count','grpc_request_messages','grpc_response_messages','grpc_receipts')}
            observed.update(grpc_mode=mode,transactions=requests)
            stage={'complete':True,'results':[{'flows':[flow]}],'origin':{'application_flows':{'flow':observed}}}
            self.assertTrue(stage_route(stage,False))
            for change in ({'grpc_rpc_count':True},{'grpc_request_messages':requests+1},{'grpc_response_messages':responses+1},
                           {'grpc_receipts':5},{'grpc_mode':'unary'},{'transactions':requests+1}):
                bad=copy.deepcopy(stage);bad['origin']['application_flows']['flow'].update(change)
                self.assertFalse(stage_route(bad,False))
            for key in ('grpc_status_verified','certificate_verified','close_verified'):
                bad=copy.deepcopy(stage);bad['results'][0]['flows'][0][key]=1
                self.assertFalse(stage_route(bad,False))


if __name__=='__main__':unittest.main()
