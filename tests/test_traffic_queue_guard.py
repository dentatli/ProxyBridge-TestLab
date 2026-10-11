"""Recovery policy regressions; no product, service or network is started."""
import copy
import unittest
from unittest.mock import patch

from trafficlab.queue_guard import recover


class RecoveryPolicyTests(unittest.TestCase):
    def setUp(self):
        self.binding = {"id": "queue", "remote_bundle_sha256": "a" * 64, "local_runtime_sha256": "b" * 64}
        self.report = {"case_id": "app-http", "complete": False, "cancelled": False,
            "cleanup_verified": True, "off_after_attempt": {"off_verified": True},
            "errors": ["TRAFFIC_TRANSPORT_INCOMPLETE", "TRAFFIC_ROUTE_UNVERIFIED"],
            "conditions": {"remote_bundle_sha256": "a" * 64, "local_runtime_sha256": "b" * 64,
                           "application_tls_sha256": "c" * 64},
            "controls": [{"mode": mode, "complete": True, "route_verified": True} for mode in ("OFF", "UNRULED")],
            "measurements": [{"mode": "SOCKS5", "complete": False, "lifecycle": {
                "ready": True, "cleanup_verified": True, "capture_complete": True, "forced_stop": False}}]}
        self.origin = {"identity": {"verified": True}, "runtime_connections": 0, "proxy_connections": 0}

    def check(self, report=None, origin=None, off=None):
        with patch("trafficlab.queue_guard.cancelled", return_value=False), \
             patch("trafficlab.queue_guard.idle", return_value=off or {"off_verified": True}), \
             patch("trafficlab.queue_guard.origin_metrics", return_value=self.origin if origin is None else origin), \
             patch("trafficlab.queue_guard.time.monotonic", side_effect=[0, 3]):
            return recover("unused-private-binding.json", self.binding, self.report if report is None else report)

    def test_failed_case_is_preserved_when_recovery_allows_next(self):
        original = copy.deepcopy(self.report)
        evidence = self.check()
        self.assertTrue(evidence["safe_to_continue"])
        self.assertTrue(evidence["fresh_off_verified"])
        self.assertTrue(evidence["origin_idle_verified"])
        self.assertEqual(self.report, original)

    def test_unsafe_case_outcomes_never_reach_recovery_actions(self):
        for change in ("cleanup", "forced", "capture", "identity", "controls", "cancelled", "missing_measurement"):
            with self.subTest(change=change):
                report = copy.deepcopy(self.report)
                if change == "cleanup": report["cleanup_verified"] = False
                if change == "forced": report["measurements"][0]["lifecycle"]["forced_stop"] = True
                if change == "capture": report["measurements"][0]["lifecycle"]["capture_complete"] = False
                if change == "identity": report["errors"].append("TRAFFIC_IMMUTABLE_FILE_CHANGED")
                if change == "controls": report["controls"][0]["complete"] = False
                if change == "cancelled": report["cancelled"] = True
                if change == "missing_measurement": report["measurements"] = []
                with patch("trafficlab.queue_guard.idle") as off, patch("trafficlab.queue_guard.origin_metrics") as remote:
                    self.assertFalse(recover("unused", self.binding, report)["safe_to_continue"])
                    off.assert_not_called(); remote.assert_not_called()

    def test_report_from_another_runtime_is_rejected(self):
        report = copy.deepcopy(self.report)
        report["conditions"]["remote_bundle_sha256"] = "d" * 64
        self.assertFalse(self.check(report=report)["safe_to_continue"])

    def test_unverified_driver_off_blocks_network_and_continuation(self):
        with patch("trafficlab.queue_guard.cancelled", return_value=False), \
             patch("trafficlab.queue_guard.idle", side_effect=ValueError("OFF failed")), \
             patch("trafficlab.queue_guard.origin_metrics") as remote:
            evidence = recover("unused", self.binding, self.report)
            self.assertFalse(evidence["safe_to_continue"])
            self.assertFalse(evidence["fresh_off_verified"])
            remote.assert_not_called()

    def test_receiver_disconnect_or_identity_change_blocks_continuation(self):
        for error in (ConnectionError(), ValueError("TRAFFIC_REMOTE_ARTIFACT_IDENTITY_CHANGED"), ValueError("APPLICATION_TLS_IDENTITY_CHANGED")):
            with self.subTest(error=type(error).__name__), \
                 patch("trafficlab.queue_guard.cancelled", return_value=False), \
                 patch("trafficlab.queue_guard.idle", return_value={"off_verified": True}), \
                 patch("trafficlab.queue_guard.origin_metrics", side_effect=error):
                evidence = recover("unused", self.binding, self.report)
                self.assertFalse(evidence["safe_to_continue"])
                self.assertTrue(evidence["fresh_off_verified"])

    def test_remaining_origin_or_proxy_connections_block_continuation(self):
        for field in ("runtime_connections", "proxy_connections"):
            with self.subTest(field=field):
                self.assertFalse(self.check(origin={**self.origin, field: 1})["safe_to_continue"])

    def test_missing_idle_witness_is_not_zero(self):
        self.assertFalse(self.check(origin={"identity": {"verified": True}})["safe_to_continue"])
        self.assertFalse(self.check(origin={**self.origin, "runtime_connections": False})["safe_to_continue"])
        for field in ('runtime_connections','proxy_connections'):
            self.assertFalse(self.check(origin={**self.origin,field:None})['safe_to_continue'])

    def test_missing_runtime_binding_is_rejected(self):
        self.binding.pop("local_runtime_sha256")
        self.report["conditions"].pop("local_runtime_sha256")
        self.assertFalse(self.check()["safe_to_continue"])

    def test_cancel_during_recovery_prevents_network_and_continuation(self):
        with patch("trafficlab.queue_guard.cancelled", side_effect=[False, True]), \
             patch("trafficlab.queue_guard.idle", return_value={"off_verified": True}), \
             patch("trafficlab.queue_guard.origin_metrics") as remote:
            evidence = recover("unused", self.binding, self.report)
            self.assertFalse(evidence["safe_to_continue"])
            self.assertEqual(evidence["reason"], "TRAFFIC_RECOVERY_CANCELLED")
            remote.assert_not_called()


if __name__ == "__main__":
    unittest.main()
