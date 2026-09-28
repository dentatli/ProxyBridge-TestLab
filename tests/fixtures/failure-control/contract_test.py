import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / "src" / "server_agent"))

from failure_control import FailureControlError, execute_failure_control_request
from negative_proxy import (
    NegativeProxyContractError,
    evaluate_socks5_auth_attempt,
    validate_negative_proxy_config,
)


class FakeAdapter:
    def __init__(self, *, rollback_verified=True, restart_invocation="invocation-after", healthy_invocation="invocation-after"):
        self.calls = []
        self.rollback_verified = rollback_verified
        self.restart_invocation = restart_invocation
        self.healthy_invocation = healthy_invocation

    def await_barrier(self, receipt_id, request_id, timeout_ms):
        self.calls.append(("await_barrier", receipt_id, request_id, timeout_ms))
        return {"state": "ARMED", "invocation_id": "invocation-before"}

    def restart(self, target, timeout_ms):
        self.calls.append(("restart", target, timeout_ms))
        return {"state": "RESTARTED", "invocation_id": self.restart_invocation}

    def verify_health(self, target, invocation_id, timeout_ms):
        self.calls.append(("verify_health", target, invocation_id, timeout_ms))
        return {"state": "HEALTHY", "invocation_id": self.healthy_invocation}

    def verify_rollback(self, receipt_id, request_id, timeout_ms):
        self.calls.append(("verify_rollback", receipt_id, request_id, timeout_ms))
        return self.rollback_verified


REQUEST = {
    "schema_version": 1,
    "receipt_id": "a" * 64,
    "request_id": "b" * 32,
    "target": "proxybridge-testlab-endpoint.service",
    "action": "restart",
    "timeout_ms": 1200,
}


def expect_error(value, code):
    try:
        execute_failure_control_request(json.dumps(value), FakeAdapter())
    except FailureControlError as error:
        assert error.code == code, (error.code, code)
        return
    raise AssertionError(f"expected {code}")


adapter = FakeAdapter()
result = execute_failure_control_request(json.dumps(REQUEST), adapter)
assert result["receipt_id"] == REQUEST["receipt_id"]
assert result["request_id"] == REQUEST["request_id"]
assert result["target"] == REQUEST["target"]
assert result["action"] == "restart"
assert result["timeout_ms"] == 1200
assert result["invocation_id_before"] == "invocation-before"
assert result["invocation_id_after"] == "invocation-after"
assert result["rollback_verified"] is True
assert result["barrier_states"] == ["ARMED", "RESTARTED", "HEALTHY", "ROLLBACK_VERIFIED"]
assert adapter.calls == [
    ("await_barrier", "a" * 64, "b" * 32, 1200),
    ("restart", "proxybridge-testlab-endpoint.service", 1200),
    ("verify_health", "proxybridge-testlab-endpoint.service", "invocation-after", 1200),
    ("verify_rollback", "a" * 64, "b" * 32, 1200),
]

expect_error({**REQUEST, "shell": "systemctl restart other.service"}, "FAILURE_CONTROL_REQUEST_FIELDS_INVALID")
expect_error({**REQUEST, "target": "other.service"}, "FAILURE_CONTROL_TARGET_INVALID")
expect_error({**REQUEST, "timeout_ms": 0}, "FAILURE_CONTROL_TIMEOUT_INVALID")

try:
    execute_failure_control_request(json.dumps(REQUEST), FakeAdapter(rollback_verified=False))
except FailureControlError as error:
    assert error.code == "FAILURE_CONTROL_ROLLBACK_UNVERIFIED"
else:
    raise AssertionError("unverified rollback must fail closed")

try:
    execute_failure_control_request(json.dumps(REQUEST), FakeAdapter(restart_invocation="invocation-before"))
except FailureControlError as error:
    assert error.code == "FAILURE_CONTROL_INVOCATION_NOT_CHANGED"
else:
    raise AssertionError("restart must produce a new invocation identity")


NEGATIVE_PROXY_CONFIG = {
    "enabled": False,
    "auth_port": 46080,
    "unavailable_port": 46081,
    "identity": "testlab-isolated-negative-socks5-v1",
}

def expect_negative_error(callback, code):
    try:
        callback()
    except NegativeProxyContractError as error:
        assert error.code == code, (error.code, code)
        return
    raise AssertionError(f"expected {code}")


def auth_frame(password: bytes) -> bytes:
    return b"\x01\x0cfixture-user" + bytes([len(password)]) + password


def assert_negative_proxy_regressions() -> None:
    failures = []

    def check(name, callback):
        try:
            callback()
        except (AssertionError, NegativeProxyContractError, TypeError) as error:
            failures.append(name + ":" + str(error))

    check("planned-artifacts", lambda: assert_planned_artifacts_empty())
    check("not-verified-state", lambda: assert_not_verified_state())
    check("multi-method", lambda: assert_multi_method_rejected_auth())
    check("password-independent-digest", lambda: assert_password_independent_digest())
    check("global-port-collision", lambda: expect_negative_error(
        lambda: validate_negative_proxy_config(NEGATIVE_PROXY_CONFIG, {46080}), "NEGATIVE_PROXY_PORT_COLLISION"))
    check("global-unavailable-port-collision", lambda: expect_negative_error(
        lambda: validate_negative_proxy_config(NEGATIVE_PROXY_CONFIG, {46081}), "NEGATIVE_PROXY_PORT_COLLISION"))
    check("invalid-attempt", lambda: expect_negative_error(
        lambda: evaluate_socks5_auth_attempt(b"\x05\x01\x02", auth_frame(b"x"), "invalid attempt"),
        "NEGATIVE_PROXY_ATTEMPT_ID_INVALID"))
    check("truncated-greeting", lambda: expect_negative_error(
        lambda: evaluate_socks5_auth_attempt(b"\x05\x02\x02", auth_frame(b"x"), "attempt-negative-proxy-1"),
        "NEGATIVE_PROXY_METHOD_NEGOTIATION_INVALID"))
    check("truncated-auth", lambda: expect_negative_error(
        lambda: evaluate_socks5_auth_attempt(b"\x05\x01\x02", b"\x01\x0cfixture-user", "attempt-negative-proxy-1"),
        "NEGATIVE_PROXY_AUTH_FRAME_INVALID"))
    if failures:
        raise AssertionError("NEGATIVE_PROXY_REGRESSION_RED: " + " | ".join(failures))


def assert_planned_artifacts_empty() -> None:
    catalog = json.loads((root / "src" / "server_agent" / "plugins" / "catalog.json").read_text(encoding="utf-8"))
    negative = next(item for item in catalog["plugins"] if item["id"] == "negative-proxy")
    assert negative["implementation_status"] == "PLANNED"
    assert negative["artifacts"] == []


def assert_not_verified_state() -> None:
    semantic = validate_negative_proxy_config(NEGATIVE_PROXY_CONFIG)
    assert semantic["auth_listener_state"] == "NOT_VERIFIED"
    assert semantic["unavailable_state"] == "NOT_VERIFIED"
    assert semantic["proof_required"] is True
    assert semantic["relay_count"] == 0


def assert_multi_method_rejected_auth() -> None:
    attempt = evaluate_socks5_auth_attempt(
        b"\x05\x02\x00\x02", auth_frame(b"fixture-password"), "attempt-negative-proxy-1")
    assert attempt["method_reply"] == b"\x05\x02"
    assert attempt["auth_reply"] == b"\x01\x01"
    assert attempt["auth_rejected"] is True
    assert attempt["relay_count"] == 0
    assert len(attempt["principal_digest"]) == 64
    assert "fixture-user" not in str(attempt)
    assert "fixture-password" not in str(attempt)


def assert_password_independent_digest() -> None:
    first = evaluate_socks5_auth_attempt(b"\x05\x01\x02", auth_frame(b"first-password"), "attempt-negative-proxy-1")
    second = evaluate_socks5_auth_attempt(b"\x05\x01\x02", auth_frame(b"second-password"), "attempt-negative-proxy-1")
    assert first["principal_digest"] == second["principal_digest"]


assert_negative_proxy_regressions()

expect_negative_error(lambda: validate_negative_proxy_config({**NEGATIVE_PROXY_CONFIG, "enabled": True}), "NEGATIVE_PROXY_RUNTIME_DISABLED")

print("PASS: offline failure-control contract")
