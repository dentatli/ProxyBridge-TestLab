# Offline apply checkpoint probe

Run `dotnet run --project tests/fixtures/traffic-apply-checkpoint/TrafficApplyCheckpointProbe.csproj -c Release`.
The project links the production checkpoint class directly, creates an isolated
temporary directory and validates its resolved cleanup target before deleting it.
It does not use application storage, credentials, SSH, services or product traffic.

Checks cover a durable marker before dispatch, exclusive ownership while a lease
is active, uncertainty surviving a new controller instance, rejection of another
target, resolution only after inspection, separate confirmed success/failure
receipts, retention of prior uncertainty and refusal to infer a torn target identity.

Live GUI verification uses explicitly labelled simulated markers and read-only
inspection of the dedicated Ubuntu. This fixture does not claim a real SSH/network
disconnect during a running installer or verification of arbitrary crash points.
