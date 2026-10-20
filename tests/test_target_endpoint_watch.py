import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'))
from pb_endpoint_watch_report import correlate,evaluate
from pb_endpoint_watch_profile import policy,registration,PROFILE_SHA
from pb_target_accept_plan import prepare
import hashlib

TRACK='PBW TRACK ep=1000 record=2000 context=3000 size=20 refs=1 flags30=1101641\n'
ARM='PBW ARMED address=1030\n'
WRITE='PBW WRITE hit=1 thread=4000 ep=1000 record=2000 old=1101641 new=1301641 ip=5000\n'
ACCEPT='PBW RETRIEVE ep=6000 nbl=7000 status=0 output_raw=2000\n'
STACK='PBW TRANSITION_BEGIN\n00 ffff000000001000 ffff000000002000 tcpip!WfpTlShimInspectRecvTcpDatagram+0x198\nPBW TRANSITION_END\n'


class EndpointWatch(unittest.TestCase):
    def test_packet_header_fields_are_bound_to_observed_transition(self):
        h='PBW RECEIVE_HEADER ep=1000 record=2000 nbl=7000 header=8000 src_raw=da84 dst_raw=d9a4 flags=14 h0=7b000000d9a4da84 h1=41450c8010000 h2=0\n'
        self.assertEqual(correlate(TRACK+ARM+WRITE+h+STACK)['packet_header']['flags'],0x14)
        for bad in (h.replace('flags=14','flags=12'),h.replace('ep=1000','ep=9000'),h+h,h.replace('h2=0','h2=100000000')):
            with self.subTest(header=bad):self.assertEqual(correlate(TRACK+ARM+WRITE+bad+STACK)['status'],'INCOMPLETE')
        self.assertEqual(correlate(TRACK+ARM+h+WRITE+STACK)['status'],'INCOMPLETE')

    def test_packet_policy_cannot_expand_trap_or_load_budget(self):
        from pb_endpoint_packet_watch import policy as packet_policy,parser_proof
        p=packet_policy(True)
        self.assertEqual({k:v for k,v in p.items() if k not in ('endpoint_packet_header','packet_header_bytes','packet_header_count_max')},policy(True))
        self.assertEqual(p['packet_header_bytes'],20);self.assertEqual(p['packet_header_count_max'],1)
        with self.assertRaisesRegex(ValueError,'TARGET_ONLY'):packet_policy(False)

    def test_transition_proves_observed_write_not_causation(self):
        r=correlate(TRACK+ARM+ACCEPT+WRITE+STACK)
        self.assertEqual(r['status'],'ENDPOINT_FLAG_TRANSITION_OBSERVED')
        self.assertTrue(r['post_write_observed']);self.assertTrue(r['transition_observed'])
        self.assertFalse(r['root_cause_proven']);self.assertFalse(r['trap_coverage_verified'])

    def test_data_sequence_and_lifetime_fail_closed(self):
        cases=[TRACK+ARM+WRITE.replace('ep=1000','ep=9999')+STACK,
               TRACK+ARM+WRITE.replace('old=1101641','old=1101643')+STACK,
               TRACK+ARM+WRITE,TRACK+ARM+WRITE+STACK+WRITE,
               TRACK+ARM+'PBW_IDENTITY_CHANGED capture=incomplete\n',
               TRACK+ARM+'PBW_LIMIT point=3 capture=incomplete\n']
        for text in cases:
            with self.subTest(text=text):self.assertEqual(correlate(text)['status'],'INCOMPLETE')

    def test_never_infers_missing_transition_from_successful_retrieve(self):
        r=correlate(TRACK+ARM+ACCEPT)
        self.assertEqual(r['status'],'ENDPOINT_WATCH_COVERAGE_UNPROVEN')
        self.assertFalse(r['transition_observed']);self.assertFalse(r['trap_coverage_verified'])

    def test_healthy_policy_has_four_connections_and_only_selected_writes(self):
        p=policy(False)
        self.assertEqual(p['fillers'],3);self.assertEqual(p['initial_debugger_points'],[2,4])
        self.assertEqual(p['dynamic_debugger_points'],[3]);self.assertEqual(p['watch_size'],4)
        self.assertEqual(p['selected_snapshot_limits_per_point']['3'],16)
        self.assertNotIn('host_deadline_ms',p)
        with self.assertRaisesRegex(ValueError,'REQUIRES_FLAG_MODE'):prepare(ROOT,ROOT,ROOT,endpoint_watch=True)

    def test_loaded_watch_does_not_enable_global_accept(self):
        p=policy(True)
        self.assertEqual(p['debugger_points'],[2,3]);self.assertEqual(p['host_enable_debugger_points'],[2])
        self.assertEqual(p['inactive_debugger_points'],[4]);self.assertEqual(p['max_total_raw_hits'],32)
        self.assertEqual(p['fillers'],200);self.assertEqual(p['control_connections'],1)

    def test_registration_requires_absent_dynamic_slot(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'receipt.json';boot=dict(method='kernel-general-12-and-prefetch-bootid-v1',cryptographic_boot_identity=False,
                identity=dict(computer='VM',provider='Microsoft-Windows-Kernel-General',event_id=12,event_record_id=1,
                event_time_utc='2026-10-20T00:00:00Z',start_time_utc='2026-10-20T00:00:00Z',prefetch_boot_id=117))
            r=dict(method='target-flow-prepared-commands-v1',source='prepared-command-awaiting-user-attestation',profile_sha256=PROFILE_SHA,
                   expected_disabled_ids=[2,4],expected_absent_ids=[3],host_registration_observed=False,boot=boot)
            def check():
                p.write_text(json.dumps(r));return registration(ROOT/'scripts/debugger/pb-kd-selected-endpoint-watch-profile-20261020.json',p,hashlib.sha256(p.read_bytes()).hexdigest(),boot)
            self.assertEqual(check()['dynamic_point_ids'],[3])
            r['expected_absent_ids']=[]
            with self.assertRaisesRegex(ValueError,'REGISTRATION_DIFFERS'):check()

    def test_native_success_does_not_override_incomplete_watch(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp);plan=p/'runtime-plan.json';plan.write_text(json.dumps(dict(policy=policy(False))))
            (p/'diagnostic-run.json').write_text(json.dumps(dict(debugger_observer=True,flow_registration_acknowledged=True,plan_sha256=hashlib.sha256(plan.read_bytes()).hexdigest())))
            c=p/'console.txt';c.write_text(TRACK+ARM+ACCEPT+WRITE+STACK)
            native=dict(status='NATIVE_SUCCESS',errors=[],matches=[dict(role='control',peer='127.0.0.1:42201',original_api_failure=False)])
            with patch('pb_target_accept_report.evaluate',return_value=native):
                self.assertEqual(evaluate(p,c)['status'],'ENDPOINT_WATCH_NATIVE_SUCCESS_OBSERVED')
                c.write_text(TRACK+ARM+ACCEPT+'PBW_LIMIT point=3 capture=incomplete\n')
                self.assertEqual(evaluate(p,c)['status'],'INCOMPLETE')


if __name__=='__main__':unittest.main()
