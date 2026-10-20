import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from test_selected_nbl_report import CONFIG,SOURCE,SEND,ARM,RECEIVE,STATE,DONE
from pb_selected_nbl64_report import correlate
from pb_selected_nbl64_profile import profile,policy,PROFILE,PROFILE_SHA,SCRIPT,SCRIPT_SHA
from pb_selected_nbl_profile import profile as old_profile
from pb_target_flag_binding import policy as bound_policy,profile_sha

POLICY='PBN POLICY read_limit=40 sample_limit=4 version=2\n'
SAMPLE='PBN REJECT sample=1 read=1 reason=KEY ip=8000 nbl_reg=7000 key=4 consume=1 retrieve_return=0 accept_return=0\n'
SUMMARY='PBN SUMMARY total=2 ip=0 object=0 key=1 consume=0 retrieve=0 accept=0 samples=1\n'
TEXT=CONFIG+POLICY+SOURCE+SEND+ARM.replace('limit=10','limit=40')+SAMPLE+RECEIVE.replace('raw=1','raw=2')+STATE+SUMMARY+DONE


class Nbl64(unittest.TestCase):
    def test_new_profile_preserves_registered_actions(self):
        self.assertEqual(profile()['points'],old_profile()['points'])
        self.assertEqual(hashlib.sha256((ROOT/PROFILE).read_bytes()).hexdigest(),PROFILE_SHA)
        self.assertEqual(json.loads((ROOT/PROFILE).read_text()),profile())
        self.assertEqual(hashlib.sha256((ROOT/SCRIPT).read_bytes()).hexdigest(),SCRIPT_SHA)
        self.assertEqual(policy(),bound_policy(True,True,True,False,'nbl64'))
        self.assertEqual(profile_sha(True,True,False,'nbl64'),PROFILE_SHA)
        self.assertEqual(policy()['max_total_raw_hits'],144)

    def test_success_joins_diagnostics(self):
        r=correlate(TEXT);self.assertEqual(r['errors'],[])
        self.assertEqual(r['reject_samples'][0]['reason'],'KEY')
        self.assertFalse(r['root_cause_proven'])

    def test_last_access_64_allowed_but_65_rejected(self):
        t=TEXT.replace('raw=2 key=5','raw=40 key=5').replace('SUMMARY total=2','SUMMARY total=40').replace(' key=1 consume=0',' key=3f consume=0')
        self.assertEqual(correlate(t)['errors'],[])
        self.assertEqual(correlate(t.replace('raw=40 key=5','raw=41 key=5'))['status'],'INCOMPLETE')

    def test_policy_counts_sample_limit_and_missing_receive_fail_closed(self):
        changes=[('read_limit=40','read_limit=80'),('samples=1','samples=0'),('reason=KEY','reason=UNKNOWN'),
            ('SUMMARY total=2','SUMMARY total=3'),(SUMMARY,''),(POLICY,''),(RECEIVE.replace('raw=1','raw=2'),''),
            (SAMPLE,SAMPLE*5)]
        for old,new in changes:
            with self.subTest(new=new):self.assertEqual(correlate(TEXT.replace(old,new))['status'],'INCOMPLETE')

    def test_cap_result_stays_incomplete(self):
        text=CONFIG+POLICY+SOURCE+SEND+ARM.replace('limit=10','limit=40')+SAMPLE+SUMMARY+'PBN INCOMPLETE stage=receive reason=READ_LIMIT\n'
        self.assertEqual(correlate(text)['status'],'INCOMPLETE')


if __name__=='__main__':unittest.main()
