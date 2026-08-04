# Runtime safety

Dry-run and mock-runtime are the default development modes. Without `-DryRun`,
`-MockRuntime` or the explicit `-AllowProductRuntime` switch the runner stops
with `RUNTIME_NOT_IMPLEMENTED`.

Real smoke is isolated in `scripts/Invoke-RealSmoke.ps1` and requires
`-ConfirmRealRuntime`. It selects one accepted TCP issue206 PROXY->BLOCK
Stage 3.4A command, stops on the first infrastructure or harness error and
writes lifecycle/client/ProxyBridge/imported-VPS evidence. It does not change firewall,
driver/service, VPS configuration, installer state or signing policy.
After the single selected record completes, the entrypoint emits
`REAL_SMOKE_RESULT=PASS|FAIL|HOLD` and returns nonzero for FAIL or HOLD.

Before a future real smoke, verify the private `.env`, exact binary hashes,
capabilities, CLI/client argument contracts and an isolated recovery path. Do
not run real smoke from automated tests or during audit-package generation.

Real process, process-observation and TCP reachability adapters are unreachable
without `-AllowProductRuntime`. Dry-run and mock use adapters and fixture files
only. The real entrypoint was not executed during development validation.
