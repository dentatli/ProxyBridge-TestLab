# Opt-in gRPC streaming SDK checks

Run `probe.py` from the repository root with `src` and an isolated, verified
official grpcio SDK installation on `PYTHONPATH`. Supply the existing traffic
binding via stdin using the TestLab DPAPI loader. Never put the secret in command
arguments, Git or logs. The tested SDK is grpcio 1.84.0; it is not a production
dependency.

The three calls use the public protobuf Envelope contract in
`config/traffic-echo.proto`. Client streaming returns one aggregate containing
three signed receipts. Server streaming returns three indexed, signed responses
to one request. Bidi sends each next request only after verifying the preceding
response, demonstrating response progress before request half-close. Every RPC
must end with SDK StatusCode.OK and exact signed origin counts/peer/idle.

The SDK uses the dedicated CA and certificate name. A separate native TLS
preflight checks the endpoint leaf pin; this does not claim grpcio pins the leaf
inside each RPC. Production native workers require their own CA/name/leaf pin.
OS DNS/proxy/trust stores remain unchanged. A final SDK cancel after the first
bidi response verifies signed idle and zero completed RPCs for that partial call.

This is dedicated component interoperability, not ProxyBridge routing or general
unbounded streaming, compression, retries or deadline-server semantics.
