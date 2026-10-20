import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'))
from pb_target_flag_binding import policy,registration,PROFILE_SHA,parser_proof,ARMED_PROFILE_SHA
from pb_target_flag_report import correlate,evaluate
from pb_target_accept_plan import validate_positive_probe,prepare

TRACK='PBFG TRACK ep=10 record=20 context=30 size=20 refs=1\n'
ACCEPT='PBFG RETRIEVE ep=40 nbl=50 status=0 output_raw=20\n'
SETTER='PBFG SET_PRE thread=1 ep=10 flags30=1101641 flags34=2080 record=20 classify_raw=2 arg12_raw=0 arg13_raw=0 arg15_raw=2\n'
STACK='PBFG STACK_BEGIN\n00 ffff000000001000 ffff000000002000 tcpip!WfpTlShimInspectRecvTcpDatagram\nPBFG STACK_END\n'


class FlagBindings(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)
        self.profile=ROOT/'scripts/debugger/pb-kd-target-flag-disabled-profile-20261020.json'
        self.boot=dict(method='kernel-general-12-and-prefetch-bootid-v1',cryptographic_boot_identity=False,
            identity=dict(computer='VM',provider='Microsoft-Windows-Kernel-General',event_id=12,event_record_id=1,
                event_time_utc='2026-10-20T00:00:00Z',start_time_utc='2026-10-20T00:00:00Z',prefetch_boot_id=117))

    def tearDown(self):self.temp.cleanup()

    def test_probe_has_two_points_and_no_stack(self):
        p=policy(False);self.assertEqual(p['debugger_points'],[2,4]);self.assertEqual(p['inactive_debugger_points'],[3])
        self.assertEqual(p['stack_count_max'],0);self.assertEqual(policy()['raw_hit_limit_per_point'],16)

    def test_receipt_does_not_claim_automatic_host_observation(self):
        r=dict(method='target-flow-prepared-commands-v1',source='prepared-command-awaiting-user-attestation',profile_sha256=PROFILE_SHA,
            expected_disabled_ids=[2,3,4],host_registration_observed=False,boot=self.boot)
        p=self.path/'receipt.json'
        def check():
            p.write_text(json.dumps(r));return registration(self.profile,p,hashlib.sha256(p.read_bytes()).hexdigest(),self.boot)
        self.assertEqual(check()['proposed_active_point_ids'],[2,3,4])
        r['host_registration_observed']=True
        with self.assertRaisesRegex(ValueError,'REGISTRATION'):check()

    def test_probe_evaluation_rejects_missing_record_or_limit(self):
        plan=self.path/'runtime-plan.json';plan.write_text(json.dumps(dict(policy=policy(False))))
        sha=hashlib.sha256(plan.read_bytes()).hexdigest()
        (self.path/'diagnostic-run.json').write_text(json.dumps(dict(debugger_observer=True,flow_registration_acknowledged=True,plan_sha256=sha)))
        console=self.path/'console.txt'
        native=dict(status='NATIVE_SUCCESS',errors=[],matches=[dict(role='control',peer='127.0.0.1:42201',original_api_failure=False)])
        with patch('pb_target_accept_report.evaluate',return_value=native):
            console.write_text(TRACK+ACCEPT)
            self.assertEqual(evaluate(self.path,console)['status'],'FLAG_PROBE_SUCCESS_OBSERVED')
            console.write_text(TRACK+ACCEPT.replace('output_raw=20','output_raw=0'))
            self.assertTrue(evaluate(self.path,console)['errors'])
            console.write_text(TRACK+ACCEPT+'PBFG_LIMIT point=2 capture=incomplete\n')
            self.assertTrue(evaluate(self.path,console)['errors'])

    def test_same_boot_positive_gate_rejects_yesterday(self):
        (self.path/'boot-session.json').write_text(json.dumps(self.boot))
        (self.path/'runtime-plan.json').write_text(json.dumps(dict(policy=policy(False),preparation=str(self.path),debugger_profile=str(self.profile))))
        console=self.path/'console.txt';console.write_text(TRACK+ACCEPT)
        result=dict(status='FLAG_PROBE_SUCCESS_OBSERVED',errors=[],plan_sha256='a'*64,console_sha256='b'*64)
        with patch('pb_target_flag_report.evaluate',return_value=result):
            self.assertEqual(validate_positive_probe(self.path,console,self.boot)['plan_sha256'],'a'*64)
            other=copy.deepcopy(self.boot);other['identity']['prefetch_boot_id']+=1
            with self.assertRaisesRegex(ValueError,'BOOT_DIFFERS'):validate_positive_probe(self.path,console,other)

    def test_set_pre_stack_does_not_claim_a_write(self):
        r=correlate(TRACK+SETTER+STACK+ACCEPT)
        self.assertEqual(r['status'],'BOUNDED_FLAG_SNAPSHOTS_OBSERVED')
        self.assertFalse(r['post_write_observed']);self.assertFalse(r['root_cause_proven'])
        self.assertTrue(r['events'][1]['bit20_before']);self.assertFalse(r['events'][1]['bit21_before'])

    def test_missing_stack_and_repeated_one_shot_are_incomplete(self):
        self.assertTrue(correlate(TRACK+SETTER+'PBFG STACK_BEGIN\n')['errors'])
        self.assertTrue(correlate(TRACK+TRACK)['errors'])

    def test_proof_requires_disable_checks_and_exact_actions(self):
        p=self.path/'parser-check.json'
        r=dict(method='cdb-safe-bounded-flag-candidate-v1',kernel_connection=False,product_started=False,traffic_generated=False,passed=True,
            cases=[dict(name=n,passed=True,checks=[True]*3,disable_checks=[True]*3,exit_code=0) for n in ('selected','nonselected','unreadable','limit')])
        (self.path/'candidate.json').write_bytes((ROOT/'scripts/debugger/pb-kd-target-flag-disabled-candidate-20261019.json').read_bytes())
        for c in r['cases']:
            for s in ('.wdbg','.stdout.txt','.stderr.txt'):(self.path/(c['name']+s)).write_text('fixture')
        p.write_text(json.dumps(r));self.assertEqual(len(parser_proof(p)['files']),14)
        r['cases'][3]['disable_checks'][0]=False;p.write_text(json.dumps(r))
        with self.assertRaisesRegex(ValueError,'PROOF_INVALID'):parser_proof(p)

    def test_armed_policy_requires_target_and_preserves_caps(self):
        p=policy(True,True)
        self.assertEqual(p['host_enable_debugger_points'],[2,4])
        self.assertEqual(p['automatic_debugger_enable_after_create'],[3])
        self.assertEqual(p['raw_hit_limit_per_point'],16)
        self.assertEqual(p['max_total_raw_hits'],48)
        with self.assertRaisesRegex(ValueError,'REQUIRES_TARGET'):policy(False,True)
        with self.assertRaisesRegex(ValueError,'REQUIRES_TARGET'):
            prepare(ROOT,ROOT,self.path,flag_create_armed=True)

    def test_armed_registration_rejects_old_receipt(self):
        profile=ROOT/'scripts/debugger/pb-kd-target-flag-create-armed-profile-20261020.json'
        r=dict(method='target-flow-prepared-commands-v1',source='prepared-command-awaiting-user-attestation',profile_sha256=PROFILE_SHA,
            expected_disabled_ids=[2,3,4],host_registration_observed=False,boot=self.boot)
        path=self.path/'receipt.json'
        def check():
            path.write_text(json.dumps(r));return registration(profile,path,hashlib.sha256(path.read_bytes()).hexdigest(),self.boot)
        with self.assertRaisesRegex(ValueError,'REGISTRATION'):check()
        r['profile_sha256']=ARMED_PROFILE_SHA
        self.assertTrue(check()['automatic_enable'])

    def test_armed_proof_rejects_early_enable_and_unchecked_actions(self):
        names=['selected','nonselected','unreadable','limit']
        states=[{'2':True,'3':False,'4':False},{'2':False,'3':True,'4':False},
                {'2':True,'3':True,'4':True},{'2':True,'3':True,'4':True}]
        r=dict(method='cdb-create-armed-flag-candidate-v1',kernel_connection=False,product_started=False,
            traffic_generated=False,runtime_authorized=False,passed=True,all_actions_proof='all-actions/parser-check.json',
            cases=[dict(name=n,passed=True,values_verified=True,disabled=s) for n,s in zip(names,states)])
        full=dict(method='cdb-safe-bounded-flag-candidate-v1',kernel_connection=False,product_started=False,
            traffic_generated=False,passed=True,cases=[dict(name=n,passed=True,checks=[True]*3,disable_checks=[True]*3,exit_code=0) for n in names])
        child=self.path/'all-actions';child.mkdir()
        profile=(ROOT/'scripts/debugger/pb-kd-target-flag-create-armed-profile-20261020.json').read_bytes()
        for parent in (self.path,child):
            (parent/'candidate.json').write_bytes(profile)
            for n in names:
                for s in ('.wdbg','.stdout.txt','.stderr.txt'):(parent/(n+s)).write_text('fixture')
        path=self.path/'parser-check.json';fp=child/'parser-check.json'
        def check():
            path.write_text(json.dumps(r));fp.write_text(json.dumps(full));return parser_proof(path,True)
        self.assertEqual(len(check()['files']),28)
        r['cases'][1]['disabled']['3']=False
        with self.assertRaisesRegex(ValueError,'PROOF_INVALID'):check()
        r['cases'][1]['disabled']['3']=True;full['cases'][0]['disable_checks'][2]=False
        with self.assertRaisesRegex(ValueError,'ALL_ACTIONS_PROOF'):check()

    def test_armed_evaluation_keeps_cap_failure_incomplete(self):
        plan=self.path/'runtime-plan.json';plan.write_text(json.dumps(dict(policy=policy(True,True))))
        sha=hashlib.sha256(plan.read_bytes()).hexdigest()
        (self.path/'diagnostic-run.json').write_text(json.dumps(dict(debugger_observer=True,flow_registration_acknowledged=True,plan_sha256=sha)))
        console=self.path/'console.txt';console.write_text(TRACK+'PBFG_LIMIT point=3 capture=incomplete\n')
        native=dict(status='TARGET_FAILURE_REPRODUCED',errors=[],matches=[dict(role='control',peer='127.0.0.1:42201',original_api_failure=True)])
        with patch('pb_target_accept_report.evaluate',return_value=native):
            result=evaluate(self.path,console)
        self.assertEqual(result['status'],'INCOMPLETE')
        self.assertIn('BOUNDED_CAPTURE_INCOMPLETE',result['errors'])


if __name__=='__main__':unittest.main()
