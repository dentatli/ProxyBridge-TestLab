"""Drain only the isolated v4 telemetry IOCTL; never configure or start a driver."""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import sys
import threading
import time

MAGIC=0x50424b34
VERSION=4
CAPACITY=8192
IOCTL=0x002263c0
FIELDS=('pid reason enabled rights_in rights_out action_in action_out redirect_present redirect_state '
        'acquire_called acquire_status writable_called writable_status req_present allocation_attempted allocation_present '
        'context_size context_pid context_family context_protocol target_pid handle_present apply_called apply_returned '
        'local_v4 remote_v4 local_port remote_port new_v4 new_port').split()

class Event(C.LittleEndianStructure):
    _pack_=8
    _fields_=[(n,C.c_uint64) for n in ('seq','start_qpc','end_qpc','frequency')]+[(n,C.c_uint32) for n in FIELDS]

class Header(C.LittleEndianStructure):
    _pack_=8
    _fields_=[(n,C.c_uint32) for n in ('magic','version','record_size','count','capacity','reserved')]+[
        (n,C.c_uint64) for n in ('written','overwritten','remaining','frequency')]

assert C.sizeof(Event)==152 and C.sizeof(Header)==56

def parse_batch(data):
    if len(data)<C.sizeof(Header):raise ValueError('KERNEL_HEADER_SHORT')
    h=Header.from_buffer_copy(data)
    header={n:getattr(h,n) for n,_ in h._fields_}
    if (h.magic,h.version,h.record_size,h.capacity,h.reserved)!=(MAGIC,VERSION,C.sizeof(Event),CAPACITY,0):
        raise ValueError('KERNEL_ABI_DIFFERS')
    if h.count>64 or h.remaining>CAPACITY or not h.frequency or h.overwritten>h.written or h.count+h.remaining+h.overwritten>h.written:
        raise ValueError('KERNEL_COUNTERS_INVALID')
    if len(data)!=C.sizeof(Header)+h.count*C.sizeof(Event):raise ValueError('KERNEL_LENGTH_DIFFERS')
    events=[]
    for i in range(h.count):
        e=Event.from_buffer_copy(data,C.sizeof(Header)+i*C.sizeof(Event))
        if not e.seq or e.seq>h.written or e.frequency!=h.frequency or e.end_qpc<e.start_qpc or not e.start_qpc:
            raise ValueError('KERNEL_EVENT_INVALID')
        events.append({n:getattr(e,n) for n,_ in e._fields_})
    return header,events

def collect(path, maximum_seconds=720):
    k=C.WinDLL('kernel32',use_last_error=True)
    k.CreateFileW.argtypes=[C.c_wchar_p,C.c_uint32,C.c_uint32,C.c_void_p,C.c_uint32,C.c_uint32,C.c_void_p];k.CreateFileW.restype=C.c_void_p
    k.DeviceIoControl.argtypes=[C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint32,C.POINTER(C.c_uint32),C.c_void_p];k.DeviceIoControl.restype=C.c_int
    k.CloseHandle.argtypes=[C.c_void_p];k.CloseHandle.restype=C.c_int
    handle=k.CreateFileW(r'\\.\ProxyBridgeDrv',0x80000000,3,None,3,0,None)
    if handle==C.c_void_p(-1).value:raise OSError(C.get_last_error(),'KERNEL_DIAGNOSTIC_DEVICE_OPEN_FAILED')
    stop=threading.Event();requested=threading.Event()
    def input_thread():
        # EOF means the owner disappeared; capture a bounded tail and exit with a failure receipt.
        for line in sys.stdin:
            if line.strip()=='STOP':requested.set();stop.set();return
        stop.set()
    thread=threading.Thread(target=input_thread,daemon=True);thread.start()
    last_seq=total=written_bytes=0;last_header=None;start=time.monotonic();tail_batches=0
    try:
        with path.open('x',encoding='utf-8') as output:
            def emit(row):
                nonlocal written_bytes
                text=json.dumps(row,separators=(',',':'))+'\n';written_bytes+=len(text.encode('utf-8'))
                if written_bytes>24*1024*1024:raise ValueError('KERNEL_LOG_SIZE_LIMIT')
                output.write(text);output.flush()
            ready=False
            while True:
                buffer=C.create_string_buffer(C.sizeof(Header)+64*C.sizeof(Event));got=C.c_uint32()
                if not k.DeviceIoControl(handle,IOCTL,None,0,buffer,len(buffer),C.byref(got),None):
                    raise OSError(C.get_last_error(),'KERNEL_DIAGNOSTIC_DRAIN_FAILED')
                header,events=parse_batch(buffer.raw[:got.value])
                if last_header and (header['written']<last_header['written'] or header['overwritten']<last_header['overwritten'] or header['frequency']!=last_header['frequency']):
                    raise ValueError('KERNEL_COUNTERS_REGRESSED')
                if not ready:
                    if header['written'] or header['count'] or header['remaining'] or header['overwritten']:
                        raise ValueError('KERNEL_RING_NOT_FRESH')
                    emit(dict(event='LISTENING',method='redirect-kernel-context-v4',pid=os.getpid(),header=header,initial_backlog=header['count']+header['remaining']))
                    ready=True
                for event in events:
                    if event['seq']!=last_seq+1:raise ValueError('KERNEL_SEQUENCE_GAP')
                    total+=1;last_seq=event['seq']
                    if total>12000:raise ValueError('KERNEL_EVENT_LIMIT')
                    emit(dict(event='CLASSIFY',record=event))
                last_header=header
                if header['overwritten']:raise ValueError('KERNEL_RECORDS_LOST')
                if stop.is_set():
                    tail_batches+=1
                    if not header['remaining']:
                        if total!=header['written']:raise ValueError('KERNEL_FINAL_COUNT_DIFFERS')
                        emit(dict(event='STOPPED',pid=os.getpid(),requested=requested.is_set(),records=total,header=header))
                        if not requested.is_set():raise ValueError('KERNEL_COLLECTOR_OWNER_EOF')
                        return
                    if tail_batches>=128:raise ValueError('KERNEL_TAIL_NOT_DRAINED')
                if time.monotonic()-start>maximum_seconds:raise ValueError('KERNEL_COLLECTOR_WATCHDOG')
                if not header['remaining']:stop.wait(.05)
    finally:k.CloseHandle(handle)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--jsonl-log',type=Path);p.add_argument('--schema',action='store_true');a=p.parse_args()
    if a.schema:print(json.dumps(dict(method='redirect-kernel-context-v4',event_size=C.sizeof(Event),header_size=C.sizeof(Header),capacity=CAPACITY,ioctl=IOCTL,read_only=True)));return 0
    if not a.jsonl_log:p.error('--jsonl-log is required')
    try:collect(a.jsonl_log)
    except Exception as error:
        print(str(error),file=sys.stderr);return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
