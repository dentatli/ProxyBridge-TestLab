"""PnP helper is local WFP only; missing state evidence never authorizes a run."""
import json
import subprocess
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from trafficlab.wfp_device import device


class DeviceBoundaryTests(unittest.TestCase):
    def test_other_adapters_never_invoke_pnp(self):
        with patch('trafficlab.wfp_device.subprocess.run') as run:
            for binding in ({'product_contract': 'v4.0.0', 'runtime_mode': 'local'},
                            {'product_contract': 'driver', 'runtime_mode': 'remote'}):
                self.assertFalse(device('unused', binding, 'Enable')['applicable'])
            run.assert_not_called()

    def test_helper_requires_matching_verified_action(self):
        binding = {'product_contract': 'driver', 'runtime_mode': 'local', 'root': 'unused'}
        # CREATE_NO_WINDOW is absent on non-Windows test hosts.
        with patch.object(subprocess, 'CREATE_NO_WINDOW', 0, create=True):
            for evidence in ({}, {'applicable': True, 'action': 'Disable', 'verified': True},
                             {'applicable': True, 'action': 'Enable', 'verified': False}):
                result = SimpleNamespace(returncode=0, stdout=json.dumps(evidence).encode(), stderr=b'')
                with patch('trafficlab.wfp_device.subprocess.run', return_value=result), self.assertRaises(ValueError):
                    device('unused', binding, 'Enable')
            result = SimpleNamespace(returncode=0, stdout=b'{"applicable":true,"action":"Enable","verified":true}', stderr=b'')
            with patch('trafficlab.wfp_device.subprocess.run', return_value=result):
                self.assertTrue(device('unused', binding, 'Enable')['verified'])
