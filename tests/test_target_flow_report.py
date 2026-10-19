import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'src'))
from pb_target_accept_plan import flow_policy
from pb_target_flow_report import evaluate


class FlowReport(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)
        self.plan = self.path/'runtime-plan.json'
        self.plan.write_text(json.dumps(dict(policy=flow_policy())))
        self.run = dict(plan_sha256=hashlib.sha256(self.plan.read_bytes()).hexdigest(),
                        debugger_observer=True, flow_registration_acknowledged=True)
        self.console = self.path/'console.txt'
        self.console.write_text('PBTF TRACK thread=1 source=2 ep=3 record=4 context=5 size=20 refs=1\n')
        self.native = dict(status='TARGET_FAILURE_REPRODUCED', errors=[],
            matches=[dict(role='control', peer='127.0.0.1:42201')],
            target_trigger_observed=True, control_original_api_failure=True)

    def tearDown(self):
        self.temp.cleanup()

    def evaluate(self):
        (self.path/'diagnostic-run.json').write_text(json.dumps(self.run))
        with patch('pb_target_flow_report.native_evaluate', return_value=self.native):
            return evaluate(self.path, self.console)

    def test_native_failure_and_no_callbacks_is_not_kernel_absence_proof(self):
        r = self.evaluate()
        self.assertEqual(r['status'], 'CALLBACK_NOT_OBSERVED_COVERAGE_UNPROVEN')
        self.assertTrue(r['control_original_api_failure'])
        self.assertFalse(r['root_cause_proven'])

    def test_missing_native_evidence_invalidates_result(self):
        self.native['errors'] = ['COHORT_INCOMPLETE']
        self.assertEqual(self.evaluate()['status'], 'INCOMPLETE')

    def test_ack_required(self):
        self.run['flow_registration_acknowledged'] = False
        with self.assertRaisesRegex(ValueError, 'BINDING_INVALID'): self.evaluate()

    def test_changed_plan_rejected(self):
        self.plan.write_text(json.dumps(dict(policy=flow_policy()))+' ')
        with self.assertRaisesRegex(ValueError, 'BINDING_INVALID'): self.evaluate()


if __name__ == '__main__':
    unittest.main()
