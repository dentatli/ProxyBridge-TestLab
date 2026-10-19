import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'src'))
from pb_target_removal_report import correlate

TRACK = 'PBTF TRACK thread=1 source=2 ep=3 record=4 context=5 size=20 refs=1\n'
REMOVE = 'PBRM REMOVE thread=10 scope=20 nbl=30 record=4 refs=2 context=5 size=20\n'
BEGIN = 'PBRM STACK_BEGIN thread=10 scope=20 record=4\n'
END = 'PBRM STACK_END thread=10 scope=20 record=4\n'
STACK = ' # Child-SP RetAddr Call Site\n00 ffff8000`00000020 ffff8000`00000040 tcpip!TlShimNblEventNotifyFn\n01 ffff8000`00000030 ffff8000`00000050 fwpkclnt!Caller+0x10\n'


class RemovalReport(unittest.TestCase):
    def test_bounded_stack_and_refs(self):
        r = correlate(TRACK+REMOVE+BEGIN+STACK+END)
        self.assertEqual(r['errors'], [])
        self.assertEqual(r['precall_refs'], [2])
        self.assertEqual(len(r['removals'][0]['frames']), 2)
        self.assertFalse(r['root_cause_proven'])
    def test_two_removals_can_reuse_scope_sequentially(self):
        r = correlate(TRACK+REMOVE+BEGIN+STACK+END+REMOVE.replace('refs=2', 'refs=1')+BEGIN+STACK+END)
        self.assertEqual(r['precall_refs'], [2, 1])
        self.assertFalse(r['record_lifetime_complete'])
    def test_wrong_record_rejected(self):
        self.assertTrue(correlate(TRACK+REMOVE.replace('record=4', 'record=6')+BEGIN+STACK+END)['errors'])
    def test_wrong_stack_identity_rejected(self):
        self.assertTrue(correlate(TRACK+REMOVE+BEGIN+STACK+END.replace('thread=10', 'thread=11'))['errors'])
    def test_truncated_stack_rejected(self):
        self.assertIn('STACK_END_MISSING', correlate(TRACK+REMOVE+BEGIN+STACK)['errors'])
    def test_empty_stack_rejected(self):
        self.assertTrue(correlate(TRACK+REMOVE+BEGIN+END)['errors'])
    def test_unreadable_record_rejected(self):
        self.assertTrue(correlate(TRACK+'PBRM_UNREADABLE event=RECORD capture=incomplete\n')['errors'])
    def test_no_removal_is_not_absence_proof(self):
        self.assertEqual(correlate(TRACK)['status'], 'REMOVAL_NOT_OBSERVED_COVERAGE_UNPROVEN')
    def test_old_callback_logger_rejected(self):
        self.assertIn('WRONG_CALLBACK_LOGGER', correlate(TRACK+'PBTF ENTER ignored\n')['errors'])
    def test_extra_character_error_keeps_partial_refs_without_success_verdict(self):
        r = correlate(TRACK+REMOVE.replace('refs=2', 'refs=3')+'^ Extra character error in command\n'+REMOVE+'^ Extra character error in command\n')
        self.assertEqual(r['status'], 'INCOMPLETE')
        self.assertIn('DEBUGGER_ERROR', r['errors'])
        self.assertEqual(r['observed_precall_refs'], [3, 2])
        self.assertEqual(r['removals'], [])


if __name__ == '__main__':
    unittest.main()
