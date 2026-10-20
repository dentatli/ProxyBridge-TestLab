import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from test_selected_nbl64_report import TEXT
from pb_selected_nbl64_report import correlate
from pb_selected_nbl512_profile import profile,policy,PROFILE,PROFILE_SHA,SCRIPT,SCRIPT_SHA
from pb_selected_nbl_profile import profile as old_profile
from pb_target_flag_binding import policy as bound_policy,profile_sha

TEXT512=TEXT.replace('read_limit=40','read_limit=200').replace('version=2','version=3').replace('limit=40','limit=200').replace('retrieve_return=0 accept_return=0','retrieve_return=9000 accept_return=a000')


class Nbl512(unittest.TestCase):
    def test_profile_preserves_actions_and_strict_bindings(self):
        self.assertEqual(profile()['points'],old_profile()['points'])
        self.assertEqual(hashlib.sha256((ROOT/PROFILE).read_bytes()).hexdigest(),PROFILE_SHA)
        self.assertEqual(json.loads((ROOT/PROFILE).read_text()),profile())
        self.assertEqual(hashlib.sha256((ROOT/SCRIPT).read_bytes()).hexdigest(),SCRIPT_SHA)
        self.assertEqual(policy(),bound_policy(True,True,True,False,'nbl512'))
        self.assertEqual(profile_sha(True,True,False,'nbl512'),PROFILE_SHA)
        self.assertEqual(policy()['max_total_raw_hits'],592)

    def test_valid_counts_and_caller_before_key(self):
        self.assertEqual(correlate(TEXT512,512,3)['errors'],[])
        self.assertIn('NBL_CALLER_BEFORE_KEY_INVALID',correlate(TEXT512.replace('key=4 consume=1 retrieve_return=9000 accept_return=a000','key=4 consume=1 retrieve_return=0 accept_return=0'),512,3)['errors'])

    def test_512_boundary_and_limit_above_boundary(self):
        t=TEXT512.replace('raw=2 key=5','raw=200 key=5').replace('SUMMARY total=2','SUMMARY total=200').replace(' key=1 consume=0',' key=1ff consume=0')
        self.assertEqual(correlate(t,512,3)['errors'],[])
        self.assertEqual(correlate(t.replace('raw=200 key=5','raw=201 key=5'),512,3)['status'],'INCOMPLETE')


if __name__=='__main__':unittest.main()
