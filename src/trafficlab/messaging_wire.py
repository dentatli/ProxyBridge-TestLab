"""Memory-only mail fixtures and bounded MQTT 3.1.1 wire framing."""
from __future__ import annotations
import base64
import hmac
import json
import struct
from trafficlab.protocol import ID, MAX_LINE, json_bytes, mac

MAIL_HEADER = (b'From: testlab@traffic.testlab.invalid\r\nTo: echo@traffic.testlab.invalid\r\n'
    b'Subject: TestLab\r\nMIME-Version: 1.0\r\nContent-Type: application/json\r\nContent-Transfer-Encoding: base64\r\n\r\n')
REQUEST_TOPIC = b'testlab/echo'
RESPONSE_TOPIC = b'testlab/echo/result'
POP_PAYLOAD = bytes(range(256)) * 2


def user_name(run_id, flow_id):
    return base64.b64encode(json_bytes([run_id, flow_id]))


def auth_plain(secret, run_id, flow_id):
    user = user_name(run_id, flow_id)
    return b'\0' + user + b'\0' + mac(secret, b'messaging-auth:', user).encode()


def authenticate(secret, raw):
    if len(raw) > 768:
        raise ValueError('APPLICATION_MESSAGING_AUTH_TOO_LARGE')
    parts = raw.split(b'\0')
    if len(parts) != 3 or parts[0] or not hmac.compare_digest(parts[2], mac(secret,b'messaging-auth:',parts[1]).encode()):
        raise ValueError('APPLICATION_MESSAGING_AUTH_FAILED')
    identity = json.loads(base64.b64decode(parts[1],validate=True))
    if not isinstance(identity,list) or len(identity)!=2 or not all(isinstance(x,str) and ID.fullmatch(x) for x in identity):
        raise ValueError('APPLICATION_MESSAGING_AUTH_IDENTITY_INVALID')
    return tuple(identity)


def mail_encode(message):
    raw = base64.b64encode(message)
    encoded = MAIL_HEADER + b'\r\n'.join(raw[i:i+76] for i in range(0,len(raw),76)) + b'\r\n'
    if len(encoded) > MAX_LINE:
        raise ValueError('APPLICATION_MAIL_TOO_LARGE')
    return encoded


def mail_decode(message):
    if len(message)>MAX_LINE or not message.startswith(MAIL_HEADER) or not message.endswith(b'\r\n'):
        raise ValueError('APPLICATION_MAIL_FORMAT_INVALID')
    lines = message[len(MAIL_HEADER):].split(b'\r\n')
    if any(len(line)>76 for line in lines):
        raise ValueError('APPLICATION_MAIL_LINE_TOO_LARGE')
    return json.loads(base64.b64decode(b''.join(lines),validate=True))


def pop_fixture():
    return mail_encode(json_bytes({'payload':base64.b64encode(POP_PAYLOAD).decode()}))


def mqtt_string(data):
    if len(data)>768:
        raise ValueError('APPLICATION_MQTT_STRING_TOO_LARGE')
    return struct.pack('!H',len(data)) + data


def mqtt_take(data, offset):
    if offset+2>len(data):
        raise ValueError('APPLICATION_MQTT_STRING_TRUNCATED')
    length = struct.unpack('!H',data[offset:offset+2])[0]
    offset += 2
    if offset+length>len(data) or length>768:
        raise ValueError('APPLICATION_MQTT_STRING_TRUNCATED')
    return data[offset:offset+length], offset+length


def mqtt_packet(header, body=b''):
    if len(body)>MAX_LINE:
        raise ValueError('APPLICATION_MQTT_PACKET_TOO_LARGE')
    remaining, length = bytearray(), len(body)
    while True:
        value = length % 128
        length //= 128
        remaining.append(value | (128 if length else 0))
        if not length:
            return bytes([header]) + remaining + body


def mqtt_length(encoded):
    if not encoded or len(encoded)>4 or encoded[-1]&128 or any(not x&128 for x in encoded[:-1]):
        raise ValueError('APPLICATION_MQTT_LENGTH_INVALID')
    length = sum((value&127) << (7*i) for i,value in enumerate(encoded))
    if length>MAX_LINE or len(encoded)>1 and encoded[-1]==0:
        raise ValueError('APPLICATION_MQTT_LENGTH_INVALID')
    return length


def mqtt_publish(data, topic):
    observed, offset = mqtt_take(data,0)
    if observed != topic or offset+2>=len(data):
        raise ValueError('APPLICATION_MQTT_TOPIC_OR_PAYLOAD_INVALID')
    packet_id = data[offset:offset+2]
    if packet_id==b'\0\0':
        raise ValueError('APPLICATION_MQTT_PACKET_ID_INVALID')
    return packet_id, data[offset+2:]
