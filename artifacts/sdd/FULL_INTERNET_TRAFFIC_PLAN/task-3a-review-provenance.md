# Task 3a review baseline provenance

Every baseline matches task-3a-before/manifest.sha256 (byte SHA-256).
Diff text normalizes CRLF to LF. Historical progress.md is excluded from code scope.

- `src/server_agent/failure_protocols.py`: current unchanged; baseline `0360e8872391f730b9a3bd35c57d06bcfb35eabe74d1ad7e85bc0c4a3bf73b6b`.
- `src/server_agent/negative_proxy.py`: absent; baseline `ABSENT`.
- `src/server_agent/pb_protocol_server.py`: artifacts\sdd\FULL_INTERNET_TRAFFIC_PLAN\task-2a-after-fix1\src\server_agent\pb_protocol_server.py; baseline `442b6b7a8bd95a23d99044fadf251c32cc4d02194afda5b2c325c4c985e96c9d`.
- `src/server_agent/plugins/catalog.json`: current unchanged; baseline `c0757541c3326b9130d8287125fbd88886af8da49565ea24ae11d4e380267b5c`.
- `ui/ProxyBridge.TestLab.Ui/Services/ServerArtifactBuilder.cs`: artifacts\sdd\FULL_INTERNET_TRAFFIC_PLAN\task-2a-after\ui\ProxyBridge.TestLab.Ui\Services\ServerArtifactBuilder.cs; baseline `2ad9e48d3a12bbad13d2dfaabbf129f832273cbebce8a442173ac6cd408caced`.
- `tests/Test-FailureControl.ps1`: current unchanged; baseline `a7689c681db3ffca1cceb765e50a90faa282ff46587d37a408d73bd321b02b37`.
- `tests/Test-ServerProvisioning.ps1`: artifacts\sdd\FULL_INTERNET_TRAFFIC_PLAN\task-2a-after\tests\Test-ServerProvisioning.ps1; baseline `b108f9520da0dc4e8c5cdd54f18bee051df5a8dc5056e25c3413bc42bb4fe57d`.
- `tests/fixtures/failure-control/contract_test.py`: hash-verified reversal of negative-proxy fixture additions; baseline `35b31b380655907d577a5af111d49cd8c4389965ec1b155bf3eb2bcffebfd02c`.
- `config/server-protocol-ports.json`: hash-verified reversal of reserved-port addition; baseline `edaef55c275a3117293c21af3d374dacce35e0a63f6045d9c2ae3bde15c0f1df`.
- `ui/ProxyBridge.TestLab.Ui/Services/ServerProtocolPortCatalog.cs`: hash-verified reversal of required-name addition; baseline `9ef16cbaabf72f373a9c049589db271d0161a2407a6f2b5182591d1f52757911`.
- `ui/ProxyBridge.TestLab.Ui.ServerProbe/Program.cs`: artifacts\sdd\FULL_INTERNET_TRAFFIC_PLAN\task-2a-after\ui\ProxyBridge.TestLab.Ui.ServerProbe\Program.cs; baseline `fc2604f0500c3a0a6ce4c57bff6f85533378c9b6d16ba869a926d8efccd5f6c3`.
