# Security boundary

ProxyBridge TestLab is a local administrative test tool, not a public web
service.

- The controller listens on loopback only, validates the Host header and rejects
  non-loopback clients.
- Mutating requests require same-origin and a per-process CSRF token.
- Browser requests cannot supply executable paths, commands, environment
  variables, evidence roots or runner switches.
- Secrets and sensitive paths are stored with Windows DPAPI for the current
  user. Temporary runner input is ACL-restricted, never returned by the API and
  removed through a lease/finally path.
- Server trust is fail-closed. A new or changed SSH host fingerprint requires
  explicit confirmation. Only private-key SSH is supported.
- Remote operations are typed, bounded and limited to Debian/Ubuntu with
  systemd. TestLab never replaces the host firewall policy.
- Real execution requires complete settings, a current server receipt, an
  exclusive lease, exact-contract scenarios, a signed two-minute immutable
  preflight receipt and a one-use selection-bound confirmation.
- Product verdicts require complete, correlated client and endpoint evidence.
  Stale or cross-phase records are contamination, not PASS.
- Sanitized exports use an explicit allowlist, reject reparse points, limit
  evidence size and exclude credentials, compatibility inputs, generated
  profiles and raw transcripts.

The package does not include ProxyBridge product binaries, installers, drivers
or signing material. They remain independently installed and hash-verified.
