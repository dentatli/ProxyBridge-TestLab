"""Passive, bounded WinDivert control-header diagnostic; never injects packets.

Uses the selected kit's existing WinDivert 2.2 DLL. Flags/layout come from
https://github.com/basil00/WinDivert/blob/v2.2.2/include/windivert.h .
No installation: open only after the controller has observed the product handle.
ACK records are a circular tail; SYN/FIN/RST have a separate bounded history.
No packet payload or raw packet is written. Timings are diagnostic only.
"""
import argparse
from collections import deque
import ctypes as c
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import sys
import threading
import time

DLL_SHA = 'c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
FLAGS = 0x1 | 0x4 | 0x10  # SNIFF | RECV_ONLY | NO_INSTALL
PRIORITIES = {'before_product': 124, 'after_product': 122}
FILTER = (b'ip and tcp and loopback and ip.SrcAddr == 127.0.0.1 and '
          b'ip.DstAddr == 127.0.0.1 and '
          b'(tcp.SrcPort == 54122 or tcp.DstPort == 54122 or '
          b'tcp.SrcPort == 54123 or tcp.DstPort == 54123 or '
          b'tcp.SrcPort == 34010 or tcp.DstPort == 34010) and '
          b'(tcp.Syn or tcp.Fin or tcp.Rst or (tcp.Ack and tcp.PayloadLength == 0))')


class Address(c.Structure):
    _fields_ = [('timestamp', c.c_int64), ('bits', c.c_uint32),
                ('reserved', c.c_uint32), ('network_union', c.c_uint8 * 64)]


def library(path):
    if hashlib.sha256(path.read_bytes()).hexdigest() != DLL_SHA:
        raise ValueError('CLOSE_CAPTURE_DLL_HASH_CHANGED')
    if c.sizeof(Address) != 80 or Address.network_union.offset != 16:
        raise ValueError('CLOSE_CAPTURE_ADDRESS_LAYOUT_CHANGED')
    dll = c.WinDLL(str(path.resolve()), use_last_error=True)
    for name, args, result in (
        ('WinDivertOpen', [c.c_char_p, c.c_int, c.c_int16, c.c_uint64], c.c_void_p),
        ('WinDivertRecv', [c.c_void_p, c.c_void_p, c.c_uint,
                          c.POINTER(c.c_uint), c.POINTER(Address)], c.c_int),
        ('WinDivertShutdown', [c.c_void_p, c.c_int], c.c_int),
        ('WinDivertClose', [c.c_void_p], c.c_int),
        ('WinDivertHelperCompileFilter', [c.c_char_p, c.c_int, c.c_void_p,
                                         c.c_uint, c.POINTER(c.c_char_p),
                                         c.POINTER(c.c_uint)], c.c_int),
    ):
        function = getattr(dll, name)
        function.argtypes, function.restype = args, result
    # WinDivertSend is deliberately neither bound nor called.
    error, position = c.c_char_p(), c.c_uint()
    if not dll.WinDivertHelperCompileFilter(FILTER, 0, None, 0,
                                           c.byref(error), c.byref(position)):
        raise ValueError(f'CLOSE_CAPTURE_FILTER_INVALID_{position.value}_{error.value!r}')
    return dll


def header(packet, address):
    if len(packet) < 40 or packet[0] >> 4 != 4 or packet[9] != 6:
        raise ValueError('CLOSE_CAPTURE_NOT_IPV4_TCP')
    ihl = (packet[0] & 15) * 4
    if ihl < 20 or len(packet) < ihl + 20:
        raise ValueError('CLOSE_CAPTURE_SHORT_HEADER')
    total = struct.unpack_from('!H', packet, 2)[0]
    thl = (packet[ihl + 12] >> 4) * 4
    if thl < 20 or total < ihl + thl or total > len(packet):
        raise ValueError('CLOSE_CAPTURE_INVALID_HEADER_LENGTH')
    source, target, seq, ack = struct.unpack_from('!HHII', packet, ihl)
    flags = packet[ihl + 13]
    return dict(source_ip=socket.inet_ntoa(packet[12:16]),
                destination_ip=socket.inet_ntoa(packet[16:20]),
                source_port=source, destination_port=target, sequence=seq,
                acknowledgment=ack, tcp_flags=flags,
                fin=bool(flags & 1), syn=bool(flags & 2), rst=bool(flags & 4),
                ack=bool(flags & 16), window=struct.unpack_from('!H', packet, ihl + 14)[0],
                payload_bytes=total - ihl - thl, ip_id=struct.unpack_from('!H', packet, 4)[0],
                packet_timestamp_qpc=address.timestamp, observed_qpc_ms=time.perf_counter() * 1000,
                layer=address.bits & 255, network_event=(address.bits >> 8) & 255,
                sniffed=bool(address.bits & (1 << 16)),
                outbound=bool(address.bits & (1 << 17)), loopback=bool(address.bits & (1 << 18)),
                impostor=bool(address.bits & (1 << 19)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dll', type=Path, required=True)
    parser.add_argument('--jsonl-log', type=Path)
    parser.add_argument('--offline-check', action='store_true')
    parser.add_argument('--max-duration-seconds', type=int, default=150)
    args = parser.parse_args()
    dll = library(args.dll)
    if args.offline_check:
        print(json.dumps(dict(status='OFFLINE_API_FILTER_VERIFIED',
                              address_bytes=c.sizeof(Address), flags=FLAGS,
                              priorities=PRIORITIES, dll_sha256=DLL_SHA,
                              handles_opened=0, driver_runtime=False)))
        return 0
    if not args.jsonl_log or not 10 <= args.max_duration_seconds <= 150:
        raise ValueError('CLOSE_CAPTURE_INVALID_ARGUMENTS')
    stop, failed = threading.Event(), threading.Event()
    handles, threads, stats = {}, [], {}
    reason = ['STDIN_STOP']
    invalid = c.c_void_p(-1).value
    # Each thread owns its records; main reads only after joining.
    def receive(side, handle):
        state = stats[side]
        buffer, length, addr = c.create_string_buffer(65575), c.c_uint(), Address()
        while True:
            if not dll.WinDivertRecv(handle, buffer, len(buffer), c.byref(length), c.byref(addr)):
                error = c.get_last_error()
                if stop.is_set() and error == 232:  # drained after SHUTDOWN_RECV
                    return
                state['errors'].append(f'RECV_{error}')
                failed.set(); stop.set()
                return
            try:
                row = header(buffer.raw[:length.value], addr)
                if not row['sniffed'] or not row['loopback'] or row['layer'] != 0:
                    raise ValueError('CLOSE_CAPTURE_ADDRESS_NOT_SNIFFED_LOOPBACK_NETWORK')
                state['received'] += 1
                row.update(event='TCP_HEADER', side=side, record_id=state['received'],
                           priority=PRIORITIES[side], process_id=os.getpid())
                state['tail'].append(row)
                if row['syn'] or row['fin'] or row['rst']:
                    if len(state['critical']) < 512:
                        state['critical'].append(row)
                    else:
                        state['critical_limit_reached'] = True
            except Exception as exc:
                state['errors'].append(str(exc)); failed.set(); stop.set(); return

    def input_stop():
        for line in sys.stdin:
            if line.strip() == 'STOP':
                stop.set(); return
        reason[0] = 'STDIN_EOF'; stop.set()

    with args.jsonl_log.open('x', encoding='utf-8') as log:
        header_bytes = 0
        def emit(value):
            nonlocal header_bytes
            line = json.dumps(value, separators=(',', ':')) + '\n'
            if value.get('event') == 'TCP_HEADER':
                if header_bytes + len(line.encode('utf-8')) > 3 * 1024 * 1024 - 8192:
                    failed.set()
                    return False
                header_bytes += len(line.encode('utf-8'))
            log.write(line); log.flush()
            return True
        try:
            for side, priority in PRIORITIES.items():
                handle = dll.WinDivertOpen(FILTER, 0, priority, FLAGS)
                if handle in (None, invalid):
                    raise OSError(c.get_last_error(), f'CLOSE_CAPTURE_OPEN_FAILED_{side}')
                handles[side] = handle
                stats[side] = dict(received=0, critical=[], tail=deque(maxlen=2048),
                                   critical_limit_reached=False, errors=[])
                thread = threading.Thread(target=receive, args=(side, handle), daemon=True)
                threads.append(thread); thread.start()
            emit(dict(event='LISTENING', process_id=os.getpid(), flags=FLAGS,
                      priorities=PRIORITIES, filter=FILTER.decode(), dll_sha256=DLL_SHA,
                      helper_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      started_qpc_ms=time.perf_counter() * 1000, payloads_saved=False,
                      acknowledgment_history='2048-record circular tail per priority',
                      critical_limit_per_priority=512, queue_loss_observable=False,
                      file_limit_bytes=3 * 1024 * 1024,
                      max_duration_seconds=args.max_duration_seconds))
            threading.Thread(target=input_stop, daemon=True).start()
            if not stop.wait(args.max_duration_seconds):
                reason[0] = 'WATCHDOG_TIMEOUT'; failed.set(); stop.set()
        except Exception as exc:
            failed.set(); stop.set(); emit(dict(event='ERROR', message=str(exc)))
        finally:
            closed_ok = True
            for side, handle in handles.items():
                if not dll.WinDivertShutdown(handle, 1):
                    failed.set(); stats[side]['errors'].append(f'SHUTDOWN_{c.get_last_error()}')
            for thread in threads:
                thread.join(5)
            for side, handle in handles.items():
                if not dll.WinDivertClose(handle):
                    closed_ok = False
                    failed.set(); stats[side]['errors'].append(f'CLOSE_{c.get_last_error()}')
            for thread in threads:
                thread.join(1)
                if thread.is_alive():
                    closed_ok = False
                    failed.set()
            for side, state in stats.items():
                if any(thread.is_alive() for thread in threads):
                    continue  # no concurrent read of a still-mutating record buffer
                records = {r['record_id']: r for r in state['critical']}
                records.update({r['record_id']: r for r in state['tail']})
                saved = sum(emit(row) for row in sorted(records.values(), key=lambda r: r['record_id']))
                emit(dict(event='CAPTURE_SUMMARY', side=side, received=state['received'],
                          records_saved=saved, file_limit_reached=(saved != len(records)),
                          critical_saved=len(state['critical']),
                          critical_limit_reached=state['critical_limit_reached'],
                          ack_tail_overwritten=max(0, state['received'] - 2048),
                          errors=state['errors'], queue_loss_observable=False))
                if state['critical_limit_reached']:
                    failed.set()
            emit(dict(event='STOPPED', process_id=os.getpid(), reason=reason[0],
                      handles_closed=closed_ok, capture_success=(not failed.is_set()), packet_injection=False,
                      full_packet_history=False, diagnostic_only=True))
    return int(failed.is_set())


if __name__ == '__main__':
    raise SystemExit(main())
