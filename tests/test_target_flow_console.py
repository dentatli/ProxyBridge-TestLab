import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_target_flow_console import correlate

TRACK = 'PBTF TRACK thread=1 source=2 ep=3 record=4 context=5 size=20 refs=1\n'
ENTER = 'PBTF ENTER thread=10 scope=20 event=1 nbl=30 new_nbl=40 layer=10 record=4 tag=5\n'
EXIT = 'PBTF EXIT thread=10 scope=20 record=4 tag=5 status=0\n'


class FlowConsole(unittest.TestCase):
    def test_success_is_snapshot_only(self):
        r = correlate(TRACK+ENTER+EXIT)
        self.assertEqual(r['status'], 'CALLBACK_SUCCESS_SNAPSHOTS_OBSERVED')
        self.assertFalse(r['trap_coverage_verified'])
    def test_failure_observed(self):
        self.assertEqual(correlate(TRACK+ENTER+EXIT.replace('status=0', 'status=c0000225'))['status'], 'CALLBACK_FAILURE_OBSERVED')
    def test_cross_thread_not_paired(self):
        self.assertTrue(correlate(TRACK+ENTER+EXIT.replace('thread=10', 'thread=11'))['errors'])
    def test_sequential_stack_reuse_is_allowed(self):
        self.assertEqual(len(correlate(TRACK+ENTER+EXIT+ENTER+EXIT)['callbacks']), 2)
    def test_missing_exit_rejected(self):
        self.assertIn('CALLBACK_EXIT_MISSING', correlate(TRACK+ENTER)['errors'])
    def test_repeated_tracker_rejected(self):
        self.assertTrue(correlate(TRACK+TRACK)['errors'])
    def test_wrong_record_rejected(self):
        self.assertTrue(correlate(TRACK+ENTER.replace('record=4', 'record=6')+EXIT)['errors'])
    def test_absence_never_proves_no_callback(self):
        self.assertEqual(correlate(TRACK)['status'], 'CALLBACK_NOT_OBSERVED_COVERAGE_UNPROVEN')
    def test_removed_event_is_not_free_proof(self):
        r = correlate(TRACK+ENTER.replace('event=1', 'event=5').replace('new_nbl=40', 'new_nbl=0')+EXIT)
        self.assertEqual(r['errors'], [])
        self.assertFalse(r['record_lifetime_complete'])


if __name__ == '__main__':
    unittest.main()
