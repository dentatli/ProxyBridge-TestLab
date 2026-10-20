import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'))
from pb_selected_nbl_profile import policy,profile,PROFILE,PROFILE_SHA,SCRIPT,SCRIPT_SHA
from pb_selected_nbl_report import correlate,evaluate
from pb_target_flag_binding import policy as bound_policy,profile_sha

CONFIG='PBN CONFIG model=0 get=8000 retrieve_return=9000 accept_return=a000\n'
SOURCE=('PBSD TRACK ep=1000 record=2000 context=3000 size=20 refs=1 flags30=1101641\n'
    'PBSD ARMED address=1030 access=r4 accept=disabled\n'
    'PBSD SEND_GATE send=1 raw=2 thread=4000 ep=1000 record=2000 nbl=5000 flags_reg=1101641 family=2 ip=8000\n'
    'PBSD SEND_HEADER send=1 nbl=5000 header=6000 flags=2 h0=7b000000da84d9a4 h1=400025000000000 h2=0\n'
    'PBSD SEND_GATE send=2 raw=4 thread=4000 ep=1000 record=2000 nbl=7000 flags_reg=1301641 family=2 ip=8000\n'
    'PBSD SEND_HEADER send=2 nbl=7000 header=8000 flags=2 h0=7b000000da84d9a4 h1=400025000000000 h2=0\n')
SEND='PBN STATE stage=send nbl=7000 info_raw=0 info=0 root=0 key5=absent value=0 record_match=0 nodes=0\n'
ARM='PBN ARMED nbl=7000 address=70e0 limit=10\n'
RECEIVE='PBN RECEIVE nbl=7000 ep=9000 raw=1 key=5 consume=1\n'
STATE=SEND.replace('stage=send','stage=receive')
DONE='PBN DONE nbl=7000\n'
TEXT=CONFIG+SOURCE+SEND+ARM+RECEIVE+STATE+DONE


class SelectedNbl(unittest.TestCase):
    def test_profile_and_policy_are_exact_and_no_global_accept(self):
        self.assertEqual(hashlib.sha256((ROOT/PROFILE).read_bytes()).hexdigest(),PROFILE_SHA)
        self.assertEqual(json.loads((ROOT/PROFILE).read_text()),profile())
        self.assertEqual(hashlib.sha256((ROOT/SCRIPT).read_bytes()).hexdigest(),SCRIPT_SHA)
        self.assertEqual(policy(),bound_policy(True,True,True,False,'nbl'))
        self.assertEqual(profile_sha(True,True,False,'nbl'),PROFILE_SHA)
        self.assertEqual(policy()['max_total_raw_hits'],96)
        self.assertEqual(policy()['debugger_points'],[2,3])
        self.assertNotIn('be4;',profile()['points'][0]['action'])

    def test_absent_both_is_observation_without_attribution(self):
        r=correlate(TEXT)
        self.assertEqual(r['errors'],[])
        self.assertEqual(r['state_transition'],'absent->absent')
        self.assertFalse(r['root_cause_proven'])
        self.assertFalse(r['kernel_accept_status_observed'])

    def test_present_then_absent_preserves_record_identity(self):
        present=SEND.replace('info_raw=0 info=0 root=0 key5=absent value=0 record_match=0 nodes=0',
            'info_raw=a001 info=a000 root=b000 key5=present value=2000 record_match=1 nodes=1')
        self.assertEqual(correlate(TEXT.replace(SEND,present,1))['state_transition'],'present->absent')
        self.assertEqual(correlate(TEXT.replace(SEND,present.replace('value=2000','value=2100'),1))['status'],'INCOMPLETE')

    def test_no_receive_or_done_cannot_mean_absent(self):
        for part in (CONFIG,SEND,ARM,RECEIVE,STATE,DONE):
            with self.subTest(part=part):self.assertEqual(correlate(TEXT.replace(part,'',1))['status'],'INCOMPLETE')

    def test_model_identity_limits_and_errors_fail_closed(self):
        for old,new in [('model=0','model=1'),('address=70e0','address=71e0'),('raw=1 key=5','raw=11 key=5'),
            ('consume=1','consume=0'),('nodes=0','nodes=9'),('nbl=7000 ep=9000','nbl=7100 ep=9000')]:
            with self.subTest(new=new):self.assertEqual(correlate(TEXT.replace(old,new))['status'],'INCOMPLETE')
        for extra in ('PBN INCOMPLETE stage=receive reason=READ_LIMIT\n','Single step exception - code 80000004\n','Error: bad script\n'):
            self.assertEqual(correlate(TEXT+extra)['status'],'INCOMPLETE')

    def test_order_and_multiple_runs_rejected(self):
        for t in (TEXT+TEXT,TEXT+SOURCE,CONFIG+SOURCE+SEND+RECEIVE+ARM+STATE+DONE):
            self.assertEqual(correlate(t)['status'],'INCOMPLETE')

    def test_native_join_refuses_10061_missing_query_and_cleanup_failure(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);plan=p/'runtime-plan.json'
            plan.write_text(json.dumps(dict(policy=policy(),debugger_profile=str(ROOT/PROFILE))))
            sha=hashlib.sha256(plan.read_bytes()).hexdigest()
            (p/'diagnostic-run.json').write_text(json.dumps(dict(debugger_observer=True,flow_registration_acknowledged=True,plan_sha256=sha)))
            c=p/'console.txt';c.write_text(TEXT)
            control=dict(role='control',peer='127.0.0.1:42201',original_api_failure=True)
            for errors,matches,ok in [([], [control],True),([], [dict(control,original_api_failure=False)],False),([],[],False),(['CLEANUP_INCOMPLETE'],[control],False)]:
                with patch('pb_target_accept_report.evaluate',return_value=dict(status='test',errors=errors,matches=matches)):
                    self.assertEqual(evaluate(p,c)['status']=='SELECTED_NBL_CONTEXT_AND_NATIVE_FAILURE_OBSERVED',ok)


if __name__=='__main__':unittest.main()
