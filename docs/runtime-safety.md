# Runtime safety

Dry-run and mock-runtime are the default development modes. Without `-DryRun`,
`-MockRuntime` or the explicit `-AllowProductRuntime` switch the runner stops
with `RUNTIME_NOT_IMPLEMENTED`.

Real smoke is isolated in `scripts/Invoke-RealSmoke.ps1` and requires
`-ConfirmRealRuntime`. It selects one accepted TCP issue206 PROXY->BLOCK
Stage 3.4A command, stops on the first infrastructure or harness error and
writes preparation, baseline, lifecycle, client, ProxyBridge and VPS evidence.
By default it validates exact binary hashes, stops only same-path configured
GUI/CLI processes, and bootstraps a Stopped configured service through the
verified GUI. A same-name process with a different or unreadable image path is
never killed and causes `UNKNOWN_PROXYBRIDGE_PROCESS_CONFLICT`.

The harness never installs, removes, starts or stops the service directly and
does not change firewall, VPS configuration, installer state or signing policy.
If the service is missing or GUI bootstrap does not leave it Running, the run
ends as infrastructure failure and cleans the bootstrap GUI.
After the single selected record completes, the entrypoint emits
`REAL_SMOKE_RESULT=PASS|FAIL|HOLD` and returns nonzero for FAIL or HOLD.

Before a future real smoke, verify the UI-managed protected configuration,
exact binary hashes, capabilities, CLI/client argument contracts and an
isolated recovery path. The controller may materialize a private temporary
runner input, but the user never edits or exports it. Do not run real smoke from
automated tests or during audit-package generation.

Real process, process-observation and TCP reachability adapters are unreachable
without `-AllowProductRuntime`. Dry-run and mock use adapters and fixture files
only. The real entrypoint was not executed during development validation.

After preparation and immutable reachability checks, one in-process .NET TCP
control flow discovers direct IPv4 egress before the CLI starts. The watched
client is not used. A complete exact-SHA VPS query must prove one receive, one
echo, the destination port and a valid source IPv4. Every scenario then gets a
post-run check requiring GUI/CLI absence and the configured service Running.
