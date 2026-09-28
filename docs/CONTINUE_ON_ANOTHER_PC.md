# Continue development on another Windows PC

Clone https://github.com/dentatli/ProxyBridge-TestLab.git (or fast-forward an
existing clean checkout). Open the repository root in Codex. Do not copy the
previous machine's .env, SSH private keys, UI secret storage, runtime evidence,
generated profiles or build output. Configure secrets through the UI only when
runtime work is separately authorized. See ui/README.md for build prerequisites
and vendor/README.md for pinned offline dependencies.

## Prompt to resume

Continue from the top checkpoint in docs/WORK_CHECKPOINT.md in this checkout.
Milestone 16 Task 3a: the offline negative-proxy semantic foundation and isolated
profile constructor are accepted. Do not redo completed stages. Next implement
the signed semantic receipt contract and negative offline fixtures, then derived
readiness, orchestration, no-fallback/zero-delivery and cleanup assertions.
Read the Task 3a brief and reports in artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN.
Use the approved Windows tester/ProxyBridge plus separate Debian/Ubuntu systemd
Linux server topology; configuration is UI-only. Keep negative scenarios gated
until the complete contract is proven. No real runtime/network, deployment,
driver/firewall changes, commit or push without a new explicit request.
Superpowers is not used; grill-me is only for separately requested quizzes.
An independent review subagent is permitted. Preserve unrelated changes.

## Transfer scope

The September 28 commit/push is explicitly authorized for transferring the
accumulated work; it does not authorize future commits or runtime activity.
Previously recorded test results are historical, not fresh acceptance on this
machine. Restore/build local dependencies as needed and run only relevant
offline checks. No private machine state is included.
