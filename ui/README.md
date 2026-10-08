# Local web UI

The bilingual laboratory is the default page at `http://127.0.0.1:5178/`.
It has separate **Builds → Testing → Run → Results** views in Russian and English.
The existing `/lab.html?page=builds|testing|run|results` URLs remain supported;
`/index.html` redirects to the laboratory. The retired technical HTML/JavaScript
and its styles have been removed. Unknown routes and missing assets return 404.

## Start from source

Prerequisite: .NET 10 SDK. Run from the repository root:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run `
    --project '.\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj'
```

Source changes require restarting the application. Published packages must be
rebuilt to include them. To publish a portable release, use
`scripts\Publish-LocalRelease.ps1`; see [release procedure](../docs/RELEASE.md)
and [operator guide](../docs/OPERATOR_GUIDE.md).

## Current workflow

1. **Builds:** inspect files, save a kit under a custom name, select or rename it.
   Inspection does not start ProxyBridge or change the driver. Bundle identity
   remains separate from the name; paths are protected with DPAPI and are not
   returned by the API. Unknown, relocated and 4.0.0 runtime paths remain blocked.
2. **Testing:** select TCP RTT, combined upload/download, separate
   OFF/UNRULED/SOCKS5 RTT, or TCP connection load/recovery. Set duration and load
   independently for each test; estimates are shown per test and for the suite.
   Save/use/update/delete named suites to repeat the same choices on another
   build. Applying a suite requires fresh preparation; it cannot reuse a frozen
   plan or establish readiness.
3. **Run:** prepare an immutable files-only plan, review its summary, then start
   explicitly from an administrator UI. The backend rechecks kit identity and
   launches the existing controller with evidence/route/data/cleanup gates.
   Stop waits for the current run and cleanup; remaining tests are not started.
   The queue stops on failure. Complete and partial attempts remain recorded.
4. **Results:** select builds, tests, conditions and metrics in Comparison, or
   inspect attempts in History. The latest failed/cancelled attempt never falls
   back to an earlier success. Unconfirmed attempts have no measured metrics;
   unreadable history blocks the latest-only table. RTT, rates and sampled CLI
   CPU/private RAM retain their actual measurement scope.

Navigation does not start or stop a run. Choices survive refresh in session
storage; saved builds, suites and job state come from the server. Unstarted
plans must be prepared again after a full reload. Interrupted jobs are not
resumed automatically; reboot/evidence gates remain in force.

Named suites store only choices in `benchmark-suites.json` below the protected
user config directory. Catalog reads/writes are bounded and validated; corrupt
catalogs block writes. Credentials, keys, kit paths and old launch plans are not
stored in templates. Local saved reports are read without probing the product.
A conditions-key match does not prove full hardware/background comparability.

## Remaining integration

The [functional inventory](../docs/DEVELOPMENT_FUNCTIONAL_STATUS.md) records
source verification and remaining work. Separate upload/download selection,
loaded RTT/UDP queue integration, other build adapters and complete remote
controllers are pending. Runtime validation is separate from a successful build.

The [Ubuntu wizard](../docs/REMOTE_UBUNTU_SETUP_PLAN.md) targets Ubuntu Server
22.04/24.04/26.04 LTS, a dedicated key for root, public-key copy, IP/optional
port, Automatic setup and Check connection. It is not yet connected to this UI;
`REMOTE_CONTROLLER_PENDING` remains in force.

Shared backend services are retained for catalog coverage, settings, SSH trust,
provisioning and safety checks. `BenchmarkRunService` still consults
`RunCoordinator` to reject concurrent legacy real jobs. The technical API and
existing security/server/runner probes are retained; they are not a second UI.
The standalone PowerShell controllers and diagnostic tooling are unchanged.

The controller accepts loopback clients/known host names only; mutations require
same-origin requests and a per-process CSRF token. See [security](../docs/SECURITY.md).
Default user data is under `%LOCALAPPDATA%\ProxyBridge-TestLab`. Private data,
frozen kits and captures remain outside Git and are not removed by UI cleanup.
