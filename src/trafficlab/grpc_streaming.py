"""Controlled three-message gRPC streams; no compression or arbitrary services."""
from __future__ import annotations
import base64,json,struct,time
from typing import Any
from trafficlab.application_wire import SERVER_NAME,response
from trafficlab.http_two import grpc_encode,grpc_decode,header_map
from trafficlab.protocol import MAX_LINE,json_bytes,mac
from h2.events import ConnectionTerminated,DataReceived,ResponseReceived,StreamEnded,StreamReset,TrailersReceived

WIDTH=3
PATHS={'client-stream':'/testlab.Echo/ClientStream','server-stream':'/testlab.Echo/ServerStream',
       'bidi-stream':'/testlab.Echo/BidiStream'}


class MessageReader:
    def __init__(self,maximum: int=WIDTH):
        self.buffer=bytearray();self.count=0;self.maximum=maximum

    def feed(self,data: bytes) -> list[bytes]:
        self.buffer.extend(data);result=[]
        while len(self.buffer)>=5:
            size=struct.unpack('!I',self.buffer[1:5])[0]
            if self.buffer[0]!=0 or not 2<=size<=MAX_LINE+6:
                raise ValueError('APPLICATION_GRPC_FRAME_INVALID')
            if len(self.buffer)<size+5:break
            self.count+=1
            if self.count>self.maximum:raise ValueError('APPLICATION_GRPC_MESSAGE_LIMIT')
            result.append(grpc_decode(bytes(self.buffer[:size+5])))
            del self.buffer[:size+5]
        return result

    def finish(self):
        if self.buffer:raise ValueError('APPLICATION_GRPC_FRAME_TRUNCATED')


def receipt(secret: bytes,value: dict[str,Any],peer: list[Any],payload: str,mode: str,index: int) -> dict[str,Any]:
    result=response(secret,value,peer,payload);result.pop('proof')
    result.update(grpc_mode=mode,grpc_message_index=index,grpc_message_count=WIDTH)
    result['proof']=mac(secret,b'application-response:',json_bytes(value)+json_bytes(result))
    return result


class ServerStream:
    def __init__(self,origins: Any,conn: Any,stream: int,mode: str,session: dict[str,Any],peer: list[Any]):
        if session.get('grpc_mode') not in (None,mode):raise ValueError('APPLICATION_GRPC_MODE_CHANGED')
        session['grpc_mode']=mode
        self.origins=origins;self.conn=conn;self.stream=stream;self.mode=mode;self.session=session;self.peer=peer
        self.reader=MessageReader(1 if mode=='server-stream' else WIDTH)
        self.requests=0;self.receipts=[];self.headers_sent=False;self.flow=None

    def send(self,message: dict[str,Any]):
        body=json_bytes(message)
        if len(body)>MAX_LINE:raise ValueError('APPLICATION_GRPC_MESSAGE_LIMIT')
        if not self.headers_sent:
            self.conn.send_headers(self.stream,[(':status','200'),('content-type','application/grpc+proto')])
            self.headers_sent=True
        self.conn.send_data(self.stream,grpc_encode(body))
        self.flow['grpc_response_messages']=self.flow.get('grpc_response_messages',0)+1

    def feed(self,data: bytes):
        for raw in self.reader.feed(data):
            message=json.loads(raw)
            if not isinstance(message,dict) or not isinstance(message.get('payload'),str) or not 1<=len(base64.b64decode(message['payload'],validate=True))<=1024:
                raise ValueError('APPLICATION_GRPC_STREAM_PAYLOAD_INVALID')
            value,row,payload=self.origins.authenticate(message,'grpc',self.peer,self.session)
            self.flow=row['application_flows'][value['flow_id']]
            self.flow['grpc_mode']=self.mode
            self.flow['grpc_request_messages']=self.flow.get('grpc_request_messages',0)+1
            row['rx_bytes']+=len(payload)
            if self.mode=='server-stream':
                replies=[receipt(self.origins.agent.secret,value,self.peer,message['payload'],self.mode,index) for index in range(WIDTH)]
            else:replies=[receipt(self.origins.agent.secret,value,self.peer,message['payload'],self.mode,self.requests)]
            self.requests+=1
            self.flow['grpc_receipts']=self.flow.get('grpc_receipts',0)+len(replies)
            row['tx_bytes']+=len(payload)*len(replies)
            if self.mode=='client-stream':self.receipts.extend(replies)
            else:
                for reply in replies:self.send(reply)

    def end(self):
        self.reader.finish()
        if self.requests!=(1 if self.mode=='server-stream' else WIDTH):
            raise ValueError('APPLICATION_GRPC_MESSAGE_COUNT_INVALID')
        if self.mode=='client-stream':self.send({'messages':self.receipts})
        self.flow['grpc_rpc_count']=self.flow.get('grpc_rpc_count',0)+1
        self.conn.send_headers(self.stream,[('grpc-status','0')],end_stream=True)


def exchange(client: Any,mode: str,messages: list[bytes]) -> tuple[list[dict[str,Any]],list[float]]:
    if mode not in PATHS or len(messages)!=(1 if mode=='server-stream' else WIDTH) or any(not 0<len(message)<=MAX_LINE for message in messages):
        raise ValueError('APPLICATION_GRPC_MESSAGE_COUNT_INVALID')
    stream=client.conn.get_next_available_stream_id()
    client.conn.send_headers(stream,[(':method','POST'),(':scheme','https'),(':authority',SERVER_NAME),
        (':path',PATHS[mode]),('content-type','application/grpc+proto'),('te','trailers')])
    reader=MessageReader(1 if mode=='client-stream' else WIDTH)
    replies=[];rtts=[];received=None;trailers=None;ended=False
    started=time.perf_counter()
    def receive(count: int,require_end: bool):
        nonlocal received,trailers,ended
        while len(replies)<count or (require_end and not ended):
            raw=client.sock.recv(16384)
            if not raw:raise EOFError('APPLICATION_HTTP2_TRUNCATED')
            for event in client.conn.receive_data(raw):
                if isinstance(event,(StreamReset,ConnectionTerminated)):raise ValueError('APPLICATION_HTTP2_RESET')
                current=getattr(event,'stream_id',None)
                if current in (None,0):continue
                if current!=stream or ended:raise ValueError('APPLICATION_HTTP2_STREAM_CHANGED')
                if isinstance(event,ResponseReceived):
                    if received is not None:raise ValueError('APPLICATION_HTTP2_STATUS_INVALID')
                    received=header_map(event.headers)
                    if received.get(':status')!='200' or received.get('content-type')!='application/grpc+proto':
                        raise ValueError('APPLICATION_HTTP2_STATUS_INVALID')
                elif isinstance(event,DataReceived):
                    for message in reader.feed(event.data):
                        replies.append(json.loads(message));rtts.append((time.perf_counter()-started)*1000)
                    client.conn.acknowledge_received_data(event.flow_controlled_length,stream)
                elif isinstance(event,TrailersReceived):
                    if trailers is not None:raise ValueError('APPLICATION_GRPC_STATUS_UNVERIFIED')
                    trailers=header_map(event.headers)
                elif isinstance(event,StreamEnded):
                    reader.finish();ended=True
            outgoing=client.conn.data_to_send()
            if outgoing:client.sock.sendall(outgoing)
            if ended and len(replies)!=count:raise ValueError('APPLICATION_GRPC_MESSAGE_COUNT_INVALID')
    if mode=='bidi-stream':
        for index,message in enumerate(messages):
            client.conn.send_data(stream,grpc_encode(message),end_stream=index==WIDTH-1)
            client.sock.sendall(client.conn.data_to_send())
            # Each response must arrive while the request stream is still open.
            receive(index+1,index==WIDTH-1)
    else:
        data=b''.join(grpc_encode(message) for message in messages)
        for offset in range(0,len(data),8192):
            client.conn.send_data(stream,data[offset:offset+8192],end_stream=offset+8192>=len(data))
        client.sock.sendall(client.conn.data_to_send())
        receive(1 if mode=='client-stream' else WIDTH,True)
    if received is None or trailers is None or trailers.get('grpc-status')!='0':
        raise ValueError('APPLICATION_GRPC_STATUS_UNVERIFIED')
    if mode=='client-stream':
        if not isinstance(replies[0],dict) or set(replies[0])!={'messages'} or not isinstance(replies[0]['messages'],list) or len(replies[0]['messages'])!=WIDTH:
            raise ValueError('APPLICATION_GRPC_MESSAGE_COUNT_INVALID')
        return replies[0]['messages'],rtts*WIDTH
    return replies,rtts
