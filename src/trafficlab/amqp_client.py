"""AMQP native handshake, publisher confirms, signed get and consumer acknowledgement."""
from __future__ import annotations
import json
import struct
from trafficlab.amqp_wire import PROTOCOL,Fields,header,method,short,long,content,content_header


class AmqpClient:
    def __init__(self,sock,stream,auth):
        # Username contains only the public run/flow pair; server independently verifies the token.
        import base64
        _,username,_=auth.split(b'\0')
        flow=json.loads(base64.b64decode(username,validate=True))[1]
        self.sock,self.stream,self.sequence,self.queue=sock,stream,0,b'testlab.'+flow.encode()
        sock.sendall(PROTOCOL)
        fields=self.expect(10,10)
        if fields.take(2)!=b'\0\x09':
            raise ValueError('APPLICATION_AMQP_VERSION_INVALID')
        fields.long()
        if fields.long()!=b'PLAIN' or fields.long()!=b'en_US':
            raise ValueError('APPLICATION_AMQP_AUTH_MECHANISM_INVALID')
        fields.done()
        sock.sendall(method(10,11,long(b'')+short(b'PLAIN')+long(auth)+short(b'en_US')))
        fields=self.expect(10,30)
        if fields.take(8)!=struct.pack('!HIH',1,16384,0):
            raise ValueError('APPLICATION_AMQP_TUNE_INVALID')
        fields.done()
        sock.sendall(method(10,31,struct.pack('!HIH',1,16384,0))+method(10,40,short(b'/')+short(b'')+b'\0'))
        fields=self.expect(10,41)
        if fields.short()!=b'':
            raise ValueError('APPLICATION_AMQP_OPEN_INVALID')
        fields.done()
        sock.sendall(method(20,10,short(b'')))
        fields=self.expect(20,11)
        if fields.long()!=b'':
            raise ValueError('APPLICATION_AMQP_CHANNEL_INVALID')
        fields.done()
        sock.sendall(method(50,10,b'\0\0'+short(self.queue)+b'\x0c'+long(b'')))
        fields=self.expect(50,11)
        if fields.short()!=self.queue or fields.take(8)!=b'\0'*8:
            raise ValueError('APPLICATION_AMQP_QUEUE_INVALID')
        fields.done()
        sock.sendall(method(85,10,b'\0'))
        self.expect(85,11).done()

    def read(self):
        from trafficlab.messaging_client import exact
        kind,channel,size=header(exact(self.stream,7))
        body=exact(self.stream,size)
        if exact(self.stream,1)!=b'\xce':
            raise ValueError('APPLICATION_AMQP_FRAME_END_INVALID')
        return kind,channel,body

    def expect(self,class_id,method_id):
        kind,channel,body=self.read()
        if kind!=1 or channel!=(0 if class_id==10 else 1) or body[:4]!=struct.pack('!HH',class_id,method_id):
            raise ValueError('APPLICATION_AMQP_METHOD_INVALID')
        return Fields(body[4:])

    def exchange(self,message):
        self.sequence+=1
        self.sock.sendall(method(60,40,b'\0\0'+short(b'')+short(self.queue)+b'\0')+content(message))
        fields=self.expect(60,80)
        if fields.take(9)!=struct.pack('!QB',self.sequence,0):
            raise ValueError('APPLICATION_AMQP_CONFIRM_UNVERIFIED')
        fields.done()
        self.sock.sendall(method(60,70,b'\0\0'+short(self.queue)+b'\0'))
        fields=self.expect(60,71)
        if fields.take(9)!=struct.pack('!QB',self.sequence,0) or fields.short()!=b'' or fields.short()!=self.queue or fields.take(4)!=b'\0'*4:
            raise ValueError('APPLICATION_AMQP_DELIVERY_UNVERIFIED')
        fields.done()
        kind,channel,raw=self.read()
        if (kind,channel)!=(2,1):
            raise ValueError('APPLICATION_AMQP_CONTENT_INVALID')
        size=content_header(raw)
        body=bytearray()
        while len(body)<size:
            kind,channel,raw=self.read()
            if (kind,channel)!=(3,1) or not raw or len(body)+len(raw)>size:
                raise ValueError('APPLICATION_AMQP_CONTENT_INVALID')
            body.extend(raw)
        returned=json.loads(body)
        self.sock.sendall(method(60,80,struct.pack('!QB',self.sequence,0)))
        return returned

    def close(self):
        args=struct.pack('!H',200)+short(b'normal')+b'\0'*4
        self.sock.sendall(method(20,40,args))
        self.expect(20,41).done()
        self.sock.sendall(method(10,50,args))
        self.expect(10,51).done()
