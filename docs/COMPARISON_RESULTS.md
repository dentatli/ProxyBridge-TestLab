# WFP and WinDivert comparison results

**English** | [Русский](COMPARISON_RESULTS.ru.md)

Verified observations as of October 27, 2026. These results describe specific builds and scenarios, not a universal ranking of the architectures. See the [README](../README.md) for the project description and installation instructions. The supporting audit notes linked below are currently in Russian.

## Test machine and methodology

Physical PB-SUT: Intel Core i3-10100, 4 cores / 8 logical CPUs, approximately 16 GiB RAM, Windows 11 x64. Kernel debugging was disabled for these runs; the machine used a regular network adapter and the High Performance power plan. Temperatures, clock frequencies, and all background activity were not recorded continuously.

The compared builds were the user's **WFP build at revision 4da324e** and **ProxyBridge WinDivert 4.3.0**. The product Core ran in a process managed by the laboratory; these are not measurements of the official GUI or CLI. The generator, receiver, and SOCKS5 relay ran on the same machine over IPv4 loopback. This setup supports functional verification and limited comparisons; it does not establish maximum throughput over an external network. Accidental VM runs are excluded from these results.

The ordinary measurements below used laboratory **preview.56**, NORMAL/LOW settings, and matching recorded conditions. Endurance results use a separate fixed profile and explicitly identified laboratory versions. These datasets are not combined into a single resource ranking.

## Repeated runs at ordinary load

On October 26, each build completed two additional runs covering TCP latency under load, many concurrent TCP connections, new connection creation, and SFTP. All 16 selected checks passed: exchange, routing, and the requested load rate were verified, with no whole-system CPU saturation recorded. The numbers below are ranges from two runs, not confidence intervals.

| Measurement | WFP 4da324e | WinDivert 4.3.0 |
|---|---:|---:|
| TCP under load: RTT p99, ms | 1.058–1.146 | 5.361–6.102 |
| Same profile: process CPU time during load, s | 0.546875–0.609375 | 4.265625–4.625 |
| 128 TCP connections: probe RTT p99, ms | 2.021–2.211 | 39.229–42.904 |
| Many TCP connections: peak process private commit, MiB | 45.2266–45.2344 | 8.4844–8.5273 |
| Connection creation: successful / attempted, each run | 180/180 | 180/180 |
| Connection creation: process CPU time during load, s | 0.296875–0.328125 | 2.125–2.296875 |
| SFTP: process CPU time per 1,000 verified cycles, s | 1.4428–1.4757 | 7.5174–7.6736 |

**In these scenarios, WFP showed lower latency and lower CPU cost in the observed process. WinDivert used less process private commit in the many-connections check.** The direction of the differences repeated in both runs. This does not establish the total CPU or RAM cost of either architecture.

The amount of completed work can differ despite equal duration and requested rate. In SFTP, WFP completed 888 and 900 cycles, while WinDivert completed 900 in each run; the requested rate was met within the 5% tolerance. SFTP CPU cost is normalized by the actual number of verified cycles. Ranking the approaches solely by total operation counts would be misleading.

Detailed conditions, attempt identifiers, and calculation checks: [repeat-run audit](PB_SUT_REPEAT56_AUDIT_2026-10-26.md).

## Functional limitations in the ordinary suite

The preceding ordinary runs on preview.56 produced:

| Approach | Outcome of 44 selected checks |
|---|---|
| WFP 4da324e | 43 passed, 1 unverified |
| WinDivert 4.3.0 | 33 passed, 11 failed |

The unverified WFP scenario used many UDP flows: the generator and relay counters differed by 70 packets out of 96,002. A low loss fraction did not turn incomplete route accounting into a PASS. WinDivert failures involved UDP scenarios, including QUIC/HTTP3 and mixed workloads. These results should not automatically be classified as driver defects; establishing their causes requires separate fault isolation.

Four TCP speed profiles also do not establish ProxyBridge's maximum performance: some WFP windows saturated the shared machine's CPU, and directional asymmetry was observed. Measuring peak throughput requires a separate receiver and checks for generator and relay bottlenecks.

This describes the specific October 26 dataset, not a claim that all UDP traffic fails with WinDivert. Details: [ordinary-run audit](PB_SUT_NORMAL56_AUDIT_2026-10-26.md).

## Endurance checks

The fixed profile cycles through ordinary activity, bursts, connection creation, quiet periods, and recovery. Persistent TCP and UDP channels remain active throughout the run; six application protocols are checked periodically, with separate DIRECT/BLOCK checks. This workload is not equivalent to all the ordinary UDP scenarios above.

| Build | Laboratory | Outcome |
|---|---|---|
| WinDivert 4.3.0 | preview.60 | Completed 7,200 seconds of load; one QUIC close failure despite verified data exchange. Overall result failed. |
| WFP 4da324e | preview.62 | Completed all 7,200 seconds of load, COMPLETE; exchange and routing verified for all 212 completed jobs. |

After the WinDivert run, the laboratory's fixed QUIC close wait was revised: preview.61 follows the library timer within a bounded budget. The exact timer for the historical failure was not recorded, so its specific cause remains unproven. The change was checked in short runs, but this dataset does not yet include a full WinDivert H2 run on preview.62. The old report has not been reclassified as successful.

The WFP run on preview.62 recorded:

- TCP: 14,400 verified exchanges over the persistent connection.
- UDP: 36,000/36,000, with no lost or invalid replies.
- HTTP, HTTPS, HTTP/2, SFTP, DNS-TCP, and QUIC: 16 successful windows each, including QUIC closure.
- DIRECT/BLOCK: 464/464 successful checks, with stable rules and Core process.
- Verified cleanup, with the device disabled afterward. The previous false callback failures and roughly one-hour stop did not recur; the cause of the historical RPC failure remains unknown.

Runs of 24, 48, or 72 hours are not verified here. One successful H2 run does not establish the absence of all leaks or coverage of all network traffic on the PC.

Sources: [WinDivert H2](PB_SUT_WINDIVERT_H2_60_AUDIT_2026-10-27.md), [QUIC close fix](QUIC_CLOSE_TIMER_PREVIEW61_2026-10-27.md), [WFP H2](PB_SUT_WFP_H2_62_AUDIT_2026-10-27.md).

## Interpreting resource measurements

Process CPU time, execution samples from the selected SYS module, whole-system CPU, and memory attributed by pool tags have different measurement scopes. **These data do not establish the total CPU or RAM cost of either architecture.**

A small WFP sample count does not mean zero cost. Work in TCP/IP, WFP, NDIS, and other shared Windows components can also depend on the approach, but is not fully covered by observing the selected SYS module. These values cannot simply be added to process CPU. Tagged memory is not the entire RAM footprint of the driver and network stack; kernel ETW is disabled in endurance mode.

Compare performance only after verifying exchange, routing, and load, using comparable conditions and repeated runs. Lower latency or process CPU cost in the listed profiles does not imply superiority across all protocols, stability requirements, memory use, or loads. [Historical results from the earlier technical harness](test-results.md) use a different methodology and are not combined with these measurements.
