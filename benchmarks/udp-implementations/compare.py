"""Bounded Windows loopback experiment; no product/driver/system changes.

Build commands and scope are in README.md. Source is public; raw evidence goes
to the supplied ignored artifact directory. Public fixed test key only.
"""
from __future__ import annotations
import argparse
import ctypes
import hashlib
import hmac
import json
import os
from pathlib import Path
import platform
import queue
import secrets
import shutil
import socket
import statistics
import struct
import subprocess
import sys
import threading
import time

REPOSITORY = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY/'src'))
from trafficlab.resources import process_sample

KEY = bytes(range(32))  # Public, deliberately reproducible benchmark key.
MAGIC, BODY, SIGNED, PACKET = 0x31424c50, 512, 544, 576


def packet(nonce, sequence=1, flow=0):
    header = struct.pack('<IHHIIQQ', MAGIC, 1, 1, flow, sequence, time.perf_counter_ns(), nonce)
    raw = header + bytes((flow + sequence + i) & 255 for i in range(BODY))
    return raw + hmac.digest(KEY, raw, 'sha256')


class Server:
    def __init__(self, executable: Path, directory: Path):
        self.executable = executable
        self.log = (directory/'server-stderr.log').open('w', encoding='utf-8')
        self.process = subprocess.Popen([str(executable), 'server'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.log, text=True, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW)
        self.lines = queue.Queue()
        def read():
            for line in self.process.stdout:
                self.lines.put(line)
        self.reader = threading.Thread(target=read, daemon=True); self.reader.start()
        try:
            self.ready = self.response()
            assert self.ready['ready'] and self.ready['receive_buffer'] >= 4*1024*1024
        except BaseException:
            self.close()
            raise

    def response(self):
        try: return json.loads(self.lines.get(timeout=5))
        except queue.Empty: raise RuntimeError('BENCH_SERVER_RESPONSE_TIMEOUT') from None

    def command(self, text):
        self.process.stdin.write(text+'\n'); self.process.stdin.flush()
        return self.response()

    def reset(self):
        nonce = secrets.randbits(64) or 1
        assert self.command(f'RESET {nonce:x}')['reset']
        return nonce

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write('STOP\n'); self.process.stdin.flush()
                self.process.wait(timeout=4)
            except (OSError, subprocess.TimeoutExpired):
                self.process.kill(); self.process.wait(timeout=3)
        if self.process.returncode != 0:
            self.log.close()
            raise RuntimeError(f'BENCH_SERVER_EXIT_{self.process.returncode}')
        self.reader.join(timeout=1)
        self.process.stdout.close(); self.process.stdin.close(); self.log.close()


def verify(server):
    nonce = server.reset()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(.15)
        target = ('127.0.0.1', server.ready['port'])
        request = packet(nonce)
        client.sendto(request, target)
        response, sender = client.recvfrom(65535)
        assert sender == target and len(response) == PACKET
        expected = bytearray(request[:SIGNED]); expected[6] = 2
        assert response[:SIGNED] == expected and hmac.compare_digest(response[SIGNED:], hmac.digest(KEY, expected, 'sha256'))
        bad_mac = bytearray(packet(nonce,2)); bad_mac[35] ^= 1
        bad_body = bytearray(packet(nonce,3)); bad_body[35] ^= 1; bad_body[SIGNED:] = hmac.digest(KEY,bad_body[:SIGNED],'sha256')
        samples = [bad_mac,bad_body,packet(nonce^1,4),packet(nonce,5)[:-1]]
        for data in samples:
            client.sendto(data,target)
            try: client.recvfrom(65535)
            except socket.timeout: pass
            else: raise AssertionError('BENCH_ACCEPTED_INVALID_PACKET')
        stats = server.command('STATS')
        assert stats == {'accepted':1,'invalid':4,'send_errors':0}, stats
        return {'valid_reply':True,'bad_mac_rejected':True,'bad_payload_rejected':True,
                'bad_nonce_rejected':True,'bad_length_rejected':True}


def load(executable, server, flows, pps, seconds, nonce):
    return subprocess.Popen([str(executable),'load','--port',str(server.ready['port']), '--nonce',f'{nonce:x}',
        '--flows',str(flows),'--pps',str(pps),'--seconds',str(seconds)], stdout=subprocess.PIPE,stderr=subprocess.PIPE,
        text=True,encoding='utf-8',creationflags=subprocess.CREATE_NO_WINDOW)


def run_load(process):
    stdout,stderr = process.communicate(timeout=15)
    if process.returncode != 0: raise RuntimeError(f'BENCH_LOAD_EXIT_{process.returncode}:{stderr}')
    return json.loads(stdout)


def cpu_seconds(process):
    values = [ctypes.c_ulonglong() for _ in range(4)]
    kernel32 = ctypes.WinDLL('kernel32',use_last_error=True)
    kernel32.GetProcessTimes.argtypes = [ctypes.c_void_p] + [ctypes.POINTER(ctypes.c_ulonglong)]*4
    if not kernel32.GetProcessTimes(int(process._handle), *(ctypes.byref(v)for v in values)):
        raise ctypes.WinError(ctypes.get_last_error())
    return (values[2].value + values[3].value)/10_000_000


def cpu_cycles(process):
    value=ctypes.c_ulonglong()
    kernel32=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel32.QueryProcessCycleTime.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_ulonglong)]
    if not kernel32.QueryProcessCycleTime(int(process._handle),ctypes.byref(value)):
        raise ctypes.WinError(ctypes.get_last_error())
    return value.value


def trial(kind, executable, generator, directory, flows, pps, seconds, probe, warmup_seconds=2):
    directory.mkdir()
    server = Server(executable,directory)
    try:
        verification = verify(server) if probe else None
        warm = run_load(load(generator,server,4,1000,warmup_seconds,server.reset()))
        assert warm['received'] == warm['sent'] and warm['invalid'] == warm['errors'] == 0, warm
        nonce = server.reset()
        baseline = process_sample(server.process.pid,str(executable))
        before = cpu_seconds(server.process)
        cycles_before=cpu_cycles(server.process)
        samples=[]; stop=threading.Event()
        def monitor():
            while not stop.is_set():
                samples.append(process_sample(server.process.pid,str(executable)))
                stop.wait(.02)
        monitor_thread=threading.Thread(target=monitor); monitor_thread.start()
        process=load(generator,server,flows,pps,seconds,nonce)
        try: result=run_load(process)
        finally:
            stop.set();monitor_thread.join(timeout=2)
            if process.poll()is None:process.kill();process.wait(timeout=3)
        after=cpu_seconds(server.process)
        cycles_after=cpu_cycles(server.process)
        generator_cpu=cpu_seconds(process)
        time.sleep(.02)
        stats=server.command('STATS')
        assert result['invalid']==result['duplicates']==result['errors']==0,result
        assert stats['invalid']==stats['send_errors']==0,stats
        assert stats['accepted']>=result['received'],stats
        valid_samples=[v for v in samples if 'private_bytes'in v]
        assert valid_samples and 'private_bytes'in baseline
        row={'implementation':kind,'flows':flows,'pps_per_flow':pps,'seconds':seconds,'result':result,
            'server_stats':stats,'server_cpu_seconds':after-before,'server_cpu_percent_one_core':100*(after-before)/result['elapsed'],
            'server_cpu_percent_pc':100*(after-before)/result['elapsed']/os.cpu_count(),
            'generator_cpu_percent_one_core':100*generator_cpu/result['elapsed'],
            'server_cpu_cycles':cycles_after-cycles_before,
            'cycles_per_accepted_request':(cycles_after-cycles_before)/stats['accepted']if stats['accepted']else None,
            'private_peak_mib':max(v['private_bytes']for v in valid_samples)/1024**2,
            'working_set_peak_mib':max(v['working_set_bytes']for v in valid_samples)/1024**2,
            'private_growth_mib':(max(v['private_bytes']for v in valid_samples)-baseline['private_bytes'])/1024**2,
            'receive_buffer':server.ready['receive_buffer'],'correctness':verification,
            'offered_rate_reached':result['sent']>=.95*result['planned']}
        (directory/'result.json').write_text(json.dumps(row,indent=2),encoding='utf-8')
        (directory/'samples.json').write_text(json.dumps(samples),encoding='utf-8')
        return row
    finally:server.close()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--artifacts',type=Path,required=True);parser.add_argument('--smoke',action='store_true');parser.add_argument('--followup',action='store_true')
    args=parser.parse_args();artifacts=args.artifacts.resolve()
    generator=artifacts/'udp_bench.exe';executables={'C':generator,'C#':artifacts/'csharp/UdpBench.exe'}
    evidence=artifacts/('smoke-'+str(time.time_ns())if args.smoke else 'run-'+str(time.time_ns()));evidence.mkdir()
    inputs=evidence/'inputs';inputs.mkdir()
    shutil.copy2(generator,inputs/'udp_bench.exe')
    shutil.copytree(artifacts/'csharp',inputs/'csharp')
    generator=inputs/'udp_bench.exe';executables={'C':generator,'C#':inputs/'csharp/UdpBench.exe'}
    source_hashes={}
    for name in ('udp_bench.c','compare.py','csharp/Program.cs','csharp/UdpBench.csproj'):
        source=Path(__file__).resolve().parent/name
        target=inputs/'source'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        source_hashes[name]=hashlib.sha256(source.read_bytes()).hexdigest()
    profiles=[(4,100)]if args.smoke else [(128,100),(128,500)]if args.followup else [(32,100),(128,100),(128,500)]
    repetitions=1 if args.smoke else 3
    warmup_seconds=4 if args.followup else 2
    metadata={'platform':platform.platform(),'logical_cpus':os.cpu_count(),'packet_bytes':PACKET,'payload_bytes':BODY,
              'authentication':'HMAC-SHA256; fixed public test key','warmup_seconds':warmup_seconds,'server_network_threads':1,
              'profiles':profiles,'repetitions':repetitions,'cycle_counter_scope':'QueryProcessCycleTime; do not convert to time; same host only',
              'io_model':'one blocking UDP network worker per server; reused packet/address/HMAC state',
              'cpu_scope':'process seconds / generator elapsed; 100% core = one logical CPU; PC divides by CPU count',
              'sources_sha256':source_hashes,
              'installed_runtimes':subprocess.check_output(['dotnet','--list-runtimes'],text=True).strip(),
              'binaries_sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest()for k,v in executables.items()},
              'framework_dll_sha256':hashlib.sha256((inputs/'csharp/UdpBench.dll').read_bytes()).hexdigest()}
    (evidence/'manifest.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    all_rows=[];probed=set();started=time.monotonic()
    for profile,(flows,pps)in enumerate(profiles):
        for repeat in range(repetitions):
            order=['C','C#']if(profile+repeat)%2==0 else['C#','C']
            for kind in order:
                if time.monotonic()-started>210:raise RuntimeError('BENCH_TOTAL_DEADLINE')
                row=trial(kind,executables[kind],generator,evidence/f'{profile}-{repeat}-{kind.replace("#","sharp")}',
                    flows,pps,.5 if args.smoke else 4,kind not in probed,warmup_seconds)
                probed.add(kind);all_rows.append(row)
                (evidence/'results.json').write_text(json.dumps(all_rows,indent=2),encoding='utf-8')
                print(json.dumps({'implementation':kind,'flows':flows,'target_pps':flows*pps,'repeat':repeat,
                    'received':row['result']['received'],'sent':row['result']['sent'],'offered_ok':row['offered_rate_reached'],
                    'p99_ms':row['result']['p99_ms'],'cpu_core':row['server_cpu_percent_one_core'],
                    'private_mib':row['private_peak_mib'],'cycles_per_request':row['cycles_per_accepted_request']}),flush=True)
    print('EVIDENCE='+str(evidence),flush=True)


if __name__=='__main__':main()
