# Opt-in HTTP/2 SDK component probe

Build `TrafficHttp2Probe.csproj` with .NET 10 into
`artifacts/development-remote-wizard/http2-sdk-probe` and run `probe.py` from the
repository root with `src` on `PYTHONPATH`. Supply the existing authenticated
traffic binding on stdin using the TestLab DPAPI loader. Do not put the secret
in arguments, logs, shell history or Git.

The fixture forces HTTP/2, opens three streams on one TCP connection and waits
until all three request bodies are ready before sending any body. This makes
concurrency observable at the origin. The CA trust, name validation and leaf pin
are scoped to one HTTP handler; OS trust, proxy and DNS settings are unchanged.
The .NET process only receives signed messages and public TLS identity.

Python validates every returned payload/HMAC/peer and the signed origin peak of
three streams, completed count, contiguous sequence/replay window and global
idle. This is opt-in component interoperability, not proof of ProxyBridge
routing, arbitrary concurrency, priority handling or maximum throughput.
