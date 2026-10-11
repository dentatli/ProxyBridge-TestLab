"""Memory-only AMQP queue per authenticated flow; bounded confirmed publish and get/ack."""
from __future__ import annotations
import asyncio
import json
import struct
from trafficlab.amqp_wire import PROTOCOL,Fields,header,method,short,long,content,content_header,start_properties
from trafficlab.application_wire import response
from trafficlab.messaging_wire import authenticate
from trafficlab.protocol import json_bytes


async def read(reader):
    kind,channel,size=header(await asyncio.wait_for(reader.readexactly(7),5))
    body=await asyncio.wait_for(reader.readexactly(size),5)
    if await asyncio.wait_for(reader.readexactly(1),5)!=b'\xce':
        raise ValueError('APPLICATION_AMQP_FRAME_END_INVALID')
    return kind,channel,body


async def expect(reader,class_id,method_id):
    kind,channel,body=await read(reader)
    if kind!=1 or channel!=(0 if class_id==10 else 1) or body[:4]!=struct.pack('!HH',class_id,method_id):
        raise ValueError('APPLICATION_AMQP_METHOD_INVALID')
    return Fields(body[4:])


async def send(writer,raw):
    writer.write(raw)
    await writer.drain()


async def serve(origins,reader,writer,kind,session,peer):
    if await asyncio.wait_for(reader.readexactly(8),5)!=PROTOCOL:
        raise ValueError('APPLICATION_AMQP_VERSION_INVALID')
    await send(writer,method(10,10,b'\0\x09'+start_properties()+long(b'PLAIN')+long(b'en_US')))
    fields=await expect(reader,10,11)
    fields.long()  # bounded opaque client property table
    if fields.short()!=b'PLAIN':
        raise ValueError('APPLICATION_AMQP_AUTH_MECHANISM_INVALID')
    user=authenticate(origins.agent.secret,fields.long())
    if fields.short()!=b'en_US':
        raise ValueError('APPLICATION_AMQP_LOCALE_INVALID')
    fields.done()
    await send(writer,method(10,30,struct.pack('!HIH',1,16384,0)))
    fields=await expect(reader,10,31)
    if fields.take(8)!=struct.pack('!HIH',1,16384,0):
        raise ValueError('APPLICATION_AMQP_TUNE_INVALID')
    fields.done()
    fields=await expect(reader,10,40)
    if fields.short()!=b'/' or fields.short()!=b'' or fields.take(1) not in (b'\0',b'\x01'):
        raise ValueError('APPLICATION_AMQP_VHOST_DENIED')
    fields.done()
    await send(writer,method(10,41,short(b'')))
    fields=await expect(reader,20,10)
    if fields.short()!=b'':
        raise ValueError('APPLICATION_AMQP_CHANNEL_INVALID')
    fields.done()
    await send(writer,method(20,11,long(b'')))
    queue=b'testlab.'+user[1].encode()
    declared=confirmed=delivered=channel_closed=False
    pending=None
    sequence=0
    while True:
        frame_type,channel,body=await read(reader)
        if frame_type!=1 or len(body)<4:
            raise ValueError('APPLICATION_AMQP_METHOD_INVALID')
        class_id,method_id=struct.unpack('!HH',body[:4])
        if channel!=(0 if class_id==10 else 1) or channel_closed and class_id!=10:
            raise ValueError('APPLICATION_AMQP_CHANNEL_INVALID')
        fields=Fields(body[4:])
        if (class_id,method_id)==(50,10) and pending is None:
            if fields.take(2)!=b'\0\0' or fields.short()!=queue or fields.take(1)!=b'\x0c' or fields.long()!=b'':
                raise ValueError('APPLICATION_AMQP_QUEUE_DENIED')
            fields.done()
            declared=True
            await send(writer,method(50,11,short(queue)+struct.pack('!II',0,0)))
        elif (class_id,method_id)==(85,10) and not confirmed:
            if fields.take(1)!=b'\0':
                raise ValueError('APPLICATION_AMQP_CONFIRM_INVALID')
            fields.done()
            confirmed=True
            await send(writer,method(85,11))
        elif (class_id,method_id)==(60,40) and declared and confirmed and pending is None:
            if fields.take(2)!=b'\0\0' or fields.short()!=b'' or fields.short()!=queue or fields.take(1) not in (b'\0',b'\x01'):
                raise ValueError('APPLICATION_AMQP_ROUTE_DENIED')
            fields.done()
            header_type,header_channel,raw_header=await read(reader)
            if (header_type,header_channel)!=(2,1):
                raise ValueError('APPLICATION_AMQP_CONTENT_INVALID')
            size=content_header(raw_header)
            raw=bytearray()
            while len(raw)<size:
                body_type,body_channel,part=await read(reader)
                if (body_type,body_channel)!=(3,1) or not part or len(raw)+len(part)>size:
                    raise ValueError('APPLICATION_AMQP_CONTENT_INVALID')
                raw.extend(part)
            sequence+=1
            try:
                message=json.loads(raw)
                if (message['identity']['run_id'],message['identity']['flow_id'])!=user:
                    raise ValueError('APPLICATION_AMQP_IDENTITY_CHANGED')
                identity,row,payload=origins.authenticate(message,kind,peer,session)
            except (ValueError,KeyError,TypeError):
                await send(writer,method(60,120,struct.pack('!QB',sequence,0)))
                raise
            row['rx_bytes']+=len(payload)
            pending=json_bytes(response(origins.agent.secret,identity,peer,message['payload']))
            session['amqp_payload_bytes']=len(payload)
            delivered=False
            await send(writer,method(60,80,struct.pack('!QB',sequence,0)))
        elif (class_id,method_id)==(60,70) and declared:
            if fields.take(2)!=b'\0\0' or fields.short()!=queue or fields.take(1)!=b'\0':
                raise ValueError('APPLICATION_AMQP_GET_INVALID')
            fields.done()
            if pending is None:
                await send(writer,method(60,72,short(b'')))
            elif delivered:
                raise ValueError('APPLICATION_AMQP_DELIVERY_ALREADY_PENDING')
            else:
                delivered=True
                session['row']['tx_bytes']+=session['amqp_payload_bytes']
                args=struct.pack('!QB',sequence,0)+short(b'')+short(queue)+struct.pack('!I',0)
                await send(writer,method(60,71,args)+content(pending))
        elif (class_id,method_id)==(60,80) and pending is not None and delivered:
            if fields.take(9)!=struct.pack('!QB',sequence,0):
                raise ValueError('APPLICATION_AMQP_ACK_INVALID')
            fields.done()
            pending=None
        elif (class_id,method_id) in ((20,40),(10,50)) and pending is None:
            if fields.take(2)!=struct.pack('!H',200):
                raise ValueError('APPLICATION_AMQP_CLOSE_INVALID')
            fields.short()
            if fields.take(4)!=b'\0'*4:
                raise ValueError('APPLICATION_AMQP_CLOSE_INVALID')
            fields.done()
            await send(writer,method(class_id,method_id+1))
            if class_id==10:
                return
            channel_closed=True
        else:
            raise ValueError('APPLICATION_AMQP_METHOD_UNSUPPORTED')
