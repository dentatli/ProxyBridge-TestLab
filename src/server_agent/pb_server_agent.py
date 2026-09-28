from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
SAFE_RELATIVE_PATH = re.compile(r"^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class AgentContractError(ValueError):
    pass


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise AgentContractError("MANIFEST_READ_FAILED") from exc
    if data.startswith(b"\xef\xbb\xbf"):
        raise AgentContractError("MANIFEST_BOM_FORBIDDEN")
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AgentContractError("MANIFEST_JSON_INVALID") from exc
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise AgentContractError("MANIFEST_SCHEMA_UNSUPPORTED")
    return value


def _file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise AgentContractError("ARTIFACT_READ_FAILED") from exc
    return digest.hexdigest()


def validate_manifest(manifest_path: Path) -> int:
    manifest_path = manifest_path.resolve()
    root = manifest_path.parent
    manifest = _load_json(manifest_path)
    if manifest.get("agent_contract_version") != 1:
        raise AgentContractError("AGENT_CONTRACT_UNSUPPORTED")
    artifacts = manifest.get("artifacts")
    plugins = manifest.get("plugins")
    if not isinstance(artifacts, list) or not artifacts or not isinstance(plugins, list) or not plugins:
        raise AgentContractError("MANIFEST_CONTENT_INCOMPLETE")
    artifact_paths: set[str] = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise AgentContractError("ARTIFACT_ENTRY_INVALID")
        relative = str(artifact.get("path", ""))
        expected = str(artifact.get("sha256", ""))
        if not SAFE_RELATIVE_PATH.fullmatch(relative) or not SHA256.fullmatch(expected):
            raise AgentContractError("ARTIFACT_CONTRACT_INVALID")
        if relative in artifact_paths:
            raise AgentContractError("ARTIFACT_DUPLICATE")
        artifact_paths.add(relative)
        candidate = (root / Path(relative)).resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise AgentContractError("ARTIFACT_PATH_ESCAPE") from exc
        if not candidate.is_file() or candidate.is_symlink():
            raise AgentContractError("ARTIFACT_MISSING_OR_LINK")
        if _file_hash(candidate) != expected:
            raise AgentContractError("ARTIFACT_HASH_MISMATCH")
    plugin_ids: set[str] = set()
    for plugin in plugins:
        if not isinstance(plugin, dict):
            raise AgentContractError("PLUGIN_ENTRY_INVALID")
        plugin_id = str(plugin.get("id", ""))
        if not SAFE_ID.fullmatch(plugin_id) or plugin_id in plugin_ids:
            raise AgentContractError("PLUGIN_ID_INVALID_OR_DUPLICATE")
        plugin_ids.add(plugin_id)
        if plugin.get("implementation_status") != "IMPLEMENTED":
            raise AgentContractError("INSTALLED_PLUGIN_STATUS_INVALID")
        references = plugin.get("artifacts")
        capabilities = plugin.get("capabilities")
        if not isinstance(references, list) or not references or not isinstance(capabilities, list) or not capabilities:
            raise AgentContractError("PLUGIN_CONTRACT_INCOMPLETE")
        if any(str(reference) not in artifact_paths for reference in references):
            raise AgentContractError("PLUGIN_ARTIFACT_UNKNOWN")
        if any(not SAFE_ID.fullmatch(str(capability)) for capability in capabilities):
            raise AgentContractError("PLUGIN_CAPABILITY_INVALID")
    return len(plugin_ids)


def _port(value: str) -> int:
    try:
        port = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("invalid port") from exc
    if port < 1 or port > 65535:
        raise argparse.ArgumentTypeError("invalid port")
    return port


def _validate_serve_arguments(arguments: argparse.Namespace, root: Path) -> tuple[Path, Path, Path]:
    endpoint = (root / "pb_net_endpoint.py").resolve()
    protocol = (root / "pb_protocol_server.py").resolve()
    config = Path(str(arguments.protocol_config)).resolve()
    for candidate in (endpoint, protocol, config):
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise AgentContractError("SERVE_PATH_ESCAPE") from exc
        if not candidate.is_file() or candidate.is_symlink():
            raise AgentContractError("SERVE_ARTIFACT_MISSING")
    endpoint_log = Path(str(arguments.endpoint_log))
    if not endpoint_log.is_absolute():
        raise AgentContractError("SERVE_LOG_PATH_INVALID")
    try:
        if ipaddress.ip_address(str(arguments.bind_ipv4)).version != 4:
            raise AgentContractError("SERVE_BIND_ADDRESS_INVALID")
        if arguments.bind_ipv6 and ipaddress.ip_address(str(arguments.bind_ipv6)).version != 6:
            raise AgentContractError("SERVE_BIND_ADDRESS_INVALID")
    except ValueError as exc:
        raise AgentContractError("SERVE_BIND_ADDRESS_INVALID") from exc
    return endpoint, protocol, config


def _stop_children(children: list[subprocess.Popen[bytes]]) -> None:
    for child in children:
        if child.poll() is None:
            child.terminate()
    deadline = time.monotonic() + 5.0
    while any(child.poll() is None for child in children) and time.monotonic() < deadline:
        time.sleep(0.05)
    for child in children:
        if child.poll() is None:
            child.kill()
    for child in children:
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def serve(arguments: argparse.Namespace, manifest_path: Path) -> int:
    root = manifest_path.resolve().parent
    endpoint, protocol, config = _validate_serve_arguments(arguments, root)
    endpoint_command = [
        sys.executable, "-B", str(endpoint), "--jsonl-log", str(arguments.endpoint_log),
        "--bind-ipv4", str(arguments.bind_ipv4), "--endpoint-a-port", str(arguments.endpoint_a_port),
        "--endpoint-b-port", str(arguments.endpoint_b_port),
    ]
    if arguments.bind_ipv6:
        endpoint_command.extend(["--bind-ipv6", str(arguments.bind_ipv6)])
    protocol_command = [sys.executable, "-B", str(protocol), "--serve", "--config", str(config)]
    stopping = False

    def request_stop(_signum: int, _frame: Any) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    children: list[subprocess.Popen[bytes]] = []
    try:
        children.append(subprocess.Popen(endpoint_command, stdin=subprocess.DEVNULL))
        children.append(subprocess.Popen(protocol_command, stdin=subprocess.DEVNULL))
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline and not stopping:
            if any(child.poll() is not None for child in children):
                print("SERVER_AGENT_ERROR CHILD_EXITED_DURING_STARTUP", file=sys.stderr)
                return 33
            time.sleep(0.05)
        if stopping:
            return 0
        print("SERVER_AGENT_READY children=2", flush=True)
        while not stopping:
            if any(child.poll() is not None for child in children):
                print("SERVER_AGENT_ERROR CHILD_EXITED", file=sys.stderr)
                return 34
            time.sleep(0.1)
        return 0
    except OSError:
        print("SERVER_AGENT_ERROR CHILD_START_FAILED", file=sys.stderr)
        return 35
    finally:
        _stop_children(children)


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--endpoint-log")
    parser.add_argument("--protocol-config")
    parser.add_argument("--bind-ipv4", default="0.0.0.0")
    parser.add_argument("--bind-ipv6", default="")
    parser.add_argument("--endpoint-a-port", type=_port)
    parser.add_argument("--endpoint-b-port", type=_port)
    arguments = parser.parse_args()
    if arguments.self_test == arguments.serve:
        print("SERVER_AGENT_ERROR MODE_INVALID", file=sys.stderr)
        return 30
    try:
        manifest_path = Path(arguments.manifest)
        count = validate_manifest(manifest_path)
        if arguments.self_test:
            print(f"SERVER_AGENT_SELF_TEST_OK plugins={count}")
            return 0
        if not arguments.endpoint_log or not arguments.protocol_config or arguments.endpoint_a_port is None or arguments.endpoint_b_port is None:
            raise AgentContractError("SERVE_ARGUMENT_MISSING")
        return serve(arguments, manifest_path)
    except AgentContractError as exc:
        print(f"SERVER_AGENT_ERROR {exc}", file=sys.stderr)
        return 31
    except Exception:
        print("SERVER_AGENT_ERROR UNEXPECTED_FAILURE", file=sys.stderr)
        return 32


if __name__ == "__main__":
    raise SystemExit(main())
