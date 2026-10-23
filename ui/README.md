# Local ProxyBridge application

Open `http://127.0.0.1:5178/` (or `/lab.html`). The bilingual application uses
Builds → Testing → Run → Results/History. Find the installed driver-based
ProxyBridge or choose its folder manually, then select tests and independent
duration/load settings. Preparation is files-only; execution is explicit.

The local catalog connects TCP RTT, independent upload/download, three modes,
TCP connections/recovery, UDP echo and RTT under concurrent transfer. Every
controller retains route, payload, identity and cleanup checks. Known UDP reply
source errors remain correctness failures even when scoped metrics are valid.
Unavailable methods are shown separately; 4.0.0 needs its separate reboot adapter.

An installation is bound by observed binary hashes, never by its name. Plans
freeze the selected paths in a restricted internal input plus dependency hashes.
Unknown binaries still need actual lifecycle/route evidence. No driver installation,
signing, system proxy or power changes are performed by preparation.

Stop is cooperative: the current run verifies and cleans up before the next is
skipped. Jobs survive navigation. Restarted unfinished jobs are interrupted and
are never automatically resumed. History retains failures and cancellation;
comparison never silently substitutes an older success. CPU/RAM are scoped to
the observed CLI/Core process, not separately to the driver.

For development, use .NET 10:

```powershell
dotnet run --project ui/ProxyBridge.TestLab.Ui/ProxyBridge.TestLab.Ui.csproj
```

For a separate local package (SDK/runtime packs required only on the build machine):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-LocalApp.ps1
```

Open the package's `Start.cmd` and accept the standard Windows UAC prompt.
.NET, Python and controlled helper tools are included. ProxyBridge binaries,
private keys, captures, kits, test fixtures and research source trees are excluded.
The package manifest explicitly records pending administrator/runtime acceptance.
Do not use a successful build or synthetic gate check as product validation.

See [development handoff](../docs/CHAT_HANDOFF_DEVELOPMENT.md) for verification
and remaining boundaries. The older technical API/interface is retained for
compatibility; it is not the default local workflow.