import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'))
from pb_endpoint_send_gate import correlate,evaluate,policy,profile,PROFILE,PROFILE_SHA,create_action,read_action
from pb_target_flag_binding import policy as flag_policy,profile_sha
from pb_target_accept_plan import validate_positive_probe

TRACK='PBSD TRACK ep=1000 record=2000 context=3000 size=20 refs=1 flags30=1101641\n'
ARM='PBSD ARMED address=1030 access=r4 accept=4\n'
GATE='PBSD SEND_GATE send=1 raw=2 thread=4000 ep=1000 record=2000 nbl=5000 flags_reg=1101641 family=2 ip=8000\n'
HEADER='PBSD SEND_HEADER send=1 nbl=5000 header=6000 flags=2 h0=7b000000da84d9a4 h1=400025000000000 h2=0\n'
SECOND=GATE.replace('send=1 raw=2','send=2 raw=4').replace('nbl=5000','nbl=7000').replace('flags_reg=1101641','flags_reg=1301641')
HEADER2=HEADER.replace('send=1 nbl=5000','send=2 nbl=7000')
ACCEPT='PBSD ACCEPT ep=9000 nbl=7000 local_raw=da84 peer_raw=d9a4 status=c0000225 output_raw=0 reads=4 sends=2\n'


class SendGate(unittest.TestCase):
    def test_native_query_mode_never_arms_accept_and_requires_no_kernel_accept(self):
        from pb_endpoint_send_gate import NATIVE_SHA,NATIVE_PROFILE
        self.assertEqual(hashlib.sha256((ROOT/NATIVE_PROFILE).read_bytes()).hexdigest(),NATIVE_SHA)
        self.assertEqual(json.loads((ROOT/NATIVE_PROFILE).read_text()),profile(0))
        self.assertNotIn('be4;',create_action(True))
        self.assertEqual(policy(True,0)['debugger_points'],[2,3])
        self.assertEqual(policy(True,0)['raw_hit_limits_per_point'],{'2':16,'3':64})
        self.assertEqual(policy(True,0),flag_policy(True,True,True,False,'sendnative'))
        self.assertEqual(profile_sha(True,True,False,'sendnative'),NATIVE_SHA)
        text=TRACK+ARM.replace('accept=4','accept=disabled')+GATE+HEADER+SECOND+HEADER2
        self.assertEqual(correlate(text,True)['status'],'SEND_GATE_OBSERVATIONS_COLLECTED')
        self.assertIsNone(correlate(text,True)['accept'])
        self.assertEqual(correlate(text+ACCEPT,True)['status'],'INCOMPLETE')

    def test_native_query_mode_does_not_promote_10061_or_missing_query(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp);plan=p/'runtime-plan.json';plan.write_text(json.dumps(dict(policy=policy(True,0))))
            (p/'diagnostic-run.json').write_text(json.dumps(dict(debugger_observer=True,flow_registration_acknowledged=True,plan_sha256=hashlib.sha256(plan.read_bytes()).hexdigest())))
            c=p/'console.txt';c.write_text(TRACK+ARM.replace('accept=4','accept=disabled')+GATE+HEADER+SECOND+HEADER2)
            native=dict(status='TARGET_FAILURE_REPRODUCED',errors=[],matches=[dict(role='control',peer='127.0.0.1:42201',original_api_failure=True)])
            with patch('pb_target_accept_report.evaluate',return_value=native):
                r=evaluate(p,c);self.assertEqual(r['status'],'SEND_SKIP_AND_NATIVE_QUERY_FAILURE_OBSERVED')
                self.assertFalse(r['kernel_accept_observed']);self.assertFalse(r['root_cause_proven'])
                native['matches']=[];native['errors']=['NATIVE_ENDPOINT_UNOWNED']
                self.assertEqual(evaluate(p,c)['status'],'INCOMPLETE')

    def test_native_report_preserves_incomplete_lifecycle_for_accept256(self):
        from pb_target_accept_report import evaluate as native_evaluate
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)
            fixtures={'runtime-plan.json':dict(policy=policy(True,256)),
                'diagnostic-run.json':dict(debugger_observer=True,flow_registration_acknowledged=True,status='FAILED',cleanup_errors=['FAILED_STOP'],resident_disabled_after=True),
                'cli-lifecycle.json':dict(ready=True,graceful_stop=True,post_stop_verified=True,output_capture_complete=True,forced_stop=False,error='TCP_TABLE_UNSTABLE'),
                'cohort.json':dict(status='INCOMPLETE',native_processes_stopped=False,cleanup_errors=['FAILED_STOP'],observations=[])}
            for name,value in fixtures.items():(p/name).write_text(json.dumps(value))
            r=native_evaluate(p)
            self.assertIn('RUN_CONTROLLER_STATUS_NOT_COLLECTED',r['errors'])
            self.assertIn('COHORT_INCOMPLETE',r['errors'])
            self.assertFalse(any('POLICY_INVALID' in e for e in r['errors']))
            (p/'runtime-plan.json').write_text(json.dumps(dict(policy=policy(True,0))))
            r=native_evaluate(p)
            self.assertIn('RUN_CONTROLLER_STATUS_NOT_COLLECTED',r['errors'])
            self.assertFalse(any('POLICY_INVALID' in e for e in r['errors']))

    def test_accept256_changes_only_accept_cap_and_retains_old_profile(self):
        from pb_endpoint_send_gate import ACCEPT256_PROFILE,ACCEPT256_SHA,accept_action
        old,new=profile(),profile(256)
        self.assertEqual(new['points'][:2],old['points'][:2])
        self.assertEqual(new['points'][2]['action'],old['points'][2]['action'].replace('>= 0x40','>= 0x100'))
        self.assertEqual(hashlib.sha256((ROOT/ACCEPT256_PROFILE).read_bytes()).hexdigest(),ACCEPT256_SHA)
        self.assertEqual(json.loads((ROOT/ACCEPT256_PROFILE).read_text()),new)
        self.assertEqual(profile_sha(True,True,False,'send256'),ACCEPT256_SHA)
        for target in (True,False):
            self.assertEqual(policy(target,256),flag_policy(target,True,True,not target,'send256'))
            self.assertEqual(policy(target,256)['max_total_raw_hits'],336)
        for fn in (profile,accept_action):
            with self.assertRaises(ValueError):fn(512)

    def test_retry_chain_observes_skip_and_miss_without_claiming_root_cause(self):
        r=correlate(TRACK+ARM+GATE+HEADER+SECOND+HEADER2+ACCEPT)
        self.assertEqual(r['status'],'SEND_SKIP_AND_ACCEPT_MISS_OBSERVED')
        self.assertTrue(r['repeated_syn_observed']);self.assertTrue(r['nbl_pointer_match'])
        self.assertFalse(r['root_cause_proven']);self.assertFalse(r['trap_coverage_verified'])

    def test_packet_identity_sequence_and_command_limits_fail_closed(self):
        text=TRACK+ARM+GATE+HEADER+SECOND+HEADER2+ACCEPT
        for bad in (text.replace('flags=2','flags=14'),text.replace('record=2000 nbl=7000','record=9999 nbl=7000'),
            text.replace('peer_raw=d9a4','peer_raw=d9a5'),text.replace(HEADER2,''),text.replace('raw=4','raw=65'),
            text+SECOND,text+'PBSD_LIMIT point=4 capture=incomplete\n',text.replace('access=r4','access=w4')):
            with self.subTest(text=bad):self.assertEqual(correlate(bad)['status'],'INCOMPLETE')

    def test_only_one_skip_does_not_prove_a_repeated_syn(self):
        gate=GATE.replace('flags_reg=1101641','flags_reg=1301641')
        accept=ACCEPT.replace('nbl=7000','nbl=5000').replace('reads=4 sends=2','reads=2 sends=1')
        r=correlate(TRACK+ARM+gate+HEADER+accept)
        self.assertEqual(r['status'],'SEND_GATE_OBSERVATIONS_COLLECTED');self.assertFalse(r['repeated_syn_observed'])

    def test_changed_sequence_or_nbl_identity_is_reported_without_guessing(self):
        r=correlate(TRACK+ARM+GATE+HEADER+SECOND+HEADER2.replace('7b000000','7c000000')+ACCEPT.replace('nbl=7000','nbl=a000'))
        self.assertFalse(r['repeated_syn_observed']);self.assertFalse(r['nbl_pointer_match'])
        self.assertEqual(r['status'],'SEND_GATE_OBSERVATIONS_COLLECTED')

    def test_pinned_profile_preserves_three_points_and_selected_memory_watch(self):
        self.assertEqual(hashlib.sha256((ROOT/PROFILE).read_bytes()).hexdigest(),PROFILE_SHA)
        self.assertEqual(json.loads((ROOT/PROFILE).read_text()),profile())
        self.assertIn('ba3 r4 (@$t2+0x30)',create_action());self.assertNotIn('bp3 ',create_action())
        self.assertIn('be4;',create_action());self.assertNotIn('k 8',read_action())
        for target in (True,False):
            p=policy(target)
            self.assertEqual(p['debugger_points'],[2,3,4]);self.assertEqual(p['host_enable_debugger_points'],[2])
            self.assertEqual(p['raw_hit_limits_per_point'],{'2':16,'3':64,'4':64})
            self.assertEqual(p,flag_policy(target,True,True,not target,'send'))
        self.assertEqual(policy(False)['fillers'],3);self.assertEqual(policy(True)['fillers'],200)
        self.assertEqual(profile_sha(True,True,True,'send'),PROFILE_SHA)

    def test_reboot_rejects_old_positive_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp);(p/'runtime-plan.json').write_text(json.dumps(dict(policy=policy(False),preparation=str(p))))
            identity=dict(computer='VM',provider='Microsoft-Windows-Kernel-General',event_id=12,event_record_id=1,event_time_utc='2026-10-20T00:00:00Z',start_time_utc='2026-10-20T00:00:00Z',prefetch_boot_id=117)
            boot=dict(method='kernel-general-12-and-prefetch-bootid-v1',cryptographic_boot_identity=False,identity=identity)
            (p/'boot-session.json').write_text(json.dumps(boot))
            new=dict(boot,identity=dict(identity,prefetch_boot_id=118))
            with self.assertRaisesRegex(ValueError,'BOOT_DIFFERS'):validate_positive_probe(p,p/'console.txt',new)

    def test_native_success_cannot_override_missing_debugger_header(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp);plan=p/'runtime-plan.json';plan.write_text(json.dumps(dict(policy=policy(False))))
            (p/'diagnostic-run.json').write_text(json.dumps(dict(debugger_observer=True,flow_registration_acknowledged=True,plan_sha256=hashlib.sha256(plan.read_bytes()).hexdigest())))
            console=p/'console.txt';accept=ACCEPT.replace('nbl=7000','nbl=5000').replace('status=c0000225 output_raw=0','status=0 output_raw=2000').replace('reads=4 sends=2','reads=2 sends=1')
            native=dict(status='NATIVE_SUCCESS',errors=[],matches=[dict(role='control',peer='127.0.0.1:42201',original_api_failure=False)])
            with patch('pb_target_accept_report.evaluate',return_value=native):
                console.write_text(TRACK+ARM+GATE+HEADER+accept)
                self.assertEqual(evaluate(p,console)['status'],'SEND_GATE_HEALTHY_CONTROL_OBSERVED')
                console.write_text(TRACK+ARM+GATE+accept)
                self.assertEqual(evaluate(p,console)['status'],'INCOMPLETE')


if __name__=='__main__':unittest.main()
