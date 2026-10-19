import copy
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_target_accept_report import correlate


class TargetRoles(unittest.TestCase):
    def setUp(self):
        self.roles = {}
        self.queries, self.receiver = [], []
        for role, pid, ports in [('fillers', 100, [57001, 57002]), ('control', 101, [57201])]:
            rows = []
            for port in ports:
                seq = len(self.queries) + 1
                row = dict(LocalAddress=f'127.0.0.1:{port}', RemoteAddress='127.0.0.1:54122',
                           Result='Succeeded', SendBytes='524288', RecvBytes='41', ConnectionId=str(seq))
                q = dict(seq=seq, peer_addr='127.0.0.1', peer_port=port, relay_pid=500,
                         local_addr='127.0.0.1', local_port=34010, local_error=0, peer_error=0,
                         api_return=0, api_error=0, bytes=32, category='IPV4_CONTEXT_AVAILABLE',
                         ctx_pid=pid, protocol=6)
                rows.append(row)
                self.queries.append(q)
                self.receiver.append(dict(ConnectionId=str(seq), Result='Succeeded', RecvBytes='524288'))
            self.roles[role] = dict(pid=pid, ports=ports, rows=rows)

    def evaluate(self):
        return correlate(self.roles, self.queries, self.receiver, 500)

    def test_distinct_overlapping_processes(self):
        matches, errors = self.evaluate()
        self.assertEqual(errors, [])
        self.assertEqual([m['native_pid'] for m in matches], [100, 100, 101])

    def test_control_original_failure(self):
        row = self.roles['control']['rows'][0]
        row.update(Result='NotAllDataTransferred', SendBytes='0', RecvBytes='0')
        self.queries[-1].update(api_return=-1, api_error=10022, bytes=0, category='API_FAILED')
        self.receiver.pop()
        matches, errors = self.evaluate()
        self.assertEqual(errors, [])
        self.assertTrue(matches[-1]['original_api_failure'])

    def test_swapped_context_pid_is_rejected(self):
        self.queries[-1]['ctx_pid'] = 100
        self.assertIn('control:SUCCESS_CONTEXT_OR_BYTES_DIFFERS', self.evaluate()[1])

    def test_duplicate_query_is_not_nearest_matched(self):
        duplicate = copy.deepcopy(self.queries[-1])
        duplicate['seq'] = 99
        self.queries.append(duplicate)
        self.assertIn('control:QUERY_NOT_UNIQUE', self.evaluate()[1])

    def test_foreign_control_port(self):
        self.roles['control']['rows'][0]['LocalAddress'] = '127.0.0.1:57202'
        self.assertIn('control:NATIVE_ENDPOINT_UNOWNED', self.evaluate()[1])

    def test_receiver_stale_guid(self):
        self.receiver[-1]['ConnectionId'] = 'old-run'
        self.assertIn('RECEIVER_GUID_OR_DATA_DIFFERS', self.evaluate()[1])

    def test_unrelated_query_not_silently_discarded(self):
        extra = copy.deepcopy(self.queries[-1]);extra.update(seq=99, peer_port=60000)
        self.queries.append(extra)
        self.assertIn('UNASSIGNED_OR_DUPLICATE_QUERIES', self.evaluate()[1])

    def test_10061_not_counted_as_original_failure(self):
        row = self.roles['control']['rows'][0]
        row.update(Result='10061: connection refused', SendBytes='0', RecvBytes='0')
        self.assertIn('control:OTHER_NATIVE_FAILURE', self.evaluate()[1])


if __name__ == '__main__':
    unittest.main()
