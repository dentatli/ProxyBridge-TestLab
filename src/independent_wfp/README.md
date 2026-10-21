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

Current validation: compiler warnings treated as errors, build exit 0; help exit
0. No socket trial has run. The controller, ETW collection, sample installation,
and rollback are not implemented here. Do not execute these roles manually as a
replacement for the reviewed diagnostic sequence.
