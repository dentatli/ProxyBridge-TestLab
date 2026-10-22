# Independent WFP context probe

This diagnostic client/server shares no ProxyBridge implementation. The reference
callout is Microsoft's WFPSampler at revision
`bb68ed5e770bce04dc5395ec9258dafab034184d`.

`WfpContextProbe.cs` builds with the .NET Framework x64 C# compiler and
`System.Runtime.Serialization.dll`. `--help` creates no sockets. The executable
does not install a driver, add filters, start ETW, or manage services.

Each trial needs a fresh directory. The three roles are separate processes:

- `server`: listen on loopback port 34010, wait for `server-release.flag`, accept
  the expected connections, query original context exactly once per socket,
  validate the sample's 256-byte context, and receive/echo 512 KiB.
- `fillers`: establish 200 connections to original destination 127.0.0.1:54122,
  using source ports 42001 through 42200; wait for `clients-release.flag` before
  sending data.
- `control`: one connection using source port 42201, with the same release gate.

Role counts and ports are options shown by `--help`. A healthy trial uses a
server count of one and no fillers. No role can be reused in the same directory:
its claim file is created exclusively. Readiness files expose actual process IDs
for the future controller and narrow local-service redirect policy.

The controller must install the policy only after the server PID is known, verify
the filler connections and control SYN state, release the gates, collect all
children, and remove only its owned policy. A socket failure is evidence, not an
invitation to retry the context query. ETW must independently establish the queue
refusal/retry trigger before drawing a causal conclusion.

Validation: compiler warnings treated as errors, build exit 0; help exit 0.
`scripts/Invoke-IndependentWfpTrial.ps1` now orchestrates the separate processes,
narrow policy, TCP ownership, ETW and owned cleanup. The independent healthy
trial passed; the 200-filler trial reproduced one original 10022/zero-byte query
with the sample callout on Windows 26200.9711. See
`docs/INDEPENDENT_WFP_RESULT_2026-10-21.md` for evidence and limitations.
The sample services are currently stopped. Do not rerun consumed trial IDs or
execute the roles manually as a replacement for the diagnostic sequence.

The optional `--records-first 1` server option makes one original QUERY_RECORDS
call with a 64 KiB buffer before the single QUERY_CONTEXT call. Both raw results
are recorded separately. The trial controller exposes this as `-RecordsFirst`;
it also accepts explicit control/filler source ports to avoid reusing TIME_WAIT
tuples. This order passed the healthy control and still reproduced both getters
failing on the selected connection after queue refusal/retry. See
`docs/TCP_REDIRECT_API_CONTRACT_2026-10-21.md` for the separate flags correction
and experiment evidence. Neither experiment modified ProxyBridge product code.

The controller also supports `Capacity` and `Drain` comparisons. Capacity calls
`.NET Framework Socket.Listen(-N)` once, using Windows `SOMAXCONN_HINT(N)`;
Drain accepts the bounded set of 201 sockets before processing their data.
The corresponding options are `--backlog-hint` and `--accept-first`.
On 2026-10-22 both comparisons passed all 201 original records/context queries
and bidirectional payload checks, without the selected queue-refusal/retry
events present in the baseline. This verifies prevention in this workload;
it does not repair lost metadata or prove an instruction-level Windows cause.
See `docs/TCP_CONTEXT_QUEUE_MITIGATION_2026-10-22.md`. Avoid source port 47001
on PB-SUT: WinRM reserves it. Use fresh trial IDs and disjoint available ports.
