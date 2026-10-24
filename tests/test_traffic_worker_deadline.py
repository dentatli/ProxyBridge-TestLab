"""A stuck SSH library cannot hold the queue or defeat cancellation."""
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from trafficlab.bounded_worker import execute_bounded
from trafficlab.protocol import json_bytes, mac
from trafficlab.schedule import verified_origin_snapshot


class WorkerDeadlineTests(unittest.TestCase):
    def exercise(self, cancel):
        real_popen = subprocess.Popen
        children = []
        def stuck(_arguments, **kwargs):
            process = real_popen([sys.executable, '-c', 'import time;time.sleep(60)'], **kwargs)
            children.append(process)
            return process
        with tempfile.TemporaryDirectory() as directory:
            flag = Path(directory) / 'cancel.requested'
            job = {'application': 'ssh', 'task': 'echo', 'run_id': 'deadline-test', 'seconds': .05,
                   'connections': 1, 'cancellation_path': str(flag), '_worker_directory': directory, '_worker_process': {}}
            timer = threading.Timer(.15, lambda: flag.write_text('stop')) if cancel else None
            if timer:
                timer.start()
            started = time.monotonic()
            try:
                with patch('trafficlab.bounded_worker.subprocess.Popen', side_effect=stuck), \
                     patch('trafficlab.bounded_worker.DEADLINE_GRACE', 30 if cancel else .2):
                    result = execute_bounded(job)
            finally:
                if timer:
                    timer.join()
            self.assertLess(time.monotonic() - started, 3)
            self.assertFalse(result['complete'])
            self.assertFalse(result['worker_results_available'])
            self.assertEqual(result['cancelled'], cancel)
            self.assertIn('TRAFFIC_SSH_WORKER_CANCELLED' if cancel else 'TRAFFIC_SSH_WORKER_DEADLINE_EXCEEDED', result['errors'])
            self.assertEqual(len(children), 1)
            self.assertIsNotNone(children[0].poll())
            self.assertTrue(job['_worker_process']['finished'])

    def test_stuck_worker_has_a_hard_deadline(self):
        self.exercise(False)

    def test_cancel_stops_the_owned_worker(self):
        self.exercise(True)

    def test_child_accepts_only_signed_identity_for_its_stage(self):
        job = {'run_id':'stage-ssh', 'secret':'12' * 32, 'application_ssh_sha256':'pinned-key'}
        value = {'identity':{'application':{'ssh_host_key_sha256':'pinned-key'}}}
        context = b'a' * 64 + json_bytes({'run_id':job['run_id'], 'task':'metrics'})
        snapshot = {**value, 'authentication':{'context_hex':context.hex(),
            'proof':mac(bytes.fromhex(job['secret']), b'result:', context + json_bytes(value))}}
        self.assertEqual(verified_origin_snapshot(job, snapshot), value)
        with self.assertRaisesRegex(ValueError, 'SNAPSHOT_SCOPE_INVALID'):
            verified_origin_snapshot({**job, 'run_id':'another-stage'}, snapshot)
        with self.assertRaisesRegex(ValueError, 'AUTHENTICATION_FAILED'):
            verified_origin_snapshot(job, {**snapshot, 'identity':{}})
        with self.assertRaisesRegex(ValueError, 'HOST_KEY_CHANGED'):
            verified_origin_snapshot({**job, 'application_ssh_sha256':'another-key'}, snapshot)
