[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$endpoint = Join-Path $root 'src\pb_net_endpoint.py'
$python = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $python) { throw 'PYTHON_REQUIRED_FOR_ENDPOINT_CONTRACT_TEST' }

$program = @'
import importlib.util
import json
import pathlib
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
compile(source, str(path), "exec")
assert 'message_buffer.startswith(b"PBCT")' in source
assert 'payload.startswith(b"PBUD")' in source
assert 'SERVER_CLOSED' in source and 'RESET_BY_PEER' in source
spec = importlib.util.spec_from_file_location("pb_net_endpoint_contract", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
payload = b"PB_NET|test_id=tcp-ipv4-direct|run_id=run-123|sequence=2|phase=second_flow|protocol=TCP\n"
identity = module.payload_identity(payload)
assert identity == {"test_id": "tcp-ipv4-direct", "run_id": "run-123", "sequence": 2, "phase": "second_flow"}
assert module.payload_identity(payload.replace(b"protocol=TCP", b"protocol=HTTP"))["run_id"] == ""
assert module.payload_identity(b"unrelated payload")["sequence"] == 0
assert module.MAX_UDP_PAYLOAD == 65507
assert module.MAX_PAYLOAD >= 1048576
with tempfile.TemporaryDirectory() as directory:
    log_path = pathlib.Path(directory) / "endpoint.jsonl"
    logger = module.JsonlLogger(log_path)
    logger.write(event="RECEIVED", family="IPv4", protocol="UDP", payload=b"")
    logger.write(event="CLOSED", family="IPv4", protocol="TCP", payload=b"closed-payload")
    logger.close()
    records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]
    assert records[0]["sha256"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert records[1]["sha256"] and records[1]["event"] == "CLOSED"
print("PASS: endpoint evidence identity")
'@

$temp = New-TestDirectory
try {
    $probe = Join-Path $temp 'endpoint-contract-probe.py'
    Write-TestUtf8NoBom -Path $probe -Text $program
    $output = & $python.Source $probe $endpoint
    Assert-Equal 0 $LASTEXITCODE 'endpoint contract Python exit code'
    Assert-True (@($output) -contains 'PASS: endpoint evidence identity') 'endpoint payload identity must be strict and fail closed'
}
finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }

'PASS: endpoint evidence contract'
