# Milestone 11 report

Status: complete  
Effort: Very High

## Outcome

The local UI now owns a versioned Debian/Ubuntu systemd endpoint bundle,
private-key-only SSH transport, explicit first-use host trust, read-only
discovery, exact installation/repair planning, bounded apply with rollback and
independent post-apply verification. The server agent validates every declared
artifact and plugin before activation; the service runs under a dedicated
unprivileged identity and keeps TestLab evidence in TestLab-owned paths.

Provisioning never accepts password authentication, silently replaces a host
key, modifies an unrelated listener or claims readiness without matching
hashes, plugin self-tests, service state and required TCP/UDP listeners. Server
address, key path and other private values remain in the protected local UI
store and are absent from public repository files.

## Verification

- `tests/Test-ServerProvisioning.ps1`: PASS.
- Release build: PASS with 0 warnings and 0 errors.
- Offline rollback, artifact tamper and plugin self-test fixtures: PASS.
- Real endpoint mutation was not required to complete the offline contract.
- Commit/push: not performed.
