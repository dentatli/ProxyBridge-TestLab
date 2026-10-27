# ProxyBridge TestLab

**English** | [Русский](README.ru.md)

A laboratory for testing [ProxyBridge](https://github.com/InterceptSuite/ProxyBridge) and comparing builds using **WFP** and **WinDivert**. The application generates controlled network traffic, verifies data exchange and rule enforcement, collects measurements, and saves reports.

The primary workflow is **On this PC**, accessed through a local web interface. The traffic generator, receiver, and SOCKS5 relay run on the machine under test. This mode requires no separate server. Remote host selection is temporarily disabled in the interface. The interface supports English and Russian.

## Features

- Ten check groups: TCP, UDP, HTTP/WebSocket/gRPC, TLS/QUIC, DNS, SSH/SFTP, mail, messaging, stability, and endurance.
- Select stages, coverage, duration, and load; save, import, and export test suites.
- Verify PROXY, DIRECT, and BLOCK rules in the scenarios that exercise them.
- Follow progress through expandable groups and stages, retain partial results, and verify cleanup after stopping.
- Inspect reports, details, and logs; download JSON results; compare up to four runs in a table.
- Run a separate 2/24/48/72-hour endurance check with a fixed load cycle. It cannot be selected together with other checks.

The laboratory tests specific scenarios and conditions. A successful run does not establish compatibility with every application, traffic type, or network configuration.

## Requirements

- Windows 11 x64, the verified platform for the current local package.
- Administrator privileges for network checks.
- A separately installed or prepared ProxyBridge build with its matching driver.
- An available local port 5178 and a web browser.

For **WinDivert, support is declared only for ProxyBridge 4.3.0**. Support for other versions is not claimed. For WFP, select a specific build package; validating its files alone does not establish that it works correctly.

The prepared local package includes .NET, Python 3.11, and dependencies. On this PC does not require a separate Python or .NET Runtime installation, Ubuntu, or SSH setup. ProxyBridge and its product driver are not included. Driver installation and signing requirements depend on the selected ProxyBridge build.

## Installation and quick start

Public ready-to-run archives have not yet been published in [GitHub Releases](https://github.com/dentatli/ProxyBridge-TestLab/releases). The following instructions apply to a prepared `ProxyBridge-TestLab-…-win-x64` package.

1. Extract the entire package into its own folder, preserving the directory structure.
2. Run `Start.cmd` and approve the Windows administrator prompt.
3. The laboratory opens in your browser. If no tab appears, open [localhost:5178](http://127.0.0.1:5178/lab.html).
4. In **Builds**, locate the installed ProxyBridge or enter its folder manually. Select WFP or WinDivert, validate the files, and save the build.
5. In the machine setup step, select **On this PC**.
6. In **Select checks**, choose the checks and their settings. For an initial short run, use TCP with basic coverage, Quick duration, and Low load.
7. Open the run step, review the selection and estimated duration, and start the queue.
8. After completion, open **Results** to view the report, stage details, logs, and run comparison.

To stop a check, use the application's stop button and wait for cleanup confirmation. Before replacing the package, finish any active check and close the previous instance. Settings, saved builds, and history are stored separately from the package in the Windows user profile; use the same Windows account when launching the laboratory.

[Publish-LocalApp.ps1](scripts/Publish-LocalApp.ps1) prepares a package from source. The build machine needs the .NET 10 SDK, MSVC x64, Python 3.11, and prepared runtime dependencies and helper executables. These are build requirements, not additional requirements for running the prepared package.

## Comparison results

Measurements, test conditions, supported conclusions, and limitations are documented separately in **[WFP and WinDivert comparison results](docs/COMPARISON_RESULTS.md)**.

## License

[MIT](LICENSE).
