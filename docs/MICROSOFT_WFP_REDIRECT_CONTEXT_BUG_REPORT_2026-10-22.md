# Windows WFP: accepted loopback connection loses redirect records/context after early RST and SYN retry

**Report date:** 2026-10-22  
**Component:** Windows TCP/IP / Windows Filtering Platform, ALE connect redirection  
**Classification:** Suspected functional defect; no demonstrated security impact  
**Submission status:** Prepared for Microsoft; not submitted

## Summary

A TCP connection redirected to a local proxy can complete its handshake after
an early RST+ACK and SYN retransmission, but its accepted socket has no WFP
redirect record or redirect context. Both
`SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS` and
`SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT` return `SOCKET_ERROR`,
`WSAEINVAL (10022)`, and zero bytes.

The issue reproduces with a Microsoft WFPSampler-based callout and an independent
client/server probe, with the original product driver stopped. It does not require
a debugger, concurrent connections, or accept-queue exhaustion. A temporary,
exact-tuple inbound transport block provides a single-connection reproduction.

A subsequent kernel capture links the same source endpoint/record, early RST,
SYN retry, final SYN NBL, accepted endpoint, and failing user-mode query. The
source record/context remains present while the accepted endpoint has none.

Please confirm whether the observed behavior is a Windows defect and route this
report to the TCP/IP/WFP connect-redirection maintainers. If it is intentional,
please identify the supported API contract and recovery mechanism for a connected,
redirected socket in this state.

## Expected and actual behavior

**Expected:** When a redirected TCP handshake eventually succeeds, the accepted
proxy socket retains the redirect records and the context supplied by its callout,
including when an early received packet is followed by continued SYN retries.
The expected behavior is based on the purpose of the documented
[redirect-context query API](https://learn.microsoft.com/en-us/windows/win32/winsock/sio-query-wfp-connection-redirect-context)
and [bind/connect redirection](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection).
Please confirm the contract for this particular retry path.

**Actual:** The connection reaches the proxy's accepted socket, but both getters
fail with 10022/zero bytes. Kernel accept-side retrieval returns
`STATUS_NOT_FOUND (0xC0000225)`. The source endpoint still references the original
record and its 256-byte context. The proxy cannot reliably recover the original
destination, so it cannot safely service that connection.

## Environment

| Item | Observed value |
| --- | --- |
| Physical target OS build | 26200.9711, x64 |
| Kernel debugger build-family string | Windows kernel 26100, 8 logical processors |
| tcpip.sys file version | 10.0.26100.8875 |
| tcpip.sys SHA256 | `b0683bd7ed0f309e63b4e6e71675d8f04cfb0ea5533c3f5e8a13c6daca3b595a` |
| fwpkclnt.sys / netio.sys file versions | 10.0.26100.9711 |
| Reference sample | microsoft/Windows-driver-samples WFPSampler, revision `bb68ed5e770bce04dc5395ec9258dafab034184d` |
| Corrected sample SYS SHA256 | `d09a6871038f1f5e4dfb6c6266262d582691ae843f4cbbd6cdbb53fdefe92b95` |
| Probe executable SHA256 | `f36ada1a38c33eba7fa3ebc1cef1d7729120f2153c9eefdbe81f49cd7f25f8fb` |
| Query order | RECORDS once, then CONTEXT once per accepted socket |
| Output buffer sizes | RECORDS 65,536 bytes; CONTEXT 4,096 bytes; expected context 256 bytes |

The sample was modified to use flags=0 for inline
`FwpsApplyModifiedLayerData0`; the reauthorization flag is retained only for
pended classification. This addresses a separately identified sample API-usage
issue. Healthy controls pass and the reported failure persists with that
correction. The exact [sample patch](https://github.com/dentatli/ProxyBridge-TestLab/blob/6b4004fdebeb1d05f51e762dc8336b22e62b092b/scripts/patches/wfpsampler-inline-apply-flags.patch)
is included in the diagnostic source repository. This is therefore a modified
reference sample, not a claim that an unmodified Microsoft binary was used.

## Minimal reproduction procedure

Use a disposable Windows machine with the corrected sample callout and its
required service installed and running. The original ProxyBridge driver must be
stopped. Driver installation/signing is an environment prerequisite, not performed
by the probe. Use a fresh output directory and an available source port for each
trial; the example port below records a completed trial and should not be reused
as the identity of another capture.

1. Start a TCP listener at `127.0.0.1:34010`, accepting before client data is
   processed. Configure a sample inline PROXY policy at
   `FWPM_LAYER_ALE_CONNECT_REDIRECT_V4`, restricted to the probe application and
   original destination `127.0.0.1:54122`. Redirect to `127.0.0.1:34010`, using
   the actual server PID and a 256-byte redirect context.
2. Add `BASIC_ACTION_BLOCK` at `FWPM_LAYER_INBOUND_TRANSPORT_V4` restricted to
   TCP `127.0.0.1:<source port> -> 127.0.0.1:34010`.
3. Start one client bound to that source port and connect to the original
   destination `127.0.0.1:54122`.
4. Observe that client in SynSent, hold the block briefly, then remove the exact
   block. Removal is not instantaneous; this procedure does not claim to drop
   exactly one SYN. Collect TCP/IP ETW to identify the actual retries and RSTs.
5. On the eventually accepted socket, query RECORDS once and CONTEXT once,
   recording the raw return value, `WSAGetLastError`, returned byte count,
   socket tuple, PID and TID.
6. Remove only this trial's filters and stop its processes/trace.

The controller and probe sources are available at the pinned diagnostic revision:

- [Controller: Invoke-IndependentWfpTrial.ps1](https://github.com/dentatli/ProxyBridge-TestLab/blob/6b4004fdebeb1d05f51e762dc8336b22e62b092b/scripts/Invoke-IndependentWfpTrial.ps1).
- [Probe: WfpContextProbe.cs](https://github.com/dentatli/ProxyBridge-TestLab/blob/6b4004fdebeb1d05f51e762dc8336b22e62b092b/src/independent_wfp/WfpContextProbe.cs).
- [Probe build/setup notes](https://github.com/dentatli/ProxyBridge-TestLab/blob/6b4004fdebeb1d05f51e762dc8336b22e62b092b/src/independent_wfp/README.md).

Relevant controller parameters for the captured single-flow failure were:
`Mode=SilentRetry`, `ControlPort=48807`, `RecordsFirst=true`,
`DropHoldMilliseconds=100`, kit-r7. In the kernel-capture copy, NetTCPIP was
imported and a native TCP-table query completed before launching the flow,
avoiding lazy module loading while the target was paused. The copied controller
SHA256 is `871b5498fdbd6005e20582ede7b062d43d80f4e5eba2ef6863bb8cb3c42c6eac`.

## Controls without a debugger

All cases below used the same target boot, corrected sample, one connection,
and no filler connections. TCP/IP ETW reported zero events lost.

| Condition | Observed SYN retransmission counts | RST observation | API/data result |
| --- | --- | --- | --- |
| Temporary inbound transport block, source48801 | 1, 2, 3 | Three early RST+ACKs in SynSent, plus terminal RST | Both getters10022/0 |
| Block plus exact-tuple inbound TRANSPORT_DISCARD block, source48803 | 1 | No RST send/receive events for selected flow | Records970 bytes, context256 bytes; 512KiB each direction |
| Remove discard suppression, source48804 | 1, 2 | RST send/receive present | Both getters10022/0 |
| Discard suppression, hold3500ms, source48805 | 1, 2, 3 | No RST send/receive events for selected flow | Records970 bytes, context256 bytes; 512KiB each direction |

The exact-tuple `FWPM_LAYER_INBOUND_TRANSPORT_V4_DISCARD` block was a diagnostic
variable, not a proposed production workaround. Its effect was measured in ETW.
The long-hold control distinguishes early RST handling from retransmission alone:
three retries without early RST still preserve context. This is a small,
controlled case series, not a statistical reliability estimate.

## Single-flow kernel evidence

The linked capture used source48807. Addresses below are boot-specific identities.
No private flag or record was patched. Live code at the selected points was
checked against matching symbols before capture.

| Stage | Observation |
| --- | --- |
| CREATE | Source endpoint `ffffa18fbae2a010`, record `ffffa18fb6c60660`, context `ffffa18fbcc6fb40`, size0x100 |
| Initial SYN helper | Flags0x1101641; NBL `ffffa18fb6ded8e0` changes WFP info_raw from1 to `ffffa18fc38cd2b1` between gate and return |
| Early RST+ACK receive | TCP flags0x14, sequence0, ACK3920647988; source flags0x1101641 -> 0x1301641 at `tcpip!WfpTlShimInspectRecvTcpDatagram+0x198`, immediately after OR0x200000 |
| Subsequent SYNs | Same source endpoint/record, SYN sequence3920647987; source flags0x1301641; info_raw remains1 before and after send helper, return status0 |
| Final observed SYN | NBL `ffffa18fc2aa9c30`, still info_raw1 |
| Accept-side retrieval | Exactly that NBL; accepted endpoint `ffffa18fbe682050`; status0xC0000225, output record0 |
| Socket query | Same accepted endpoint, IOCTL0x980000dd; its record0, original source record still present |
| User-mode API | PID5684/TID4940 matches kernelPID0x1634/TID0x134c; both getters10022/0 on source48807 |

The RST ACK equals the SYN sequence+1. The final SYN NBL matches the accept NBL,
and the accepted endpoint matches the query endpoint. This is a linked capture,
not a merge of unrelated flow observations. ETW for the selected flow reports
retransmission counts1/2 and zero events lost.

Six send-helper gate/return observations are not claimed to be six separate
wire transmissions. `info_raw=1` denotes an absent WFP info structure in the
examined representation; the private tagged-context list was not separately
walked in this capture. Accept-side NOT_FOUND independently confirms that the
required record was not retrievable there.

## Mechanism supported by the evidence

The examined `tcpip.sys` code has the following sequence:

1. WFP receive inspection runs before the TCP code finishes deciding how to
   handle an early RST in SynSent. The observed receive path sets
   endpoint+0x30 bit0x200000.
2. TCP can continue the connection attempt after this RST. ETW and static code
   show a nonfatal retry path; an early RST does not always terminate this flow.
3. `WfpTlShimInspectFastLoopbackSendDatagram+0x30` tests that bit.
   The conditional branch at+0x34 goes to the epilogue at+0x14f when it is set,
   bypassing the redirect-record association path for the repeated SYN.
4. The eventual accepted connection has no record. Both getter failures follow,
   although the source record/context remains allocated and referenced.

This establishes the observed failure mechanism on the examined build. The
interpretation of the private bit as an overly broad receive-state gate is an
inference from code and behavior; its official name and intended invariant are
unknown. Please verify the intended SYN-retry/metadata association behavior and
the appropriate lifetime/reference-counting correction in Windows source.

## Impact and mitigation

WFP local TCP proxies can lose the original destination/context on connections
that successfully reach accept. Slow connection setup in a serial accept loop
can trigger queue refusal and the early RST/retry path under load. The independent
one-flow reproduction shows that queue exhaustion is not a necessary condition.

Accepting connections promptly before processing their context/data prevented
the queue-refusal trigger in separate measured trials. It cannot repair missing
metadata after every possible early RST. We have not changed private Windows
flags, disabled TCP RST globally, or implemented destination guessing.

## Evidence available for controlled transfer

Raw captures are retained separately; they are not embedded in or automatically
uploaded with this report. The successful joined capture is
`single-flow-kernel-20261022-r2`. Its retained files include:

| File | SHA256 |
| --- | --- |
| TCP/IP ETL | `b479a150f7c825b9aacdbd8492f466ba3127df2f6b3082d0565df3c85b488180` |
| Native/controller result JSON | `d273d65f220607403bdeac0d02ce25d03cce201e77bec5f44b9a0654e3b7f3d3` |
| Derived flow-history JSON | `9487044843b6237a0653413ae7896347083d1fc4c435d75bb3e287bc6803c96f` |
| Saved WinDbg log, including earlier preparation/recovery | `333dca6a4163f4c64a34e1870467fff74425d49d0b7809f3c8d90cf39fdd73b1` |
| Kernel-capture command profile | `c8dc2f34bef251e9d6c1163be959d34bb3eec66ac02ee18502683563b6ea81c1` |

Also retained: exact filter arguments, raw server query row, process summaries,
no-debugger A/B captures, and derived identity checks. A previous fresh trial-r1
was incomplete due to a debugger-command syntax error and is excluded from the
successful chain. Source/record identity is taken only from trial-r2.

After capture, owned sample filters/processes/listener were absent, sample
services stopped, and debugger points disabled/removed; the physical target was
resumed. No other Windows versions have been validated. We do not claim a
specific Windows source patch, Microsoft acknowledgement, security exploit,
or guaranteed fix in a later release.
