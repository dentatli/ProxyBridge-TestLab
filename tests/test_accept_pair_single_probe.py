import json,sys,csv,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from pb_accept_pair_profile import policy
from pb_target_accept_report import evaluate
class SingleProbeReport(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.query=dict(seq=1,peer_addr='127.0.0.1',peer_port=42201,relay_pid=500,local_addr='127.0.0.1',local_port=34010,local_error=0,peer_error=0,api_return=0,api_error=0,bytes=32,category='IPV4_CONTEXT_AVAILABLE',ctx_pid=1000,protocol=6)
  self.write('runtime-plan.json',dict(policy=policy(False)))
  self.write('diagnostic-run.json',dict(status='COLLECTED',cleanup_errors=[],resident_disabled_after=True,debugger_observer=True,flow_registration_acknowledged=True))
  self.write('cli-lifecycle.json',dict(pid=500,ready=True,graceful_stop=True,post_stop_verified=True,output_capture_complete=True,forced_stop=False,error='',stdout='[TARGETGATE] stage=ready token=fixture\n[TARGETGATE] stage=exit released=1 wait_result=0\n'))
  self.write('cohort.json',dict(status='COLLECTED',native_processes_stopped=True,cleanup_errors=[],observations=[dict(stage='fillers-established',pid=0,qpc=1,sockets=[]),dict(stage='control-established',pid=1000,qpc=2,sockets=[dict(Pid=1000,State=5,LocalPort=42201)]),dict(stage='release-request',qpc=3)]))
  self.write('proxy-process.json',dict(exit_code=0,stderr=''))
  self.write('receiver-process.json',dict(output_capture_complete=True,timed_out=False))
  self.write('control-launch.json',dict(pid=1000));self.write('control-process.json',dict(pid=1000,output_capture_complete=True))
  self.csv('control.csv',[dict(LocalAddress='127.0.0.1:42201',RemoteAddress='127.0.0.1:54122',Result='Succeeded',SendBytes='524288',RecvBytes='1',ConnectionId='fixture')])
  self.csv('receiver.csv',[dict(ConnectionId='fixture',Result='Succeeded',RecvBytes='524288')])
 def tearDown(self):self.temp.cleanup()
 def write(self,name,obj):(self.root/name).write_text(json.dumps(obj))
 def csv(self,name,rows):
  with (self.root/name).open('w',newline='') as f:
   w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 def run_report(self,queries=None):
  with patch('pb_target_accept_report.parse_queries',return_value=queries if queries is not None else [self.query]),patch('pb_target_accept_report.evaluate_etw',return_value=dict(final_counters={},errors=[])),patch('pb_target_accept_report.control_events',return_value=[]):
   return evaluate(self.root)
 def test_one_probe_without_filler_process_files(self):
  r=self.run_report();self.assertEqual(r['errors'],[]);self.assertEqual(len(r['matches']),1);self.assertEqual(r['status'],'CREATE_PROBE_NATIVE_SUCCESS_DEBUGGER_PENDING')
 def test_extra_query_not_discarded(self):
  q=dict(self.query,seq=2,peer_port=42001)
  self.assertIn('UNASSIGNED_OR_DUPLICATE_QUERIES',self.run_report([self.query,q])['errors'])
 def test_failure_not_positive_calibration(self):
  self.query.update(api_return=-1,api_error=10022,bytes=0,category='API_FAILED')
  self.assertNotEqual(self.run_report()['status'],'CREATE_PROBE_NATIVE_SUCCESS_DEBUGGER_PENDING')
 def test_policy_tamper_not_accepted(self):
  p=policy(False);p['fillers']=3;self.write('runtime-plan.json',dict(policy=p))
  self.assertIn('ACCEPT_PAIR_POLICY_INVALID',self.run_report()['errors'])
if __name__=='__main__':unittest.main()
