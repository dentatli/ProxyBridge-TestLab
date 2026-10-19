import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_target_create_report import correlate

SHA = 'a' * 64
LINE = ('PBTR CREATE thread=ffff000000001000 source=ffff000000002000 local_raw=d9a40002 '
        'ep=ffff000000003000 assigned=ffff000000004000 record=ffff000000004000 '
        'context=ffff000000005000 size=20 refs=1')


class TargetCreateReport(unittest.TestCase):
    def setUp(self):
        self.native = dict(status='TARGET_FAILURE_REPRODUCED', errors=[],
            target_trigger_observed=True, control_original_api_failure=True,
            matches=[dict(role='control', peer='127.0.0.1:42201', native_pid=123,
                          query=dict(seq=201, api_error=10022))])

    def console(self, body):
        return 'PBTR_RUN_BEGIN plan=' + SHA + '\n' + body + '\nPBTR_RUN_END plan=' + SHA

    def test_one_positive_and_unbound_local_address(self):
        r = correlate(self.console(LINE), SHA, self.native)
        self.assertEqual(r['status'], 'CONTROL_CREATE_OBSERVED')
        self.assertTrue(r['unique_control_creation_observed'])
        self.assertFalse(r['trap_coverage_verified'])

    def test_old_probe_and_quoted_commands_outside_scope_are_ignored(self):
        r = correlate('PBTR CREATE invalid old probe\n0: kd> .printf "PBTR CREATE fake"\n' +
                      self.console('0: kd> bp2 "PBTR CREATE fake"\n' + LINE), SHA, self.native)
        self.assertEqual(r['status'], 'CONTROL_CREATE_OBSERVED')

    def test_no_event_does_not_prove_no_creation(self):
        r = correlate(self.console(''), SHA, self.native)
        self.assertEqual(r['status'], 'NO_CREATE_EVENT_OBSERVED_COVERAGE_UNPROVEN')
        self.assertFalse(r['unique_control_creation_observed'])

    def test_duplicate_scope_rejected(self):
        self.assertIn('EXACT_CAPTURE_SCOPE_REQUIRED', correlate(self.console(LINE)+'\n'+self.console(LINE), SHA, self.native)['errors'])

    def test_glued_capture_markers_rejected(self):
        self.assertIn('EXACT_CAPTURE_SCOPE_REQUIRED', correlate(self.console(LINE)*2, SHA, self.native)['errors'])

    def test_wrong_plan_marker_rejected(self):
        self.assertIn('EXACT_CAPTURE_SCOPE_REQUIRED', correlate(self.console(LINE), 'b'*64, self.native)['errors'])

    def test_wrong_source_port_rejected(self):
        r = correlate(self.console(LINE.replace('d9a40002', 'daa40002')), SHA, self.native)
        self.assertTrue(r['errors'])

    def test_assignment_mismatch_rejected(self):
        r = correlate(self.console(LINE.replace('assigned=ffff000000004000', 'assigned=ffff000000009000')), SHA, self.native)
        self.assertTrue(r['errors'])

    def test_unreadable_guard_invalidates_capture(self):
        r = correlate(self.console(LINE+'\nPBTR_UNREADABLE event=CREATE_SELECTOR capture=incomplete'), SHA, self.native)
        self.assertIn('DEBUGGER_METADATA_INCOMPLETE', r['errors'])

    def test_debugger_single_step_exception_not_silently_ignored(self):
        r = correlate(self.console(LINE+'\nSingle step exception - code 80000004'), SHA, self.native)
        self.assertIn('DEBUGGER_ERROR_INSIDE_SCOPE', r['errors'])

    def test_truncated_line_rejected(self):
        self.assertTrue(correlate(self.console(LINE.replace(' refs=1', '')), SHA, self.native)['errors'])

    def test_multiple_creates_not_falsely_reduced_to_one(self):
        r = correlate(self.console(LINE+'\n'+LINE), SHA, self.native)
        self.assertEqual(r['status'], 'MULTIPLE_CONTROL_CREATES_REVIEW_PENDING')
        self.assertEqual(len(r['create_events']), 2)

    def test_ambiguous_native_control_rejected(self):
        self.native['matches'] *= 2
        self.assertIn('NATIVE_CONTROL_MATCH_NOT_UNIQUE', correlate(self.console(LINE), SHA, self.native)['errors'])

    def test_native_failure_retained(self):
        self.native['errors'] = ['COHORT_INCOMPLETE']
        self.assertIn('NATIVE_CAPTURE_INCOMPLETE', correlate(self.console(LINE), SHA, self.native)['errors'])


if __name__ == '__main__':
    unittest.main()
