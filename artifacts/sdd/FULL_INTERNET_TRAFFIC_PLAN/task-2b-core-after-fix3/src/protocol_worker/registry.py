from __future__ import annotations

import json
import importlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping

from model import WorkerContractError, WorkerPlan
from plugins.selftest import run_contract_selftest
from plugins.dns import run_dns
from plugins.http1 import run_http1
from plugins.tls import run_tls


PluginRunner = Callable[[WorkerPlan], list[dict[str, Any]]]


@dataclass(frozen=True)
class PluginRegistration:
    plugin_id: str
    evidence_profile_id: str
    required_fields: frozenset[str]
    network_access: bool
    runner: PluginRunner


STATIC_RUNNERS: dict[str, PluginRunner] = {
    "contract-selftest": run_contract_selftest,
    "protocol-dns": run_dns,
    "protocol-http": run_http1,
    "protocol-tls": run_tls,
}

LAZY_RUNNERS: dict[str, tuple[str, str]] = {
    "browser-worker": ("plugins.browser", "run_browser"),
    "protocol-http2": ("plugins.http2", "run_http2"),
    "protocol-grpc": ("plugins.http2", "run_grpc"),
    "protocol-websocket": ("plugins.websocket", "run_websocket"),
    "protocol-quic": ("plugins.quic", "run_quic_http3"),
    "protocol-webtransport": ("plugins.quic", "run_webtransport"),
    "protocol-ftp": ("plugins.standard", "run_ftp"),
    "protocol-mail": ("plugins.standard", "run_mail"),
    "protocol-messaging": ("plugins.standard", "run_messaging"),
    "protocol-ntp": ("plugins.standard", "run_ntp"),
    "protocol-irc": ("plugins.standard", "run_irc"),
    "protocol-multipeer": ("plugins.standard", "run_multipeer"),
    "protocol-realtime": ("plugins.realtime", "run_realtime"),
    "protocol-media": ("plugins.realtime", "run_media"),
    "protocol-receive-only": ("plugins.realtime", "run_receive_only"),
    "protocol-failure": ("plugins.failure", "run_process_termination"),
}


def load_registry(manifest_path: Path) -> dict[str, PluginRegistration]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WorkerContractError("PLUGIN_MANIFEST_INVALID") from exc
    if not isinstance(manifest, Mapping) or manifest.get("schema_version") != 1:
        raise WorkerContractError("PLUGIN_MANIFEST_SCHEMA_UNSUPPORTED")
    registrations: dict[str, PluginRegistration] = {}
    for raw in manifest.get("plugins", []):
        if not isinstance(raw, Mapping):
            raise WorkerContractError("PLUGIN_MANIFEST_ENTRY_INVALID")
        plugin_id = str(raw.get("id", ""))
        if plugin_id in registrations:
            raise WorkerContractError("PLUGIN_MANIFEST_DUPLICATE")
        if raw.get("implementation_status") != "IMPLEMENTED":
            continue
        runner = STATIC_RUNNERS.get(plugin_id)
        if runner is None and plugin_id not in LAZY_RUNNERS:
            raise WorkerContractError("PLUGIN_RUNNER_NOT_STATIC")
        required_fields = raw.get("required_evidence_fields", [])
        if not isinstance(required_fields, list) or not required_fields:
            raise WorkerContractError("PLUGIN_EVIDENCE_CONTRACT_MISSING")
        registrations[plugin_id] = PluginRegistration(
            plugin_id=plugin_id,
            evidence_profile_id=str(raw.get("evidence_profile_id", "")),
            required_fields=frozenset(str(item) for item in required_fields),
            network_access=bool(raw.get("network_access", True)),
            runner=runner or (lambda plan, selected=plugin_id: _load_lazy_runner(selected)(plan)),
        )
    if not registrations:
        raise WorkerContractError("PLUGIN_REGISTRY_EMPTY")
    return registrations


def _load_lazy_runner(plugin_id: str) -> PluginRunner:
    module_name, function_name = LAZY_RUNNERS[plugin_id]
    try:
        runner = getattr(importlib.import_module(module_name), function_name)
    except (ImportError, AttributeError) as exc:
        raise WorkerContractError("PLUGIN_DEPENDENCY_UNAVAILABLE") from exc
    if not callable(runner):
        raise WorkerContractError("PLUGIN_RUNNER_INVALID")
    return runner


def resolve_plugin(plan: WorkerPlan, registry: Mapping[str, PluginRegistration]) -> PluginRegistration:
    registration = registry.get(plan.plugin_id)
    if registration is None:
        raise WorkerContractError("PLUGIN_NOT_IMPLEMENTED")
    return registration
