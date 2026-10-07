# Local web UI

The new bilingual laboratory screen is at `http://127.0.0.1:5178/lab.html`.
It presents separate Builds → Testing → Run → Results views in Russian and English:
`/lab.html?page=builds`, `?page=testing`, `?page=run`, `?page=results`.
Navigation uses browser history and keeps the shared in-memory selection/prepared plan and active-run polling.
Mode/scenario are retained in session storage; only these non-sensitive choices are stored there.
The saved kit and active job are restored from the server after refresh; an unstarted plan must be prepared again after a full reload.
An active run (or lost run-state connection) is visible from every view; changing views does not stop or start it.
The Builds page now accepts a custom name and lists saved kits with select/rename actions.
The catalog deduplicates by contract and inspected bundle identity; changing files creates another identity, while renaming does not change the binaries or old evidence.
Catalog paths are DPAPI protected in `benchmark-builds.dpapi`. The API returns labels and ids, not stored paths.
An old single saved selection is migrated from its saved observation on first state read, without a product/driver probe.
Selecting a catalog item performs a new files-only inspection. This does not enable unknown, relocated, remote or 4.0.0 benchmark paths.
New frozen plans/jobs carry the build id and name snapshot. Old confirmed local results derive identity from verified saved bundles; old plans do not invent a historical custom name.
Build catalog compilation, DPAPI migration/select/rename and API/UI integration await user verification.
The Results page now separates **Comparison** and **History**. Comparison selects builds and metrics for the latest attempt of each build/scenario in the current local SMOKE path; it never substitutes an older success after failure or cancellation.
History merges validated local reports with saved UI jobs, including pre-workload failures, and filters by build/test/status. Old paired version reports remain in a separate expandable archive.
RTT now projects saved CLI mean CPU/private RAM as well as latency. Conditions keys compare saved configuration/tool values, excluding ephemeral ports/PIDs/run ids/direction/product label; matching keys alone do not establish full hardware/background comparability.
Unconfirmed or running attempts show no metrics. Unreadable launch history blocks the latest-only table rather than hiding an unknown newer attempt.
Initial data loads the latest 50 local reports per scenario and 1000 UI job records. Earlier jobs can be paged, and older report details are loaded on demand through a strict basename-only read-only API.
The new results API/UI, tabs, filters, latest-attempt selection and on-demand/paged loading await user compile/runtime verification. No new benchmark is required to review the saved data.
Test checkboxes/queues, duration/load presets and arbitrary beta/4.0.0/remote runtime adapters remain pending.
Choose an installation folder and either **4.0.0** or **driver**; a separate driver path is optional.
The files-only inspector reuses `ProductBuild.psm1` and never starts ProxyBridge or probes driver state.
Known benchmark file fingerprints and unknown candidates have different statuses.
Selection is saved under the current Windows user's DPAPI protection; stored paths are not returned by the API.
Saved comparisons of transfer rates and application TCP RTT are shown without raw logs or paths.

The **Prepare launch** action re-inspects the DPAPI-saved selection and freezes controller/environment/kit
fingerprints under `artifacts/benchmark-launch/plan-*.json`. It supports the original known driver kit in local mode:
TCP transfer, RTT and loaded RTT use short SMOKE readiness profiles; UDP uses MULTI_TARGET with buffered helper logs.
Preparation runs only the files-only inspector (`Invoke-PlannedBenchmark.ps1 -Phase Inspect`).
Local **driver TCP RTT SMOKE** and **TCP upload/download SMOKE** have an explicit **Run check** button when the UI application runs as administrator.
They launch the frozen plan through the existing controllers. Progress shows completed runs out of two (RTT) or four (transfer), direct/SOCKS5 mode and transfer direction.
**Stop after current run** queues cooperative cancellation: the current run finishes verification and cleanup, then the next run is skipped.
Cancelled series retain completed evidence and do not produce a passed paired comparison. Other prepared scenarios still use the administrator command (`-Phase Run`).
TCP RTT and upload/download GUI launch/results have been observed through the user. Transfer cancellation is not yet runtime-verified.
The transfer readiness profile verifies four 64 MiB transfers with an 8 MiB/s sender cap and data-only shutdown.
Saved transfer results show per-direction rates vs direct, rate change and sampled CLI CPU/private RAM; normal TCP close and maximum throughput are not established.
The old real executor and planned wrapper share an exclusive checkout file lease; external product launches are outside its scope.
State survives refresh; after an app restart an unfinished UI job is marked interrupted and is never resumed automatically.
Cross-boot checks require reboot after recorded 4.0.0 activity or an interrupted UI job. These checks do not prove global cleanup.
The entry point rechecks fingerprints, checks reboot time against recorded 4.0.0 attempts, and launches the original
controller in a separate PowerShell process with its existing evidence/route/data/cleanup gates. No settings from the old runner are used.
Unknown or relocated kits, 4.0.0 (which requires its existing reboot/lifecycle/idle flow), and remote mode remain blocked here.
The planned-run mutex only coordinates this entry point; it is not a global system lock or proof about external product launches.
The entry point now forwards both controller streams live and stores them with a process receipt under
`artifacts/benchmark-launch/<plan-id>-run`. Each plan can be executed only once. Controller exit and evidence verdict remain distinct.
The Results screen includes saved local TCP RTT SMOKE runs (including incomplete/failed runs when a manifest exists).
Completed metrics require matching embedded/source reports and saved run/kit receipts; reading history never probes or starts the product.
Results for other local scenarios, automatic execution and cancellation remain pending.
Selection does not change the old runner settings, and arbitrary-build runtime compatibility is unverified.
The previous technical interface remains at `/index.html`. Do not treat a successful file inspection
or historical results as a readiness/correctness pass for the newly selected installation.
After source changes use the development command below; previously published binaries do not include these changes.

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
