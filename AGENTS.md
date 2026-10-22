# ProxyBridge-TestLab

## Scope and context

- Choose scope from the current request. Development and diagnosis are separate; neither historical NEXT entries nor development permissions authorize diagnostic runs.
- Development: read [development handoff](docs/CHAT_HANDOFF_DEVELOPMENT.md). Continue UI, orchestration, reporting, and remote setup independently of the TCP failure. Do not investigate or fix that failure in development work. Preserve evidence gates and report actual test failures.
- Diagnosis: start with [current UDP/SOCKS5 handoff](docs/NEXT_DIAGNOSTIC_CHAT_2026-10-22.md). For TCP/WinDbg, read the current summary and linked checkpoint in [diagnostic handoff](docs/CHAT_HANDOFF_DIAGNOSTIC.md). Respect applicable runtime restrictions; read older entries only as needed.
- [Historical context](docs/history/AGENTS_CONTEXT_2026-10-08.md) is evidence, not an action queue or fresh authorization. Keep progress in the relevant handoff/topic document, not AGENTS.md.

## Workspace, checks, and Git

- Check Git status before edits; preserve other chats' changes. Do not reset, overwrite, or discard unrelated work. Use separate worktrees for parallel source edits when requested; they share the VM, driver, services, ports, and debugger.
- Development checks expected to take <5 minutes are authorized; do not split longer suites to evade this limit. Coordinate ProxyBridge/traffic checks with diagnosis; do not run them with active debugger points or a diagnostic workload on the VM. This allowance excludes diagnostic Run.
- Routine development must not change system proxy, BCD, trust/signing, hypervisor, power state, or product driver installation. Such work requires its own scope and authorization.
- Preserve captures, frozen kits, and manifests. Do not refreeze or Resume old preparations, or claim a changed profile matches a frozen kit. Historical build/test results apply only to their recorded revisions.
- Commit and push authorized source/docs changes; verify the remote result. No force-push. Exclude private captures, kits, archives, SSH private keys, credentials, and machine-specific backups.
- Product branches follow the [owner-controlled driver workflow](docs/PRODUCT_BRANCH_WORKFLOW.md): new work branches from dentatli/ProxyBridge `driver`; PR creation and merging each require an explicit user request. Use Squash and merge for authorized PR merges.

## WinDbg safety

- Agent VM is the debugger host; only physical PB-SUT (192.168.0.157) may be the target. Installing/operating WinDbg here for PB-SUT, including Break, breakpoint enable, and single-step, is authorized. Never debug the agent VM or reuse its old named pipe.
- Before an action that can pause PB-SUT (including WinRM/RDP), warn the user and prepare recovery commands. Enter `g` on a separate command line; it may be the last line of a pasted block.
- KernelReadCapture and hidden kd with redirected output remain prohibited.
