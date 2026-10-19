import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from pb_target_retry_profile import profile, fixture, stage, PROFILE_SHA, PROFILE_NAME, STAGE_NAME, validate_parser_proof
from pb_target_accept_plan import flow_policy, validate_registration, prepare
from pb_target_retry_report import correlate

TRACK='PBRT TRACK thread=1 source_ep=10 record=20 context=30 size=20 refs=1\n'
SEND='PBRT SEND thread=1 scope=200 tcb=40 nbl=50 source_ep=10 local_raw=d9a4 peer_raw=da84\n'
ENTRY='PBRT INSPECT thread=1 scope=200 source_ep=10 nbl=50 family=2 flags30=0 flags34=2000 record=20\n'
POST='PBRT ASSOC_RETURN thread=1 scope=198 source_ep=10 nbl=50 result_raw=0\n'
ACCEPT='PBRT RETRIEVE thread=2 scope=300 ep=60 nbl=50 local_raw=da84 peer_raw=d9a4 status=c0000225 output_raw=0\n'


class RetryEvidence(unittest.TestCase):
    def test_full_snapshot_chain_is_not_root_cause_or_retry_proof(self):
        r=correlate(TRACK+SEND+ENTRY+POST+ACCEPT)
        self.assertEqual(r['status'],'SELECTED_CHAIN_SNAPSHOTS_OBSERVED')
        self.assertEqual(len(r['association_pairs']),1)
        self.assertFalse(r['root_cause_proven']);self.assertFalse(r['retry_clock_alignment_verified'])
        self.assertFalse(r['events'][-1]['returned_record_matches_create'])

    def test_missing_post_is_not_proof_of_loss(self):
        r=correlate(TRACK+SEND+ENTRY+ACCEPT)
        self.assertEqual(r['errors'],[])
        self.assertEqual(r['status'],'CHAIN_INCOMPLETE_COVERAGE_UNPROVEN')

    def test_null_send_endpoint_is_preserved(self):
        r=correlate(TRACK+SEND.replace('source_ep=10','source_ep=0'))
        self.assertFalse(r['events'][-1]['source_matches_create'])
        self.assertEqual(r['errors'],[])

    def test_post_from_another_scope_cannot_match(self):
        r=correlate(TRACK+ENTRY+POST.replace('scope=198','scope=199'))
        self.assertIn('ASSOC_RETURN_WITHOUT_INSPECT',r['errors'])

    def test_partial_printf_error_and_duplicate_fail_closed(self):
        for suffix in ('PBRT_DUPLICATE capture=incomplete','Extra character error'):
            self.assertTrue(correlate(TRACK+suffix)['errors'])

    def test_bit21_skips_association_despite_preserved_record(self):
        first=ENTRY.replace('flags30=0','flags30=1101641')
        later=ENTRY.replace('scope=200','scope=400').replace('flags30=0','flags30=1301641')
        r=correlate(TRACK+SEND+first+POST+later+ACCEPT)
        entries=[e for e in r['events'] if e['kind']=='INSPECT']
        self.assertTrue(entries[0]['association_branch_eligible'])
        self.assertFalse(entries[1]['association_branch_eligible'])
        self.assertTrue(entries[1]['record_matches_create'])
        self.assertEqual(len(r['association_pairs']),1)
        self.assertFalse(r['root_cause_proven'])

    def test_hot_trace_cannot_be_prepared_again(self):
        with self.assertRaisesRegex(ValueError,'PROFILE_RETIRED_HOT_TRACE'):
            prepare(None,None,None,retry_target=True)

    def test_fixture_does_not_replace_wo_inside_dwo(self):
        text=fixture(profile()['points'][2]['action'],{})
        self.assertNotIn('d0x',text);self.assertNotIn('dwo(',text)
        self.assertIn('.printf "PBRT INSPECT',text)

    def test_pinned_stage_contains_disabled_actions_and_no_enable_resume(self):
        root=Path(__file__).resolve().parents[1];raw=(root/'scripts/debugger'/PROFILE_NAME).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),PROFILE_SHA)
        self.assertEqual(json.loads(raw),profile())
        self.assertEqual((root/'scripts/debugger'/STAGE_NAME).read_text(),stage(profile()))
        self.assertFalse(any(l.startswith(('be','g')) for l in stage(profile()).splitlines()))
        self.assertEqual(flow_policy(retry=True)['debugger_points'],[2,3,4,5,6])
        with self.assertRaises(ValueError):flow_policy(True,True)

    def test_retry_receipt_cannot_reuse_three_point_registration(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'review.json';boot=dict(identity=dict(computer='TESTVM',provider='Microsoft-Windows-Kernel-General',event_id=12,event_record_id=1,event_time_utc='2026-10-19T00:00:00Z',start_time_utc='2026-10-19T00:00:00Z',prefetch_boot_id=1))
            boot.update(method='kernel-general-12-and-prefetch-bootid-v1',cryptographic_boot_identity=False)
            r=dict(method='target-flow-prepared-commands-v1',source='prepared-command-awaiting-user-attestation',profile_sha256=PROFILE_SHA,expected_disabled_ids=[2,3,4,5,6],host_registration_observed=False,boot=boot)
            path=Path(__file__).resolve().parents[1]/'scripts/debugger'/PROFILE_NAME
            def check():
                p.write_text(json.dumps(r));return validate_registration(path,p,hashlib.sha256(p.read_bytes()).hexdigest(),boot)
            self.assertEqual(check()['proposed_active_point_ids'],[2,3,4,5,6])
            r['expected_disabled_ids']=[2,3,4]
            with self.assertRaises(ValueError):check()

    def test_parser_proof_requires_every_point_branch(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'parser-check.json'
            r=dict(method='cdb-safe-retry-command-fixture-v1',passed=True,profile_sha256=PROFILE_SHA,kernel_connection=False,product_started=False,traffic_generated=False,
                cases=[dict(name=n,passed=True,exit_code=0,point_checks=[True]*5) for n in ('selected','unreadable','not-selected','duplicate')])
            for c in r['cases']:
                for suffix in ('.wdbg','.stdout.txt','.stderr.txt'):(p.parent/(c['name']+suffix)).write_text('fixture')
            p.write_text(json.dumps(r));self.assertEqual(len(validate_parser_proof(p)['files']),13)
            r['cases'][1]['point_checks'][2]=False;p.write_text(json.dumps(r))
            with self.assertRaises(ValueError):validate_parser_proof(p)


if __name__=='__main__':unittest.main()
