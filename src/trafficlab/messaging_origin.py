"""Isolated SMTP/IMAP/MQTT subset; no external mail delivery or persistent broker."""
from __future__ import annotations
import asyncio
import base64
import json
import hashlib
import re
from trafficlab.application_wire import response, request
from trafficlab.protocol import MAX_LINE, json_bytes
from trafficlab.messaging_wire import (authenticate, mail_decode, mqtt_length, mqtt_packet, mqtt_publish,
    mqtt_string, mqtt_take, REQUEST_TOPIC, RESPONSE_TOPIC, POP_PAYLOAD, pop_fixture)


async def line(reader, limit=1024):
    raw = await asyncio.wait_for(reader.readline(),5)
    if not raw.endswith(b'\r\n') or len(raw)>limit:
        raise ValueError('APPLICATION_MESSAGING_LINE_INVALID')
    return raw[:-2]


async def send(writer, data):
    writer.write(data)
    await writer.drain()


async def packet(reader):
    header = (await asyncio.wait_for(reader.readexactly(1),5))[0]
    encoded = bytearray()
    for _ in range(4):
        encoded.extend(await asyncio.wait_for(reader.readexactly(1),5))
        if not encoded[-1]&128:
            length = mqtt_length(encoded)
            return header, await asyncio.wait_for(reader.readexactly(length),5)
    raise ValueError('APPLICATION_MQTT_LENGTH_INVALID')


def exchange(origins, message, kind, peer, session, user):
    if (message['identity']['run_id'],message['identity']['flow_id']) != user:
        raise ValueError('APPLICATION_MESSAGING_IDENTITY_CHANGED')
    value, row, payload = origins.authenticate(message,kind,peer,session)
    row['rx_bytes'] += len(payload)
    receipt = response(origins.agent.secret,value,peer)
    return row, payload, receipt


async def smtp(origins, reader, writer, kind, session, peer):
    await send(writer,b'220 traffic.testlab.invalid TestLab\r\n')
    user, greeted, sender, recipient = None, False, False, False
    while True:
        command = await line(reader)
        verb, separator, argument = command.partition(b' ')
        command = verb.upper() + separator + argument
        if command.startswith(b'EHLO '):
            greeted = True
            await send(writer,b'250-traffic.testlab.invalid\r\n250 AUTH PLAIN\r\n')
        elif command.startswith(b'AUTH PLAIN ') and greeted and user is None:
            user = authenticate(origins.agent.secret,base64.b64decode(command[11:],validate=True))
            await send(writer,b'235 2.7.0 Authenticated\r\n')
        elif command == b'MAIL FROM:<testlab@traffic.testlab.invalid>' and user:
            sender, recipient = True, False
            await send(writer,b'250 2.1.0 Sender accepted\r\n')
        elif command == b'RCPT TO:<echo@traffic.testlab.invalid>' and sender:
            recipient = True
            await send(writer,b'250 2.1.5 Recipient accepted\r\n')
        elif command.startswith(b'RCPT TO:'):
            await send(writer,b'550 5.7.1 External delivery denied\r\n')
        elif command == b'DATA' and recipient:
            await send(writer,b'354 Send mail data\r\n')
            raw = bytearray()
            while True:
                part = await line(reader)
                if part == b'.':
                    break
                if part.startswith(b'..'):
                    part = part[1:]
                raw.extend(part + b'\r\n')
                if len(raw)>MAX_LINE:
                    raise ValueError('APPLICATION_MAIL_TOO_LARGE')
            _, _, receipt = exchange(origins,mail_decode(bytes(raw)),kind,peer,session,user)
            reply = b'250 ' + base64.b64encode(json_bytes(receipt)) + b'\r\n'
            if len(reply)>512:
                raise ValueError('APPLICATION_SMTP_RECEIPT_TOO_LARGE')
            await send(writer,reply)
            sender = recipient = False
        elif command == b'RSET':
            sender = recipient = False
            await send(writer,b'250 Reset\r\n')
        elif command == b'QUIT':
            await send(writer,b'221 2.0.0 Closing\r\n')
            return
        else:
            await send(writer,b'503 5.5.1 Unsupported command or sequence\r\n')


async def imap(origins, reader, writer, kind, session, peer):
    await send(writer,b'* OK TestLab IMAP4rev1\r\n')
    user, selected, stored, receipt, deleted = None, False, None, None, False
    while True:
        raw = await line(reader)
        tag, separator, command = raw.partition(b' ')
        if not separator or not re.fullmatch(rb'[A-Za-z0-9]{1,32}',tag):
            raise ValueError('APPLICATION_IMAP_TAG_INVALID')
        if command == b'CAPABILITY':
            await send(writer,b'* CAPABILITY IMAP4rev1 AUTH=PLAIN SASL-IR\r\n' + tag + b' OK Capability\r\n')
        elif command.startswith(b'AUTHENTICATE PLAIN') and user is None:
            if command == b'AUTHENTICATE PLAIN':
                await send(writer,b'+ \r\n')
                auth = await line(reader)
            elif command.startswith(b'AUTHENTICATE PLAIN '):
                auth = command[19:]
            else:
                raise ValueError('APPLICATION_IMAP_AUTH_INVALID')
            user = authenticate(origins.agent.secret,base64.b64decode(auth,validate=True))
            await send(writer,tag + b' OK Authenticated\r\n')
        elif command in (b'SELECT INBOX',b'SELECT "INBOX"') and user:
            selected = True
            await send(writer,b'* FLAGS (\\Deleted)\r\n* 0 RECENT\r\n* ' + (b'1' if stored else b'0') + b' EXISTS\r\n' + tag + b' OK [READ-WRITE] Selected\r\n')
        elif command.startswith(b'APPEND ') and user:
            match = re.fullmatch(rb'APPEND (?:INBOX|"INBOX") \{([0-9]{1,5})\}',command)
            if not match or stored is not None or not 0<int(match[1])<=MAX_LINE:
                raise ValueError('APPLICATION_IMAP_APPEND_INVALID')
            await send(writer,b'+ Ready for literal\r\n')
            stored = await asyncio.wait_for(reader.readexactly(int(match[1])),5)
            if await asyncio.wait_for(reader.readexactly(2),5) != b'\r\n':
                raise ValueError('APPLICATION_IMAP_LITERAL_INVALID')
            _, payload, receipt = exchange(origins,mail_decode(stored),kind,peer,session,user)
            session['mail_payload_bytes'] = len(payload)
            if selected:
                await send(writer,b'* 1 EXISTS\r\n')
            await send(writer,tag + b' OK Appended\r\n')
        elif command in (b'FETCH 1 BODY.PEEK[]',b'FETCH 1 (BODY.PEEK[])',b'FETCH 1 (BODY[])') and selected and stored:
            session['row']['tx_bytes'] += session['mail_payload_bytes']
            await send(writer,b'* 1 FETCH (BODY[] {' + str(len(stored)).encode() + b'}\r\n' + stored + b')\r\n' +
                tag + b' OK TestLab-Receipt ' + base64.b64encode(json_bytes(receipt)) + b'\r\n')
        elif command == b'STORE 1 +FLAGS (\\Deleted)' and selected and stored:
            deleted = True
            await send(writer,b'* 1 FETCH (FLAGS (\\Deleted))\r\n' + tag + b' OK Stored\r\n')
        elif command == b'EXPUNGE' and selected and deleted:
            stored = receipt = None
            deleted = False
            await send(writer,b'* 1 EXPUNGE\r\n' + tag + b' OK Expunged\r\n')
        elif command == b'LOGOUT':
            await send(writer,b'* BYE Logging out\r\n' + tag + b' OK Logout\r\n')
            return
        else:
            await send(writer,tag + b' BAD Unsupported command or mailbox\r\n')


async def mqtt(origins, reader, writer, kind, session, peer):
    header, body = await packet(reader)
    protocol, offset = mqtt_take(body,0)
    if header!=0x10 or protocol!=b'MQTT' or body[offset:offset+2]!=b'\x04\xc2' or len(body)<offset+4:
        raise ValueError('APPLICATION_MQTT_CONNECT_INVALID')
    offset += 4  # protocol level, clean-session + username/password flags, keepalive
    client_id, offset = mqtt_take(body,offset)
    username, offset = mqtt_take(body,offset)
    password, offset = mqtt_take(body,offset)
    if offset!=len(body) or not client_id:
        raise ValueError('APPLICATION_MQTT_CONNECT_INVALID')
    user = authenticate(origins.agent.secret,b'\0' + username + b'\0' + password)
    await send(writer,mqtt_packet(0x20,b'\0\0'))
    subscribed, pending = False, None
    while True:
        header, body = await packet(reader)
        if header==0x82 and pending is None:
            if len(body)<3 or body[:2]==b'\0\0':
                raise ValueError('APPLICATION_MQTT_SUBSCRIBE_INVALID')
            topic, offset = mqtt_take(body,2)
            if topic!=RESPONSE_TOPIC or body[offset:]!=b'\x01':
                raise ValueError('APPLICATION_MQTT_TOPIC_DENIED')
            subscribed = True
            await send(writer,mqtt_packet(0x90,body[:2]+b'\x01'))
        elif header==0x32 and subscribed and pending is None:
            packet_id, raw = mqtt_publish(body,REQUEST_TOPIC)
            message = json.loads(raw)
            row, payload, _ = exchange(origins,message,kind,peer,session,user)
            identity = {key:value for key,value in message['identity'].items() if key != 'proof'}
            reply = json_bytes(response(origins.agent.secret,identity,peer,message['payload']))
            row['tx_bytes'] += len(payload)
            pending = packet_id
            await send(writer,mqtt_packet(0x40,packet_id)+mqtt_packet(0x32,mqtt_string(RESPONSE_TOPIC)+packet_id+reply))
        elif header==0x40 and pending is not None and body==pending:
            pending = None
        elif header==0xc0 and not body:
            await send(writer,mqtt_packet(0xd0))
        elif header==0xe0 and not body and pending is None:
            return
        else:
            raise ValueError('APPLICATION_MQTT_PACKET_OR_SEQUENCE_INVALID')


async def serve(origins, reader, writer, kind, session, peer):
    handler = smtp if kind in ('smtp','smtps') else imap if kind in ('imap','imaps') else pop if kind in ('pop3','pop3s') else mqtt
    await handler(origins,reader,writer,kind,session,peer)


async def pop(origins, reader, writer, kind, session, peer):
    await send(writer,b'+OK TestLab POP3\r\n')
    username, user, deleted, sequence = None, None, False, 0
    fixture = pop_fixture()
    while True:
        raw = await line(reader,512)
        verb, separator, argument = raw.partition(b' ')
        command = verb.upper() + separator + argument
        if command.startswith(b'USER ') and user is None:
            username = command[5:]
            await send(writer,b'+OK Password required\r\n')
        elif command.startswith(b'PASS ') and username is not None and user is None:
            user = authenticate(origins.agent.secret,b'\0'+username+b'\0'+command[5:])
            await send(writer,b'+OK Maildrop ready\r\n')
        elif command == b'CAPA':
            await send(writer,b'+OK Capabilities\r\nUSER\r\nUIDL\r\n.\r\n')
        elif command == b'STAT' and user:
            await send(writer,b'+OK '+(b'0 0' if deleted else b'1 '+str(len(fixture)).encode())+b'\r\n')
        elif command in (b'LIST',b'UIDL') and user:
            value = b'' if deleted else b'1 '+(str(len(fixture)).encode() if command==b'LIST' else hashlib.sha256(fixture).hexdigest().encode())+b'\r\n'
            await send(writer,b'+OK Listing\r\n'+value+b'.\r\n')
        elif command in (b'LIST 1',b'UIDL 1') and user and not deleted:
            await send(writer,b'+OK 1 '+(str(len(fixture)).encode() if command==b'LIST 1' else hashlib.sha256(fixture).hexdigest().encode())+b'\r\n')
        elif command == b'RETR 1' and user and not deleted:
            value = request(origins.agent.secret,kind,*user,sequence,hashlib.sha256(POP_PAYLOAD).hexdigest())
            message = {'identity':value,'payload':base64.b64encode(POP_PAYLOAD).decode()}
            identity, row, _ = origins.authenticate(message,kind,peer,session)
            row['tx_bytes'] += len(POP_PAYLOAD)
            receipt = response(origins.agent.secret,identity,peer)
            await send(writer,b'+OK '+base64.b64encode(json_bytes(receipt))+b'\r\n'+fixture+b'.\r\n')
            sequence += 1
        elif command == b'DELE 1' and user and not deleted:
            deleted = True
            await send(writer,b'+OK Marked deleted\r\n')
        elif command == b'RSET' and user:
            deleted = False
            await send(writer,b'+OK Reset\r\n')
        elif command == b'NOOP' and user:
            await send(writer,b'+OK\r\n')
        elif command == b'QUIT':
            await send(writer,b'+OK Closing\r\n')
            return
        else:
            await send(writer,b'-ERR Unsupported command or message\r\n')
