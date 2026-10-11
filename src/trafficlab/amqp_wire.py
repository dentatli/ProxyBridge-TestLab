"""Bounded AMQP 0-9-1 frames for a single ephemeral queue and confirmed publish/get."""
from __future__ import annotations
import struct
from trafficlab.protocol import MAX_LINE

PROTOCOL = b'AMQP\0\0\x09\x01'


def short(value):
    if len(value)>255:
        raise ValueError('APPLICATION_AMQP_STRING_TOO_LARGE')
    return bytes([len(value)])+value


def long(value):
    if len(value)>MAX_LINE:
        raise ValueError('APPLICATION_AMQP_STRING_TOO_LARGE')
    return struct.pack('!I',len(value))+value


def frame(kind,channel,body):
    if kind not in (1,2,3,8) or channel not in (0,1) or len(body)>MAX_LINE:
        raise ValueError('APPLICATION_AMQP_FRAME_INVALID')
    return struct.pack('!BHI',kind,channel,len(body))+body+b'\xce'


def method(class_id,method_id,args=b''):
    return frame(1,0 if class_id==10 else 1,struct.pack('!HH',class_id,method_id)+args)


def header(raw):
    kind,channel,length=struct.unpack('!BHI',raw)
    if kind not in (1,2,3,8) or channel not in (0,1) or length>MAX_LINE or kind==8 and (channel or length):
        raise ValueError('APPLICATION_AMQP_FRAME_INVALID')
    return kind,channel,length


class Fields:
    def __init__(self,raw):
        self.raw,self.offset=raw,0

    def take(self,length):
        if self.offset+length>len(self.raw):
            raise ValueError('APPLICATION_AMQP_FIELDS_TRUNCATED')
        result=self.raw[self.offset:self.offset+length]
        self.offset+=length
        return result

    def short(self):
        return self.take(self.take(1)[0])

    def long(self):
        length=struct.unpack('!I',self.take(4))[0]
        if length>MAX_LINE:
            raise ValueError('APPLICATION_AMQP_STRING_TOO_LARGE')
        return self.take(length)

    def done(self):
        if self.offset!=len(self.raw):
            raise ValueError('APPLICATION_AMQP_EXTRA_FIELDS')


def content_header(raw):
    fields=Fields(raw)
    class_id,weight,size,flags=struct.unpack('!HHQH',fields.take(14))
    if class_id!=60 or weight or not 0<size<=MAX_LINE or flags not in (0,0x8000):
        raise ValueError('APPLICATION_AMQP_CONTENT_INVALID')
    if flags and fields.short()!=b'application/json':
        raise ValueError('APPLICATION_AMQP_CONTENT_TYPE_INVALID')
    fields.done()
    return size


def content(raw):
    return frame(2,1,struct.pack('!HHQH',60,0,len(raw),0))+frame(3,1,raw)


def start_properties():
    capabilities=short(b'publisher_confirms')+b't\x01'+short(b'basic.nack')+b't\x01'
    return long(short(b'product')+b'S'+long(b'TestLab')+short(b'capabilities')+b'F'+long(capabilities))
