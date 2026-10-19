import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_target_retrieve_report import correlate


def event(hit, status=0, record=0x1000):
    return (f'PBTA RETRIEVE hit={hit:x} ep=2000 nbl=3000 local_raw=da84 peer_raw=d9a4 '
            f'status={status:x} record={record:x}\n')


class RetrieveDecision(unittest.TestCase):
    def setUp(self):
        self.native = dict(errors=[], status='TARGET_FAILURE_REPRODUCED', target_trigger_observed=True,
            control_original_api_failure=True, matches=[dict(role='control',peer='127.0.0.1:42201')])

    def test_positive_success_then_missing_sequence(self):
        r=correlate(event(1)+event(2,0xc0000225,0),self.native)
        self.assertEqual(r['status'],'RETRIEVE_SUCCESS_THEN_NOT_FOUND_OBSERVED')
        self.assertFalse(r['root_cause_proven'])
        self.assertFalse(r['trap_coverage_verified'])

    def test_missing_first_snapshot_is_not_initial_loss_proof(self):
        r=correlate(event(2,0xc0000225,0),self.native)
        self.assertEqual(r['status'],'RETRIEVE_NOT_FOUND_OBSERVED')
        self.assertFalse(r['private_lifetime_complete'])

    def test_success_only_does_not_exonerate_missing_events(self):
        r=correlate(event(1),self.native)
        self.assertEqual(r['status'],'SUCCESS_SNAPSHOTS_OBSERVED_API_FAILED')
        self.assertFalse(r['trap_coverage_verified'])

    def test_no_event_is_never_absence_proof(self):
        self.assertEqual(correlate('',self.native)['status'],'NO_RETRIEVE_EVENT_COVERAGE_UNPROVEN')

    def test_wrong_control_port_rejected(self):
        self.assertTrue(correlate(event(1).replace('d9a4','d9a5'),self.native)['errors'])

    def test_valid_record_snapshot_attaches_by_hit(self):
        r=correlate(event(1)+'PBTA RECORD hit=1 record=1000 context=4000 size=20 refs=1\n',self.native)
        self.assertEqual(r['errors'],[])

    def test_mismatched_record_snapshot_rejected(self):
        r=correlate(event(1)+'PBTA RECORD hit=1 record=1001 context=4000 size=20 refs=1\n',self.native)
        self.assertIn('RECORD_METADATA_INCONSISTENT',r['errors'])

    def test_duplicate_hit_rejected(self):
        self.assertIn('HIT_SEQUENCE_INVALID',correlate(event(1)+event(1),self.native)['errors'])

    def test_debugger_error_rejected(self):
        self.assertIn('DEBUGGER_METADATA_INCOMPLETE',correlate('PBTA_UNREADABLE event=RECORD\n',self.native)['errors'])

    def test_native_errors_block_conclusions(self):
        n=copy.deepcopy(self.native);n['errors']=['COHORT_INCOMPLETE']
        self.assertEqual(correlate(event(1),n)['status'],'INCOMPLETE')


if __name__=='__main__': unittest.main()
