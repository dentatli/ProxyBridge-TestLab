# Local web UI

The release-candidate controller provides an English interface for the authoritative test catalog,
Run Builder, live fixture-job progress, deterministic result explanations,
sanitized audit export and Environment Setup. Public settings are
stored separately from DPAPI-protected secrets. The UI never returns secret
values; it reports only whether each protected value is saved.

Mutating settings and provisioning endpoints require a same-origin request and
the per-process CSRF token. Server Setup uses explicit private-key SSH actions,
host-fingerprint confirmation, an unexpired exact plan and post-apply
verification. Fixture jobs use the existing PowerShell mock runner. A real run
can be confirmed only after the controller performs a bounded immutable
preflight and issues a signed two-minute receipt for that exact selection and
private input. Server Setup readiness alone is not enough.

Prerequisite: .NET 10 SDK.

Start from the repository root:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run `
    --project '.\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj'
```

Open `http://127.0.0.1:5178`. The controller rejects non-loopback clients and
unexpected host names.

Use **Environment Setup** to enter all values. Do not create or edit `.env`.
The controller creates a restricted, short-lived compatibility input only for
an authorized runner job, then deletes it after use. By default,
configuration is stored below `%LOCALAPPDATA%\ProxyBridge-TestLab`.

Standard ProxyBridge paths are preconfigured. The traffic client is discovered
at `bin\pb_net_client.exe`, and binary integrity values are calculated
internally rather than entered in the UI. Server Setup supports only Debian or
Ubuntu with systemd and SSH private-key authentication.

The UI displays persisted controller jobs, fixture reports from
`tests/fixtures/ui-runs` and sanitized run reports from controller-owned
evidence roots. Each scenario separates product errors, harness errors, missing
evidence and contamination, and exposes a readable timeline plus the allowed
technical artifacts. The bounded audit ZIP uses the same explicit allowlist. It
never serves generated profiles, transcripts, environment files, credentials,
reparse points or arbitrary evidence paths.

For a portable local release, use `scripts\Publish-LocalRelease.ps1`. See
`docs\RELEASE.md`, `docs\OPERATOR_GUIDE.md` and `docs\SECURITY.md` before VM
validation.
