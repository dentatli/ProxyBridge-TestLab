"""Evidence guards: missing BLOCK observations must never become a success."""
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from trafficlab.endurance_policy import check


class PolicyEvidenceTests(unittest.TestCase):
    def exercise(self, block_events=1, leaked=0, health=True):
        ports = list(map(str, range(42541, 42545)))
        events = {p: {'DIRECT': 0, 'PROXY': 0, 'BLOCKED': 0} for p in ports}
        after = {p: {'DIRECT': int(i < 2), 'PROXY': 0, 'BLOCKED': block_events if i >= 2 else 0}
                 for i, p in enumerate(ports)}
        session = Mock()
        session.command.side_effect = [{'events': events}, {'events': after}]
        job = {'run_id': 'policy-unit', '_policy_session': session, 'native_origin_port': 12345,
               'native_origin_pid': 1, 'native_origin_executable': 'origin.exe'}
        empty = {'active': 0, 'proxy': {'tcp_active': 0, 'tcp_flows': 0, 'udp_sent': 0}}
        before_origin = {'policy_receivers': dict.fromkeys(ports, 0)}
        after_origin = {'policy_receivers': {p: 1 if i < 2 else leaked for i, p in enumerate(ports)}}
        results = [{'complete': health}, {'complete': True}, {'complete': True},
                   {'complete': True}, {'complete': False}, {'complete': False}]
        with patch('trafficlab.endurance_policy.execute_worker', side_effect=results), \
             patch('trafficlab.endurance_policy.origin_metrics', side_effect=[before_origin, empty, empty, empty, empty, after_origin]), \
             patch('trafficlab.endurance_policy.cancelled', return_value=False), \
             patch('trafficlab.endurance_policy.time.sleep'):
            return check(job)

    def test_block_requires_event_and_zero_delivery(self):
        self.assertTrue(all(row['complete'] for row in self.exercise()['checks']))
        for values in ({'block_events': 0}, {'leaked': 1}):
            with self.subTest(values=values):
                blocked = [row for row in self.exercise(**values)['checks'] if row['channel'].startswith('block')]
                self.assertTrue(all(not row['complete'] for row in blocked))

    def test_unhealthy_receiver_is_not_a_successful_block(self):
        with self.assertRaisesRegex(ValueError, 'RECEIVER_HEALTH_UNVERIFIED'):
            self.exercise(health=False)


if __name__ == '__main__':
    unittest.main()
