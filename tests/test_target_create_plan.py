import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
from pb_target_accept_plan import CREATE_PROFILE_SHA, RETRIEVE_PROFILE_SHA, POLICY, create_policy, retrieve_policy, validate_registration, validate_positive_probe


class TargetCreateBinding(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'review.json'
        self.profile = ROOT / 'scripts/debugger/pb-kd-target-create-disabled-candidate-20261019.json'
        self.boot = dict(method='kernel-general-12-and-prefetch-bootid-v1', cryptographic_boot_identity=False,
            identity=dict(computer='TESTVM', provider='Microsoft-Windows-Kernel-General', event_id=12,
                event_record_id=123, event_time_utc='2026-10-19T00:00:00+00:00',
                start_time_utc='2026-10-19T00:00:00+00:00', prefetch_boot_id=10))
        self.review = dict(method='target-create-registration-review-v1', profile_sha256=CREATE_PROFILE_SHA,
            registered_ids=[2], disabled_ids=[2], action_matches_profile=True, separate_g_shown=True,
            source='user-chat-paste', boot=self.boot)

    def tearDown(self):
        self.temp.cleanup()

    def validate(self, boot=None):
        self.path.write_text(json.dumps(self.review), encoding='utf-8')
        sha = hashlib.sha256(self.path.read_bytes()).hexdigest()
        return validate_registration(self.profile, self.path, sha, boot or self.boot)

    def test_disabled_registration_allowed_for_future_explicit_observer(self):
        self.assertEqual(self.validate()['active_point_ids'], [])
        self.assertEqual(create_policy()['debugger_points'], [2])
        self.assertEqual(POLICY['debugger_points'], [])

    def test_changed_boot_rejected(self):
        changed = copy.deepcopy(self.boot)
        changed['identity']['prefetch_boot_id'] += 1
        with self.assertRaisesRegex(ValueError, 'REGISTRATION_OR_BOOT_DIFFERS'):
            self.validate(changed)

    def test_unknown_action_rejected(self):
        self.review['action_matches_profile'] = False
        with self.assertRaises(ValueError):
            self.validate()

    def test_point_not_disabled_rejected(self):
        self.review['disabled_ids'] = []
        with self.assertRaises(ValueError):
            self.validate()

    def test_resume_not_shown_rejected(self):
        self.review['separate_g_shown'] = False
        with self.assertRaises(ValueError):
            self.validate()

    def test_additional_point_rejected(self):
        self.review['registered_ids'] = [2, 3]
        with self.assertRaises(ValueError):
            self.validate()

    def positive_fixture(self):
        capture = Path(self.temp.name) / 'capture'
        capture.mkdir()
        (capture / 'runtime-plan.json').write_text(json.dumps(dict(policy=create_policy(),
            preparation=self.temp.name, debugger_profile=str(self.profile))), encoding='utf-8')
        (Path(self.temp.name) / 'boot-session.json').write_text(json.dumps(self.boot), encoding='utf-8')
        console = Path(self.temp.name) / 'console.txt'
        console.write_text('fixture', encoding='utf-8')
        result = dict(status='CONTROL_CREATE_OBSERVED', errors=[], unique_control_creation_observed=True,
                      create_events=[{}], plan_sha256='a'*64, console_sha256='b'*64)
        return capture, console, result

    def test_target_requires_positive_four_and_keeps_single_point(self):
        capture, console, result = self.positive_fixture()
        with patch('pb_target_create_report.evaluate', return_value=result):
            proof = validate_positive_probe(capture, console, self.boot)
            self.assertEqual(validate_positive_probe(proof['capture'], proof['console'], self.boot), proof)
        self.assertEqual(proof['console_sha256'], 'b'*64)
        self.assertEqual(create_policy(True)['fillers'], 200)
        self.assertEqual(create_policy(True)['debugger_points'], [2])
        self.assertEqual(create_policy()['fillers'], 3)

    def test_retrieve_positive_requires_one_success_and_record_snapshot(self):
        capture, console, _ = self.positive_fixture()
        profile = ROOT/'scripts/debugger/pb-kd-target-retrieve-disabled-candidate-20261019.json'
        (capture/'runtime-plan.json').write_text(json.dumps(dict(policy=retrieve_policy(False), preparation=self.temp.name, debugger_profile=str(profile))))
        result = dict(status='RETRIEVE_SUCCESS_OBSERVED', errors=[], retrieve_events=[{}], record_snapshots=[{}], plan_sha256='a'*64, console_sha256='b'*64)
        with patch('pb_target_retrieve_report.evaluate', return_value=result):
            self.assertEqual(validate_positive_probe(capture, console, self.boot)['plan_sha256'], 'a'*64)
            result['record_snapshots'] = []
            with self.assertRaisesRegex(ValueError, 'POSITIVE_RETRIEVE_REQUIRED'):
                validate_positive_probe(capture, console, self.boot)

    def test_missing_create_is_not_positive_evidence(self):
        capture, console, result = self.positive_fixture()
        result.update(status='NO_CREATE_EVENT_OBSERVED_COVERAGE_UNPROVEN', create_events=[])
        with patch('pb_target_create_report.evaluate', return_value=result):
            with self.assertRaisesRegex(ValueError, 'POSITIVE_CREATE_REQUIRED'):
                validate_positive_probe(capture, console, self.boot)

    def test_positive_probe_different_boot_rejected(self):
        capture, console, result = self.positive_fixture()
        other = copy.deepcopy(self.boot)
        other['identity']['prefetch_boot_id'] += 1
        with self.assertRaisesRegex(ValueError, 'POSITIVE_PROBE_BOOT_DIFFERS'):
            validate_positive_probe(capture, console, other)

    def test_target_capture_cannot_substitute_for_four_positive_probe(self):
        capture, console, result = self.positive_fixture()
        p = capture / 'runtime-plan.json'
        data = json.loads(p.read_text()); data['policy'] = create_policy(True)
        p.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'POSITIVE_FOUR_POLICY_REQUIRED'):
            validate_positive_probe(capture, console, self.boot)

    def test_staged_contract_starts_disabled_and_preserves_watchdog(self):
        p = create_policy(True, True)
        self.assertEqual(p['initial_debugger_points'], [])
        self.assertEqual(p['debugger_points'], [2])
        self.assertEqual(p['core_watchdog_ms'], 30000)
        self.assertLess(p['host_deadline_ms'], p['control_deadline_ms'])
        self.assertLess(p['control_deadline_ms'], p['core_watchdog_ms'])
        with self.assertRaisesRegex(ValueError, 'STAGED_REQUIRES_201'):
            create_policy(False, True)

    def test_retrieve_registration_uses_own_pinned_profile(self):
        self.profile=ROOT/'scripts/debugger/pb-kd-target-retrieve-disabled-candidate-20261019.json'
        self.review.update(method='target-retrieve-registration-review-v1', profile_sha256=RETRIEVE_PROFILE_SHA)
        self.assertIn('retrieve',self.validate()['method'])
        self.assertEqual(retrieve_policy()['debugger_points'],[2])
        self.assertEqual(retrieve_policy()['initial_debugger_points'],[])

    def test_create_review_cannot_approve_retrieve_profile(self):
        self.profile=ROOT/'scripts/debugger/pb-kd-target-retrieve-disabled-candidate-20261019.json'
        with self.assertRaises(ValueError): self.validate()


if __name__ == '__main__':
    unittest.main()
