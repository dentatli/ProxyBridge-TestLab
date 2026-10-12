"""HTTP/2 demultiplexing, bounded stream state and signed evidence gates."""
import base64,copy,hashlib,json,unittest
from types import SimpleNamespace
from trafficlab.application_origin import ApplicationOrigins
from trafficlab.application_wire import request
from trafficlab.http_two import H2Client,MULTIPLEX_PROFILE,MULTIPLEX_WIDTH,header_map
from trafficlab.routes import stage_route
from h2.config import H2Configuration
from h2.connection import H2Connection
from h2.events import DataReceived,RequestReceived,StreamEnded


class Peer:
    def __init__(self,width=3,mode='reverse'):
        self.conn=H2Connection(config=H2Configuration(client_side=False))
        self.conn.initiate_connection()
        self.received=bytearray(self.conn.data_to_send())
        self.requests={};self.ended=[];self.width=width;self.mode=mode;self.peak=0

    def sendall(self,raw):
        for event in self.conn.receive_data(raw):
            if isinstance(event,RequestReceived):
                self.requests[event.stream_id]=bytearray()
                self.peak=max(self.peak,len(self.requests))
            elif isinstance(event,DataReceived):
                self.requests[event.stream_id].extend(event.data)
                self.conn.acknowledge_received_data(event.flow_controlled_length,event.stream_id)
            elif isinstance(event,StreamEnded):self.ended.append(event.stream_id)
        if len(self.ended)==self.width:
            streams=list(reversed(self.ended));self.ended=[]
            for stream in streams:
                self.conn.send_headers(stream,[(':status','200'),('content-type','application/json')])
            for stream in streams:
                body=bytes(self.requests[stream])
                if self.mode=='oversized':body=b' '*8300
                if self.mode=='reset' and stream==streams[-1]:
                    self.conn.reset_stream(stream);continue
                if self.mode=='partial' and stream==streams[-1]:continue
                self.conn.send_data(stream,body[:len(body)//2])
            for stream in streams:
                if self.mode in ('reset','partial') and stream==streams[-1]:continue
                body=bytes(self.requests.pop(stream))
                if self.mode=='oversized':body=b' '*8300
                self.conn.send_data(stream,body[len(body)//2:],end_stream=True)
        self.received.extend(self.conn.data_to_send())

    def recv(self,size):
        # Small reads force HEADERS/DATA across transport reads as well as streams.
        result=bytes(self.received[:min(size,37)]);del self.received[:len(result)]
        return result


class MultiplexTests(unittest.TestCase):
    def test_duplicate_and_oversized_headers_are_rejected(self):
        self.assertEqual(header_map([(':status','200')]),{':status':'200'})
        for headers in ([('content-type','a'),('content-type','b')],[('large','x'*8192)]):
            with self.assertRaisesRegex(ValueError,'HTTP2_HEADERS_INVALID'):header_map(headers)

    def test_reverse_and_interleaved_replies_keep_request_identity(self):
        peer=Peer();client=H2Client(peer,False)
        for offset in (0,3):
            messages=[json.dumps({'sequence':offset+index}).encode() for index in range(3)]
            replies,rtts=client.exchange_many(messages)
            self.assertEqual(replies,[{'sequence':offset+index} for index in range(3)])
            self.assertEqual(peer.peak,3)
            self.assertEqual(len(rtts),3)
            self.assertTrue(all(value>=0 for value in rtts))

    def test_single_stream_reset_cannot_be_partial_batch_success(self):
        with self.assertRaisesRegex(ValueError,'HTTP2_RESET'):
            H2Client(Peer(mode='reset'),False).exchange_many([b'{}']*3)

    def test_unfinished_stream_and_oversized_reply_fail_whole_batch(self):
        with self.assertRaisesRegex(EOFError,'HTTP2_TRUNCATED'):
            H2Client(Peer(mode='partial'),False).exchange_many([b'{}']*3)
        with self.assertRaisesRegex(ValueError,'HTTP2_RESPONSE_TOO_LARGE'):
            H2Client(Peer(mode='oversized'),False).exchange_many([b'{}']*3)

    def test_request_bounds_fail_before_stream_allocation(self):
        for messages in ([],[b'{}']*17,[b''],[b'x'*8193]):
            with self.assertRaisesRegex(ValueError,'HTTP2_REQUEST_LIMIT'):
                H2Client(Peer(),False).exchange_many(messages)

    def test_exact_signed_peak_count_profile_and_tls_are_required(self):
        flow={'flow_id':'flow','http2_profile':MULTIPLEX_PROFILE,'http2_peak_streams':MULTIPLEX_WIDTH,
              'http2_completed_streams':6,'verified_transactions':6,'certificate_verified':True,'close_verified':True}
        stage={'complete':True,'results':[{'flows':[flow]}],'origin':{'application_flows':{'flow':{
            'http2_peak_streams':3,'http2_completed_streams':6,'transactions':6,
            'http2_pending_sequences':[],'last_sequence':5}}}}
        self.assertTrue(stage_route(stage,False))
        for change in ({'http2_peak_streams':1},{'http2_peak_streams':True},{'http2_completed_streams':5},{'transactions':5},
                       {'http2_pending_sequences':[1]},{'last_sequence':4}):
            bad=copy.deepcopy(stage);bad['origin']['application_flows']['flow'].update(change)
            self.assertFalse(stage_route(bad,False))
        for change in ({'http2_profile':'unknown'},{'certificate_verified':1},{'close_verified':False}):
            bad=copy.deepcopy(stage);bad['results'][0]['flows'][0].update(change)
            self.assertFalse(stage_route(bad,False))

    def test_out_of_order_sequences_have_a_bounded_replay_window(self):
        secret=b's'*32;payload=b'checked'
        row={'accepted':0,'active':0,'tcp_active_peak':0}
        agent=SimpleNamespace(secret=secret,metrics=lambda _:row,
                              proxy=SimpleNamespace(observe_application=lambda *_:None))
        origins=ApplicationOrigins(agent,{})
        def message(sequence):
            value=request(secret,'http2','unit-run','unit-flow',sequence,hashlib.sha256(payload).hexdigest())
            return {'identity':value,'payload':base64.b64encode(payload).decode()}
        session={};peer=['192.0.2.1',12345]
        for sequence in (2,0,1):origins.authenticate(message(sequence),'http2',peer,session)
        flow=row['application_flows']['unit-flow']
        self.assertEqual((flow['transactions'],flow['last_sequence'],flow['http2_pending_sequences']),(3,2,[]))
        for sequence in (1,19):
            with self.assertRaisesRegex(ValueError,'REPLAY_OR_PEER_CHANGED'):
                origins.authenticate(message(sequence),'http2',peer,session)
        self.assertEqual(flow['transactions'],3)


if __name__=='__main__':unittest.main()
