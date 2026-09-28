# Local release procedure

1. Build the x64 deterministic client with `scripts\Build-Harness.ps1`, or pass
   an independently reviewed exact client path to the publisher.
2. Run the offline Windows PowerShell suite and the Release UI build.
3. Run `scripts\Publish-LocalRelease.ps1 -Version <version> -CreateZip`.
4. Verify the generated `SHA256SUMS.txt` with
   `packaging\Repair-ProxyBridge-TestLab.ps1` from inside the package.
5. Perform the operator guide's VM checklist. Do not treat an offline build as
   proof of ProxyBridge, driver, SSH, proxy or network behavior.

The publisher stages to a new directory, refuses to overwrite an existing
release, copies only explicit public trees, publishes a self-contained win-x64
controller and records whether the deterministic client was included. `.env`,
credentials, product binaries, generated profiles, evidence and `.git` are not
copied. Package verification rejects missing, changed, duplicate, unlisted and
reparse-point entries.

The repository's ordinary UI builds keep package sources disabled. The release
publisher explicitly uses the official `https://api.nuget.org/v3/index.json`
source only to restore the SDK-matched Windows runtime packs required for a
self-contained controller.

Use `-AllowMissingClient` only for an interface/fixture evaluation package. Such
a package is intentionally blocked from real traffic by Environment Setup.
