# Opt-in encrypted DNS component probe

This probe uses dnspython 2.9.0 for DoT and DNS wire parsing, and Python's
`http.client.HTTPSConnection` for DoH POST. Install the SDK into a disposable
directory from its verified official PyPI wheel; it is not a production runtime
dependency and is not vendored in this repository.

Run `probe.py` from the repository root with `src` and the SDK directory on
`PYTHONPATH`. Supply the existing traffic binding on standard input:
`host`, `port`, `control_port`, `secret` (hex), `remote_bundle_sha256`.
Use the TestLab DPAPI secret loader; do not put credentials in arguments, Git,
logs or shell history. The remote runtime must match the binding and expose
DoT TCP 42533 and DoH TCP 42535.

The probe checks the dedicated CA, certificate name and leaf pin without changing
OS trust, DNS or proxy settings. It validates the SDK-parsed A/TXT answer, full
TestLab HMAC receipt, origin peer, signed per-flow count and global idle. DoT
also verifies the authenticated terminal TXT exchange and TLS close_notify.
These are direct component checks: they do not establish ProxyBridge routing,
recursive resolution, DNSSEC or interoperability with arbitrary DNS servers.
