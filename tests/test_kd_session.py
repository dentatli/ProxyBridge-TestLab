"""File fixtures only: no debugger, product processes, sockets, or service changes."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_kd_session import boot_identity, checked, check_files, digest, policy, save, snapshot, validate_assets, validate_review


class DiagnosticSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.profile = dict(method='test-profile', active_point_ids=[2, 3], registered_point_ids=[2, 3],
                            inactive_point_ids=[], point_count_active=2, points=[dict(id=2), dict(id=3)],
                            automatic_debugger_control=False, load_authorized=False, root_cause_proven=False)
        self.boot = dict(method='kernel-general-12-and-prefetch-bootid-v1', cryptographic_boot_identity=False,
                         identity=dict(computer='fixture', provider='Microsoft-Windows-Kernel-General',
                                       event_id=12, event_record_id=7, event_time_utc='fixture-event',
                                       start_time_utc='fixture-start', prefetch_boot_id=9))
        self.evidence = self.root / 'console.txt'
        self.evidence.write_text('fixture')
        self.review = dict(schema_version=1, registration_reviewed=True, profile_sha256='a' * 64,
                           boot_identity=boot_identity(self.boot), allowed_workloads=['four'],
                           evidence_files=[dict(path=str(self.evidence), sha256=digest(self.evidence))],
                           root_cause_proven=False, automatic_debugger_control=False)

    def test_two_shapes_and_no_640(self):
        self.assertEqual(policy('four', self.profile)['phase_connections'], [4])
        self.assertEqual(policy('bounded256', self.profile)['total_connections'], 328)
        with self.assertRaises(ValueError):
            policy('640', self.profile)

    def test_changed_profile_or_boot_rejected(self):
        validate_review(self.review, self.profile, 'a' * 64, self.boot, 'four')
        with self.assertRaisesRegex(ValueError, 'NOT_APPROVED'):
            validate_review(self.review, self.profile, 'b' * 64, self.boot, 'four')
        reboot = copy.deepcopy(self.boot)
        reboot['identity']['prefetch_boot_id'] += 1
        with self.assertRaisesRegex(ValueError, 'NOT_APPROVED'):
            validate_review(self.review, self.profile, 'a' * 64, reboot, 'four')

    def test_bounded_needs_review_and_prior_four(self):
        with self.assertRaisesRegex(ValueError, 'NOT_APPROVED'):
            validate_review(self.review, self.profile, 'a' * 64, self.boot, 'bounded256')
        self.review['allowed_workloads'].append('bounded256')
        self.review['prior_four_review'] = dict(native_probe_complete=False)
        with self.assertRaisesRegex(ValueError, 'PRIOR_FOUR_REQUIRED'):
            validate_review(self.review, self.profile, 'a' * 64, self.boot, 'bounded256')
        self.review['prior_four_review'] = dict(native_probe_complete=True, profile_sha256='a' * 64,
            boot_identity=boot_identity(self.boot), path=str(self.evidence), sha256=digest(self.evidence))
        validate_review(self.review, self.profile, 'a' * 64, self.boot, 'bounded256')

    def test_debugger_ids_must_partition_registered(self):
        self.profile['inactive_point_ids'] = [2]
        with self.assertRaisesRegex(ValueError, 'PROFILE_INVALID'):
            policy('four', self.profile)

    def test_resident_mode_is_explicit_and_initially_four_only(self):
        self.assertNotIn('driver_lifecycle', policy('four', self.profile))
        self.profile['driver_lifecycle'] = 'resident-disabled'
        self.assertEqual(policy('four', self.profile)['driver_lifecycle'], 'resident-disabled')
        with self.assertRaisesRegex(ValueError, 'RESIDENT_FOUR_ONLY'):
            policy('bounded256', self.profile)
        self.profile['driver_lifecycle'] = 'anything'
        with self.assertRaisesRegex(ValueError, 'LIFECYCLE_INVALID'):
            policy('four', self.profile)

    def test_file_tamper_and_duplicate_rejected(self):
        entry = dict(path=str(self.evidence), sha256=digest(self.evidence))
        with self.assertRaisesRegex(ValueError, 'DUPLICATE'):
            check_files([entry, entry])
        self.evidence.write_text('changed')
        with self.assertRaisesRegex(ValueError, 'SHA_CHANGED'):
            checked(self.evidence, entry['sha256'])

    def test_plan_is_create_only(self):
        p = self.root / 'plan.json'
        save(p, dict(value=1))
        with self.assertRaises(FileExistsError):
            save(p, dict(value=2))
        self.assertEqual(json.loads(p.read_text()), dict(value=1))

    def test_reviewed_json_bytes_are_preserved(self):
        source = self.root / 'profile.json'
        source.write_bytes(b'\xef\xbb\xbf{ "arbitrary_spacing":true }\r\n')
        target = self.root / 'snapshot.json'
        snapshot(source, target)
        self.assertEqual(digest(source), digest(target))
        with self.assertRaises(FileExistsError):
            snapshot(source, target)

    def test_shared_runtime_rejects_added_file_before_product(self):
        runtime = self.root / 'runtime/python'
        runtime.mkdir(parents=True)
        (runtime / 'python.exe').write_bytes(b'fixture-only')
        manifest = runtime.parent / 'manifest.json'
        save(manifest, dict(isolated_pth=True, import_site=False, source_runtime_reused_at_run=False,
                            copied_files=1, files={'python.exe': digest(runtime / 'python.exe')}))
        assets = self.root / 'assets.json'
        save(assets, dict(method='kd-shared-assets-v1', root=str(self.root), python=str(runtime / 'python.exe'),
                         runtime_manifest=dict(path=str(manifest), sha256=digest(manifest))))
        (runtime / 'unexpected.pth').write_text('fixture')
        with self.assertRaisesRegex(ValueError, 'INVENTORY_CHANGED'):
            validate_assets(assets, digest(assets), self.root)


if __name__ == '__main__':
    unittest.main()
