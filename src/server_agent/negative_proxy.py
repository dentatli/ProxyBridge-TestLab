from __future__ import annotations

import hashlib
import re
from typing import Any


class NegativeProxyContractError(ValueError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


_IDENTITY = "testlab-isolated-negative-socks5-v1"
_ATTEMPT_ID_MAX_LENGTH = 64
_ATTEMPT_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")


def validate_negative_proxy_config(value: object, allocated_ports: set[int] | None = None) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"enabled", "identity", "auth_port", "unavailable_port"}:
        raise NegativeProxyContractError("NEGATIVE_PROXY_CONFIG_FIELDS_INVALID")
    if value["enabled"] is not False:
        raise NegativeProxyContractError("NEGATIVE_PROXY_RUNTIME_DISABLED")
    if value["identity"] != _IDENTITY:
        raise NegativeProxyContractError("NEGATIVE_PROXY_IDENTITY_INVALID")
    auth_port = value["auth_port"]
    unavailable_port = value["unavailable_port"]
    if (isinstance(auth_port, bool) or not isinstance(auth_port, int) or auth_port < 1 or auth_port > 65535 or
            isinstance(unavailable_port, bool) or not isinstance(unavailable_port, int) or unavailable_port < 1 or unavailable_port > 65535 or
            auth_port == unavailable_port):
        raise NegativeProxyContractError("NEGATIVE_PROXY_PORTS_INVALID")
    if allocated_ports is not None and (auth_port in allocated_ports or unavailable_port in allocated_ports):
        raise NegativeProxyContractError("NEGATIVE_PROXY_PORT_COLLISION")
    return {
        "semantic_version": 1,
        "identity": _IDENTITY,
        "auth_listener_state": "NOT_VERIFIED",
        "unavailable_state": "NOT_VERIFIED",
        "proof_required": True,
        "relay_count": 0,
    }


def evaluate_socks5_auth_attempt(greeting: bytes, authentication: bytes, attempt_id: str) -> dict[str, Any]:
    if not isinstance(attempt_id, str) or len(attempt_id) > _ATTEMPT_ID_MAX_LENGTH or not _ATTEMPT_ID.fullmatch(attempt_id):
        raise NegativeProxyContractError("NEGATIVE_PROXY_ATTEMPT_ID_INVALID")
    if len(greeting) < 2 or greeting[0] != 5 or greeting[1] == 0 or len(greeting) != greeting[1] + 2 or 2 not in greeting[2:]:
        raise NegativeProxyContractError("NEGATIVE_PROXY_METHOD_NEGOTIATION_INVALID")
    if len(authentication) < 3 or authentication[0] != 1:
        raise NegativeProxyContractError("NEGATIVE_PROXY_AUTH_FRAME_INVALID")
    username_length = authentication[1]
    username_end = 2 + username_length
    if username_length == 0 or username_end >= len(authentication):
        raise NegativeProxyContractError("NEGATIVE_PROXY_AUTH_FRAME_INVALID")
    password_length = authentication[username_end]
    if password_length == 0 or username_end + 1 + password_length != len(authentication):
        raise NegativeProxyContractError("NEGATIVE_PROXY_AUTH_FRAME_INVALID")
    try:
        attempt_bytes = attempt_id.encode("ascii", "strict")
    except UnicodeEncodeError as exc:
        raise NegativeProxyContractError("NEGATIVE_PROXY_ATTEMPT_ID_INVALID") from exc
    principal_digest = hashlib.sha256(
        b"proxybridge-testlab-negative-proxy-v1\0" + attempt_bytes + b"\0" + authentication[2:username_end]
    ).hexdigest()
    return {
        "method_reply": b"\x05\x02",
        "auth_reply": b"\x01\x01",
        "auth_rejected": True,
        "principal_digest": principal_digest,
        "relay_count": 0,
    }


def self_test(config: object) -> dict[str, Any]:
    semantic = validate_negative_proxy_config(config)
    attempt = evaluate_socks5_auth_attempt(b"\x05\x02\x00\x02", b"\x01\x01x\x01y", "negative-proxy-self-test")
    if attempt["auth_reply"] != b"\x01\x01" or attempt["relay_count"] != 0 or len(attempt["principal_digest"]) != 64:
        raise NegativeProxyContractError("NEGATIVE_PROXY_SELF_TEST_FAILED")
    return semantic
