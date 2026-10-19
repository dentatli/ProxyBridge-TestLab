import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'src'))
from pb_target_accept_plan import validate_command_parser_proof, REMOVAL_PROFILE_SHA, REMOVAL_R2_PROFILE_SHA
from pb_kd_command_parser_check import fixture


class CommandParserProof(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)/'parser-check.json'
        cases = []
        for index, name in enumerate(['r1-readable', 'r2-readable', 'r2-unreadable']):
            old = index == 0
            cases.append(dict(name=name, passed=True,
                profile_sha256=REMOVAL_PROFILE_SHA if old else REMOVAL_R2_PROFILE_SHA,
                old_error_reproduced=old, action_end=not old, stack_begin=not old,
                stack_end=not old, exit_code=0))
            for suffix in ('.wdbg', '.stdout.txt', '.stderr.txt'):
                (self.path.parent/(name+suffix)).write_text('fixture')
        self.proof = dict(method='cdb-safe-removal-command-fixture-v1', passed=True,
            kernel_connection=False, product_started=False, traffic_generated=False, cases=cases)

    def tearDown(self):
        self.temp.cleanup()

    def validate(self):
        self.path.write_text(json.dumps(self.proof))
        return validate_command_parser_proof(self.path)

    def test_success_binds_all_native_parser_artifacts(self):
        self.assertEqual(len(self.validate()['files']), 10)

    def test_original_error_must_be_reproduced(self):
        self.proof['cases'][0]['old_error_reproduced'] = False
        with self.assertRaises(ValueError): self.validate()

    def test_both_fixed_branches_must_finish(self):
        self.proof['cases'][2]['action_end'] = False
        with self.assertRaises(ValueError): self.validate()

    def test_different_profile_cannot_reuse_proof(self):
        self.proof['cases'][1]['profile_sha256'] = '0'*64
        with self.assertRaises(ValueError): self.validate()

    def test_changed_stdout_changes_sealed_binding(self):
        before = self.validate()
        (self.path.parent/'r2-readable.stdout.txt').write_text('changed')
        self.assertNotEqual(validate_command_parser_proof(self.path), before)

    def test_fixture_retains_control_grammar_and_real_stack_command(self):
        root = Path(__file__).resolve().parents[1]
        profile = json.loads((root/'scripts/debugger/pb-kd-target-removal-disabled-candidate-20261019-r2.json').read_text())
        action = fixture(profile['points'][1]['action'], True)
        self.assertIn('}; .printf "PBRM STACK_BEGIN', action)
        self.assertIn('k 10;', action)
        self.assertNotIn('poi(', action)
        self.assertNotIn('$vvalid', action)
        self.assertTrue(action.endswith('.printf "PARSER_ACTION_END\\n";'))


if __name__ == '__main__':
    unittest.main()
