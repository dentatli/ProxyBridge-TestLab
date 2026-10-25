# Small C / C# UDP implementation comparison

This is an isolated Windows loopback experiment, **not a replacement engine**,
product test, protocol coverage suite or maximum-throughput claim. It never loads
ProxyBridge or a driver and does not change system settings. Keep the production
lab idle and driver stopped before running it. Expected measured suite duration
is about two minutes (hard launch budget210seconds), below the five-minute
development-check allowance. Do not run alongside diagnostic traffic/debugger work.

Both receivers use one dedicated blocking UDP worker,4MiB receive/send buffers,
reused packet/address/hash objects and the same512-byte payload. The576-byte wire
packet has a32-byte little-endian header and32-byte HMAC-SHA256 tag. Header fields:
magic0x31424c50,version1,kind1=request/2=response,flow(u32),sequence(u32),QPC ticks(u64),
run nonce(u64). Payload byte i is(flow+sequence+i)mod256. The fixed public test key
is bytes0..31; it is not a production secret. Replies must preserve every field
except kind and recompute the HMAC. C uses reusable Windows CNG HMAC; C# uses a
reused HMACSHA256 instance and Span/SocketAddress APIs. Neither creates per-packet
application buffer/address objects. This compares these implementations/toolchains,
not an abstract language or identical crypto API wrappers.

The **same C generator** drives both receivers through32 or128 real UDP sockets,
paces aggregate requests, validates source/run/flow/sequence/payload/HMAC and
detects duplicate replies. Profiles:3200,12800,64000 requests/s,4seconds each,
3 repeats per implementation. Order alternates across repeats/profiles. Every
fresh receiver gets2seconds of identical warmup (4000requests/s). Correctness
probes independently use Python HMAC: valid exchange and rejection of bad MAC,
bad payload with valid MAC, wrong nonce and short frame. Python orchestrates and
samples resources only; it is not in the measured packet path.

The generator must reach95% of offered rate for a profile to be usable; otherwise
report generator limitation instead of attributing its missed target to a server.
Report loss as(sent-received)/sent separately from offered-rate achievement.
Latency is client QPC round-trip, with all accepted samples sorted for quantiles.
It includes generator scheduling; it is not pure server service time. Up to500ms
is allowed for final draining. CPU uses whole-process kernel+user times after
warmup, RAM is20ms-sampled peak private committed bytes/working set. Windows CPU
accounting quantization limits conclusions at very low CPU rates. No priority,
affinity, power, firewall or network-stack tuning is applied.

Build from this repository root in an x64 MSVC developer shell:

```
cl /nologo /W4 /WX /O2 /MT /TC /D_WIN32_WINNT=0x0A00 benchmarks/udp-implementations/udp_bench.c /Fe:artifacts/c-vs-csharp-20261025/udp_bench.exe
dotnet publish benchmarks/udp-implementations/csharp/UdpBench.csproj -c Release -r win-x64 --self-contained false -o artifacts/c-vs-csharp-20261025/csharp
python -B benchmarks/udp-implementations/compare.py --artifacts artifacts/c-vs-csharp-20261025 --smoke
python -B benchmarks/udp-implementations/compare.py --artifacts artifacts/c-vs-csharp-20261025
python -B benchmarks/udp-implementations/compare.py --artifacts artifacts/c-vs-csharp-20261025 --followup
```

The artifact directory must already exist. C# uses the installed.NET10 runtime;
do not compare its framework-dependent apphost file size against a standalone C
executable as total distribution size. Results, samples, input binaries and exact
source copies/hashes are frozen under a unique ignored run directory. Never commit
those binaries as source. Freeze validation uses a new unique directory every run.
Use per-trial medians and ranges, not a single best number; measure further before
selecting a production engine or claiming that a language is fastest.

`--followup` keeps the same binaries/protocol, uses4seconds of warmup, adds
QueryProcessCycleTime and repeats12800/64000pps. It was needed because the first
short CPU-time samples were unstable. Never convert process cycle counts to
wall time or compare them across different machines/clock policies. Both suites
together take roughly3.5minutes; do not extend them past the applicable allowance.

Primary API references:

- [Reusable CNG HMAC](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptcreatehash)
- [ReceiveFrom with reusable SocketAddress](https://learn.microsoft.com/en-us/dotnet/api/system.net.sockets.socket.receivefrom?view=net-10.0)
- [Process cycle counter](https://learn.microsoft.com/en-us/windows/win32/api/realtimeapiset/nf-realtimeapiset-queryprocesscycletime)
