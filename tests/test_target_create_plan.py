import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
from pb_target_accept_plan import CREATE_PROFILE_SHA, POLICY, create_policy, validate_registration


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


if __name__ == '__main__':
    unittest.main()
