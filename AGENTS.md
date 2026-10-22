# Working preferences

- Respond in Russian by default. Lead with the outcome; keep answers concise, concrete, and clear. Include verification evidence and material limitations when relevant.
- Complete authorized work autonomously. Resolve routine choices from context; ask only when missing input materially changes the outcome. Explicit task boundaries and stop points remain binding.
- Distinguish observations, hypotheses, and proposed actions. Never claim a build, test, installation, or deployment succeeded without checking its result.
- Inspect relevant files and symbols selectively. Use Serena for semantic navigation when connected and suitable; otherwise use targeted searches. Avoid dumping entire logs or repositories.
- Match verification to the change and risk. Do not repeat successful checks without a new reason; honor explicit prohibitions on builds, installs, and execution.
- When using grill-me or grilling, ask exactly one question at a time, explain the recommended choice, and wait for the answer.

## Separate development and diagnostic work

The user separated these tasks on 2026-10-08. Choose the scope from the user's request; do not infer scope from historical NEXT entries.

- Application development: read [development handoff](docs/CHAT_HANDOFF_DEVELOPMENT.md). Continue TestLab functionality without investigating or fixing the TCP redirect-context failure. The unresolved failure does not block independent UI, orchestration, reporting, and remote-setup development. Preserve evidence gates and show actual test failures.
- TCP failure / WinDbg diagnosis: read [diagnostic handoff](docs/CHAT_HANDOFF_DIAGNOSTIC.md), then its current checkpoint. Its runtime restrictions remain binding for diagnostic work. Do not use development authorization to bypass them.
- Full prior project context is preserved in [historical snapshot](docs/history/AGENTS_CONTEXT_2026-10-08.md). This is historical evidence, not a global action queue. Read relevant entries selectively. Historical permissions, commands and NEXT entries do not override the current request and scoped handoffs.
- Keep ongoing status in the corresponding handoff or topic document. Do not append the diagnostic journal to this file again.

## Shared workspace and verification

- Separate chats do not establish file ownership. Before editing, inspect Git status and preserve other work. Do not reset, overwrite or discard another chat's changes. Use separate worktrees for parallel source changes when requested; a worktree does not isolate the VM, driver, services, ports or debugger.
- Debugger topology explicitly fixed by USER on 2026-10-22: run WinDbg inside the agent VM and debug only the physical PB-SUT (192.168.0.157). The agent may install and operate WinDbg here for PB-SUT, including Break, breakpoint enable and single-step. Never use WinDbg to debug the agent VM itself; do not reuse its old named-pipe connection. Before actions that can stop the target, warn that PB-SUT, including its WinRM/RDP, can pause and prepare recovery commands. The agent VM/Codex must remain the debugger host. Enter g as a separate command; it may be the last line of the same pasted block. The separate prohibition on KernelReadCapture and the previous hidden kd with redirected output remains in force.
- Ordinary development checks expected to take less than five minutes are authorized. Do not split a longer suite to evade that limit. Coordinate checks that start ProxyBridge or generate traffic with diagnostic work; do not run them while debugger points are active or a diagnostic workload is using the VM. Diagnostic Run is not authorized by this general allowance.
- Preserve captured evidence, frozen kits and their manifests. Do not refreeze or Resume old diagnostic preparations. Never claim that a changed profile conforms to a previously frozen kit.
- Do not change system proxy, BCD, trust/signing, hypervisor configuration, power state or product driver installation as a routine development step. Keep such work separate from application development and obey its explicit authorization and stop points.
- Commit and push authorized source/documentation changes, and verify the remote result. Do not commit private captures, kits, archives, SSH private keys, credentials or machine-specific backups. Do not force-push or discard unrelated work.
- Historical test/build statuses are evidence for their recorded revisions, not proof of the current checkout. Verify claims against implementation and appropriate checks.
