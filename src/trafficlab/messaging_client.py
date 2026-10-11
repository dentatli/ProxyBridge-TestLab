"""Native SMTP acceptance, IMAP append/fetch and MQTT QoS1, with signed all-flow proofs."""
from __future__ import annotations
import base64
import hashlib
import json
import re
import socket
import ssl
import struct
import time
from trafficlab.application_wire import APPLICATION_PORTS, SERVER_NAME, request, verify_response
from trafficlab.protocol import MAX_LINE, Histogram, json_bytes
from trafficlab.messaging_wire import (auth_plain, mail_encode, mqtt_length, mqtt_packet, mqtt_publish,
    mqtt_string, REQUEST_TOPIC, RESPONSE_TOPIC)


def exact(stream, size):
    raw = stream.read(size)
    if len(raw)!=size:
        raise EOFError('APPLICATION_MESSAGING_TRUNCATED')
    return raw


def line(stream, limit=1024):
    raw = stream.readline(limit+1)
    if not raw.endswith(b'\r\n') or len(raw)>limit:
        raise ValueError('APPLICATION_MESSAGING_LINE_INVALID')
    return raw[:-2]


class SmtpClient:
    def __init__(self,sock,stream,auth):
        self.sock,self.stream=sock,stream
        self.reply(b'220')
        self.command(b'EHLO traffic.testlab.invalid',b'250')
        self.command(b'AUTH PLAIN '+base64.b64encode(auth),b'235')

    def reply(self,code):
        for _ in range(16):
            value=line(self.stream,512)
            if value[:3]!=code or value[3:4] not in (b' ',b'-'):
                raise ValueError('APPLICATION_SMTP_STATUS_INVALID')
            if value[3:4]==b' ':
                return value[4:]
        raise ValueError('APPLICATION_SMTP_REPLY_TOO_LARGE')

    def command(self,command,code):
        self.sock.sendall(command+b'\r\n')
        return self.reply(code)

    def exchange(self,message):
        self.command(b'MAIL FROM:<testlab@traffic.testlab.invalid>',b'250')
        self.command(b'RCPT TO:<echo@traffic.testlab.invalid>',b'250')
        self.command(b'DATA',b'354')
        self.sock.sendall(mail_encode(message)+b'.\r\n')
        return json.loads(base64.b64decode(self.reply(b'250'),validate=True))

    def close(self):
        self.command(b'QUIT',b'221')


class ImapClient:
    def __init__(self,sock,stream,auth):
        self.sock,self.stream,self.sequence=sock,stream,0
        if not line(stream).startswith(b'* OK '):
            raise ValueError('APPLICATION_IMAP_GREETING_INVALID')
        self.command(b'AUTHENTICATE PLAIN '+base64.b64encode(auth))
        self.command(b'SELECT INBOX')

    def command(self,command,literal=None):
        self.sequence+=1
        tag=f'A{self.sequence}'.encode()
        self.sock.sendall(tag+b' '+command+b'\r\n')
        if literal is not None:
            if not line(self.stream).startswith(b'+ '):
                raise ValueError('APPLICATION_IMAP_LITERAL_REJECTED')
            self.sock.sendall(literal+b'\r\n')
        stored=None
        for _ in range(16):
            value=line(self.stream)
            match=re.fullmatch(rb'\* 1 FETCH \(BODY\[\] \{([0-9]{1,5})\}',value)
            if match:
                size=int(match[1])
                if stored is not None or not 0<size<=MAX_LINE:
                    raise ValueError('APPLICATION_IMAP_LITERAL_INVALID')
                stored=exact(self.stream,size)
                if line(self.stream)!=b')':
                    raise ValueError('APPLICATION_IMAP_LITERAL_INVALID')
            elif value.startswith(tag+b' '):
                if not value.startswith(tag+b' OK '):
                    raise ValueError('APPLICATION_IMAP_STATUS_INVALID')
                return stored,value[len(tag)+4:]
            elif not value.startswith(b'* '):
                raise ValueError('APPLICATION_IMAP_RESPONSE_INVALID')
        raise ValueError('APPLICATION_IMAP_RESPONSE_TOO_LARGE')

    def exchange(self,message):
        encoded=mail_encode(message)
        self.command(b'APPEND INBOX {'+str(len(encoded)).encode()+b'}',encoded)
        stored,receipt=self.command(b'FETCH 1 BODY.PEEK[]')
        if stored!=encoded or not receipt.startswith(b'TestLab-Receipt '):
            raise ValueError('APPLICATION_MAIL_CONTENT_OR_RECEIPT_CHANGED')
        returned=json.loads(base64.b64decode(receipt[16:],validate=True))
        self.command(b'STORE 1 +FLAGS (\\Deleted)')
        self.command(b'EXPUNGE')
        return returned

    def close(self):
        self.command(b'LOGOUT')


class MqttClient:
    def __init__(self,sock,stream,auth):
        self.sock,self.stream,self.sequence=sock,stream,1
        _,username,password=auth.split(b'\0')
        body=mqtt_string(b'MQTT')+b'\x04\xc2\x00\x05'+mqtt_string(b'testlab-'+hashlib.sha256(username).hexdigest()[:16].encode())+mqtt_string(username)+mqtt_string(password)
        sock.sendall(mqtt_packet(0x10,body))
        if self.packet()!=(0x20,b'\0\0'):
            raise ValueError('APPLICATION_MQTT_CONNECT_REJECTED')
        sock.sendall(mqtt_packet(0x82,b'\0\x01'+mqtt_string(RESPONSE_TOPIC)+b'\x01'))
        if self.packet()!=(0x90,b'\0\x01\x01'):
            raise ValueError('APPLICATION_MQTT_SUBSCRIBE_REJECTED')

    def packet(self):
        header=exact(self.stream,1)[0]
        encoded=bytearray()
        for _ in range(4):
            encoded.extend(exact(self.stream,1))
            if not encoded[-1]&128:
                return header,exact(self.stream,mqtt_length(encoded))
        raise ValueError('APPLICATION_MQTT_LENGTH_INVALID')

    def exchange(self,message):
        self.sequence=self.sequence%65535+1
        packet_id=struct.pack('!H',self.sequence)
        self.sock.sendall(mqtt_packet(0x32,mqtt_string(REQUEST_TOPIC)+packet_id+message))
        acknowledged,returned=False,None
        for _ in range(2):
            header,body=self.packet()
            if header==0x40 and body==packet_id and not acknowledged:
                acknowledged=True
            elif header==0x32 and returned is None:
                reply_id,raw=mqtt_publish(body,RESPONSE_TOPIC)
                if reply_id!=packet_id:
                    raise ValueError('APPLICATION_MQTT_PACKET_ID_CHANGED')
                returned=json.loads(raw)
                self.sock.sendall(mqtt_packet(0x40,reply_id))
            else:
                raise ValueError('APPLICATION_MQTT_ACK_OR_PAYLOAD_INVALID')
        if not acknowledged or returned is None:
            raise ValueError('APPLICATION_MQTT_ACK_OR_PAYLOAD_INVALID')
        return returned

    def close(self):
        self.sock.sendall(mqtt_packet(0xc0))
        if self.packet()!=(0xd0,b''):
            raise ValueError('APPLICATION_MQTT_FINAL_ACK_UNVERIFIED')
        self.sock.sendall(mqtt_packet(0xe0))
        if self.stream.read(1)!=b'':
            raise ValueError('APPLICATION_MQTT_CLOSE_INVALID')


def messaging_flow(job,flow_id):
    from trafficlab.worker import cancelled
    kind,secret=job['application'],bytes.fromhex(job['secret'])
    result={'flow_id':flow_id,'application':kind,'complete':False,'errors':[],'tx_bytes':0,'rx_bytes':0,
        'verified_transactions':0,'peer_observed_by_origin':None}
    started=time.perf_counter()
    histogram,connection_latency=Histogram(),Histogram()
    sock=stream=None
    try:
        target={**job,'port':job.get('application_ports',APPLICATION_PORTS)[kind]}
        sock=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
        if job.get('test_proxy'):
            from trafficlab.socks_client import negotiate
            negotiate(sock,target)
        else:
            sock.connect((job['host'],target['port']))
        secure=kind in ('smtps','imaps','mqtts')
        if secure:
            identity=job['application_identity']
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.minimum_version=ssl.TLSVersion.TLSv1_2
            context.load_verify_locations(cadata=identity['tls_ca_pem'])
            context.set_alpn_protocols(['mqtt' if kind=='mqtts' else 'testlab-mail/1'])
            sock=context.wrap_socket(sock,server_hostname=SERVER_NAME)
            observed=hashlib.sha256(sock.getpeercert(binary_form=True)).hexdigest()
            expected='mqtt' if kind=='mqtts' else 'testlab-mail/1'
            if observed!=identity['tls_certificate_sha256'] or sock.selected_alpn_protocol()!=expected:
                raise ValueError('APPLICATION_TLS_IDENTITY_OR_ALPN_CHANGED')
            result.update(tls_version=sock.version(),cipher=sock.cipher()[0],certificate_sha256=observed,
                certificate_verified=True,server_name=SERVER_NAME,alpn=expected)
        stream=sock.makefile('rb')
        client_type=SmtpClient if kind in ('smtp','smtps') else ImapClient if kind in ('imap','imaps') else MqttClient
        client=client_type(sock,stream,auth_plain(secret,job['run_id'],flow_id))
        result['messaging_protocol']='SMTP' if client_type is SmtpClient else 'IMAP4rev1' if client_type is ImapClient else 'MQTT 3.1.1 QoS1'
        connection_latency.add((time.perf_counter()-started)*1000)
        deadline,next_send,sequence=time.perf_counter()+job['seconds'],time.perf_counter(),0
        while time.perf_counter()<deadline and not cancelled(job):
            payload=bytes((i+sequence)%256 for i in range(job.get('message_bytes',512)))
            value=request(secret,kind,job['run_id'],flow_id,sequence,hashlib.sha256(payload).hexdigest())
            message=json_bytes({'identity':value,'payload':base64.b64encode(payload).decode()})
            stamp=time.perf_counter()
            returned=client.exchange(message)
            if client_type is MqttClient and base64.b64decode(returned.get('payload',''),validate=True)!=payload:
                raise ValueError('APPLICATION_ECHO_PAYLOAD_MISMATCH')
            peer=verify_response(secret,value,returned)
            if result['peer_observed_by_origin'] not in (None,peer):
                raise ValueError('APPLICATION_ORIGIN_PEER_CHANGED')
            result['peer_observed_by_origin']=peer
            result['verified_transactions']+=1
            result['tx_bytes']+=len(payload)
            result['rx_bytes']+=0 if client_type is SmtpClient else len(payload)
            histogram.add((time.perf_counter()-stamp)*1000)
            sequence+=1
            next_send+=1/job.get('rate_packets_per_second',100)
            while time.perf_counter()<min(deadline,next_send) and not cancelled(job):
                time.sleep(min(.05,max(0,min(deadline,next_send)-time.perf_counter())))
        client.close()
        stream.close(); stream=None
        if secure:
            sock=sock.unwrap()
        elif sock.recv(1)!=b'':
            raise ValueError('APPLICATION_MESSAGING_CLOSE_INVALID')
        result['close_verified']=True
        result['complete']=result['verified_transactions']>0 and not cancelled(job)
    except Exception as error:
        code=str(error) if isinstance(error,ValueError) and str(error).startswith('APPLICATION_') else 'APPLICATION_MESSAGING_TRANSPORT_FAILED'
        result['errors'].append(type(error).__name__+':'+code)
        if isinstance(error,OSError):
            result.update(socket_errno=error.errno,socket_winerror=getattr(error,'winerror',None))
    finally:
        if stream is not None:
            stream.close()
        if sock is not None:
            sock.close()
    result.update(elapsed_seconds=time.perf_counter()-started,latency=histogram.view(),connection_and_authentication_ms=connection_latency.view())
    return result
