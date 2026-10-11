# Offline protocol dependencies

`protocol-dependencies.lock.json` is the authoritative allowlist for bundled
third-party Python wheels. Test execution and server provisioning never access
package indexes. Every wheel is verified by exact filename, size and SHA-256
before extraction into a versioned TestLab-owned runtime.

The two wheel sets target CPython 3.11 on Windows x64 and CPython 3.10 ABI
compatibility on Debian/Ubuntu x64. They currently provide the QUIC, HTTP/3 and
WebTransport protocol stack used by Milestone 13.

The traffic runtime uses a separate `traffic-dependencies.lock.json` and
`traffic-wheelhouse/{win-x64,linux-x64}` for AsyncSSH, hyper-h2 and their locked
dependencies. It does not expand or replace the original protocol wheel set.
Both runtimes verify exact wheel hashes before offline extraction. Package
licenses are recorded in the lock and retained in wheel metadata.
