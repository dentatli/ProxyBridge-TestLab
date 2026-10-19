import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_target_accept_plan import create_policy
from pb_target_accept_report import evaluate
from pb_tcp_redirect_context_report import FIELDS


class FourCapture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)
        self.populate()

    def populate(self, fillers=3, failed_control=False):
        self.save('diagnostic-run.json', dict(status='COLLECTED', cleanup_errors=[], resident_disabled_after=True, debugger_observer=True))
        self.save('runtime-plan.json', dict(policy=create_policy(fillers == 200)))
        self.save('proxy-process.json', dict(exit_code=0, stderr=''))
        self.save('receiver-process.json', dict(output_capture_complete=True, timed_out=False))
        self.cohort = dict(status='COLLECTED', native_processes_stopped=True, cleanup_errors=[], observations=[
            dict(stage='fillers-established', qpc=1, pid=100, sockets=[dict(Pid=100, State=5, LocalPort=p) for p in range(42001,42001+fillers)]),
            dict(stage='control-synsent' if fillers == 200 else 'control-established', qpc=2, pid=101,
                 sockets=[dict(Pid=101, State=3 if fillers == 200 else 5, LocalPort=42201)]),
            dict(stage='release-request', qpc=3)])
        self.save('cohort.json', self.cohort)
        stdout = '[TARGETGATE] stage=ready token=fixture timeout_ms=30000\n[TARGETGATE] stage=exit released=1 wait_result=0\n'
        receiver=[]
        seq=0
        for role, pid, ports in [('fillers',100,list(range(42001,42001+fillers))),('control',101,[42201])]:
            self.save(role+'-launch.json',dict(pid=pid))
            self.save(role+'-process.json',dict(pid=pid,output_capture_complete=True))
            rows=[]
            for port in ports:
                seq+=1
                q=dict.fromkeys(FIELDS,0)
                q.update(seq=seq,socket=seq,relay_pid=999,qpc=seq*100,frequency=10000000,
                         bytes=32,required=32,complete=1,family=2,protocol=6,ctx_pid=pid,
                         local_addr='127.0.0.1',local_port=34010,peer_addr='127.0.0.1',peer_port=port)
                failure = failed_control and role == 'control'
                if failure:
                    q.update(api_return=-1, api_error=10022, wsa_after=10022, bytes=0, ctx_pid=0, complete=0)
                stdout+='[CTXDIAG] '+' '.join(str(k)+'='+str(q[k]) for k in FIELDS)+'\n'
                rows.append(dict(LocalAddress=f'127.0.0.1:{port}',RemoteAddress='127.0.0.1:54122',Result='Failed' if failure else 'Succeeded',
                                 SendBytes='0' if failure else '524288',RecvBytes='0' if failure else '41',ConnectionId=str(seq)))
                if not failure:
                    receiver.append(dict(ConnectionId=str(seq),Result='Succeeded',RecvBytes='524288'))
            self.csv(role+'.csv',rows)
        self.csv('receiver.csv',receiver)
        # This is the actual EvidenceSink shape: error/stdout, no process_result.
        self.save('cli-lifecycle.json',dict(ready=True,graceful_stop=True,post_stop_verified=True,output_capture_complete=True,
                                          forced_stop=False,error='',pid=999,stdout=stdout))

    def tearDown(self):
        self.temp.cleanup()

    def save(self,name,value):
        (self.path/name).write_text(json.dumps(value),encoding='utf-8')

    def csv(self,name,rows):
        with (self.path/name).open('w',newline='',encoding='utf-8') as f:
            writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)

    def evaluate(self, events=None):
        with patch('pb_target_accept_report.evaluate_etw',return_value=dict(final_counters={},errors=[])), \
             patch('pb_target_accept_report.control_events',return_value=events or []):
            return evaluate(self.path)

    def test_positive_four_native_capture_uses_sink_contract(self):
        r=self.evaluate()
        self.assertEqual(r['errors'],[])
        self.assertEqual(r['status'],'CREATE_PROBE_NATIVE_SUCCESS_DEBUGGER_PENDING')
        self.assertEqual(len(r['matches']),4)
        self.assertFalse(r['target_trigger_observed'])

    def test_synsent_is_not_four_probe_readiness(self):
        self.cohort['observations'][1]['sockets'][0]['State']=3
        self.save('cohort.json',self.cohort)
        self.assertIn('TARGET_OWNED_SOCKET_OBSERVATION_INVALID',self.evaluate()['errors'])

    def test_four_probe_cannot_silently_become_201(self):
        policy=create_policy();policy['fillers']=200
        self.save('runtime-plan.json',dict(policy=policy))
        self.assertIn('CREATE_FOUR_OBSERVER_POLICY_INVALID',self.evaluate()['errors'])

    def test_target_201_correlates_original_failure_without_requiring_all_success(self):
        self.populate(200, failed_control=True)
        events = [dict(event_id=1214, data=dict(Reason='30'), time='2026-10-19T00:00:00Z'),
                  dict(event_id=1186, data={}, time='2026-10-19T00:00:01Z'),
                  dict(event_id=1553, data=dict(Succeeded='1'), time='2026-10-19T00:00:02Z')]
        r = self.evaluate(events)
        self.assertEqual(r['errors'], [])
        self.assertEqual(len(r['matches']), 201)
        self.assertTrue(r['control_original_api_failure'])
        self.assertEqual(r['status'], 'TARGET_FAILURE_REPRODUCED')

    def test_target_201_without_trigger_remains_inconclusive(self):
        self.populate(200)
        r = self.evaluate()
        self.assertEqual(r['errors'], [])
        self.assertEqual(r['status'], 'INCONCLUSIVE_TARGET_NOT_REPRODUCED')

    def test_target_201_control_established_is_wrong_readiness(self):
        self.populate(200)
        self.cohort['observations'][1]['sockets'][0]['State'] = 5
        self.save('cohort.json', self.cohort)
        self.assertIn('TARGET_OWNED_SOCKET_OBSERVATION_INVALID', self.evaluate()['errors'])


if __name__=='__main__':
    unittest.main()
