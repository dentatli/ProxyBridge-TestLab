"""Regression: endurance applications must be included in both worker rules."""
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from trafficlab.core_session import CoreSession
from trafficlab.rule_scope import case_ports, port_filter
from trafficlab.runner import profile


class RuleScopeTests(unittest.TestCase):
    def test_endurance_scope_reaches_session_and_both_cli_worker_rules(self):
        ports = case_ports({'id': 'soak'}, 42501)
        expected = '42501,42511,42513,42515,42517,42518,42520'
        session = object.__new__(CoreSession)
        session.command = Mock(return_value={'rule_enabled': True})
        self.assertEqual(session.enable(ports)['target_ports'], expected)
        self.assertEqual(bytes.fromhex(session.command.call_args.args[1]).decode(), expected)
        for adapter in ('windivert-4.1-cli-v1', 'driver'):
            with self.subTest(adapter=adapter):
                binding = {'python': 'pb_testlab_adapter_worker.exe', 'native_worker_executable': 'pb_testlab_worker.exe',
                           'runtime_mode': 'local', 'host': '127.0.0.1', 'proxy_port': 42502, 'port': 42501,
                           'secret': '01' * 32, 'adapter_id': adapter}
                rules = profile(binding, 'check', 'SOCKS5', ports)['ProxyRules']
                self.assertEqual(len(rules), 2)
                self.assertEqual({rule['TargetPorts'] for rule in rules}, {expected})
                self.assertEqual({rule['TargetHosts'] for rule in rules}, {'127.0.0.1'})
                self.assertNotIn(42502, ports)
                self.assertNotIn(42503, ports)

    def test_ordinary_cases_keep_their_single_port(self):
        self.assertEqual(case_ports({'id': 'tcp-rtt'}, 42501), (42501,))
        self.assertEqual(case_ports({'id': 'app-sftp', 'application': 'sftp'}, 42501), (42517,))
        self.assertEqual(port_filter(42501), '42501')

    def test_port_scope_cannot_be_empty_wildcard_or_invalid(self):
        for value in ((), '*', '42501,42511', (0,), (65536,), (True,)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                port_filter(value)


if __name__ == '__main__':
    unittest.main()
