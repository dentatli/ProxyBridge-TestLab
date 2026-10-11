"""Fault injection for installer transactions; Linux filesystem semantics are required."""
import base64
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from trafficlab import deploy
actual_state = deploy.state


@unittest.skipUnless(os.name == 'posix', 'Ubuntu installer filesystem checks')
class DeploymentTests(unittest.TestCase):
    def setUp(self):
        import pwd
        self.directory = tempfile.TemporaryDirectory(prefix='testlab-deploy-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / 'runtime'
        self.root.mkdir()
        self.unit = Path(self.directory.name) / 'service.unit'
        self.old = self.root / 'versions' / ('a' * 64)
        self.old.mkdir(parents=True)
        self.old_payload = {'hashes': {}, 'config_sha256': 'b' * 64, 'bundle_sha256': 'a' * 64}
        (self.old / 'runtime-manifest.json').write_text(json.dumps(self.old_payload))
        (self.root / 'current').symlink_to(self.old)
        self.old_unit = b'# ProxyBridge-TestLab owned traffic runtime\nold unit\n'
        self.unit.write_bytes(self.old_unit)
        self.active = self.enabled = True
        self.commands = []
        self.fail = 'restart'
        self.valid_old = True
        sources = {'trafficlab/agent.py': b'# isolated fixture', 'traffic-dependencies.lock.json': b'{}'}
        self.payload = {'action': 'apply', 'bundle_sha256': 'c' * 64,
            'sources': {name: base64.b64encode(value).decode() for name, value in sources.items()},
            'hashes': {name: deploy.digest(value) for name, value in sources.items()},
            'configuration': base64.b64encode(b'{}').decode(), 'config_sha256': deploy.digest(b'{}')}
        previous_path = sys.path[:]
        self.addCleanup(lambda: sys.path.__setitem__(slice(None), previous_path))
        patches = (patch.object(deploy, 'ROOT', self.root), patch.object(deploy, 'UNIT', self.unit),
            patch.object(deploy, 'platform'), patch.object(deploy, 'state', side_effect=self.state),
            patch.object(deploy, 'command', side_effect=self.command), patch.object(deploy, 'provision_pki', side_effect=self.pki),
            patch('trafficlab.dependencies.extract', return_value={'fixture': 'hash'}),
            patch.object(pwd, 'getpwnam', return_value=SimpleNamespace(pw_gid=os.getgid())),
            patch.object(os, 'chown'), patch.dict(os.environ, {'SSH_CONNECTION': '192.0.2.10 1000 192.0.2.20 22'}),
            patch('time.sleep'))
        for item in patches:
            item.start()
            self.addCleanup(item.stop)

    def state(self, payload):
        previous = payload['bundle_sha256'] == self.old_payload['bundle_sha256']
        matches = previous and self.valid_old
        return {'state': 'READY' if matches and self.active and self.enabled else 'SETUP_REQUIRED',
            'hashes_match': matches, 'service_active': self.active, 'service_enabled': self.enabled, 'listeners': self.active}

    def command(self, *args, required=True):
        self.commands.append(args)
        if args[:2] == ('systemctl', 'is-active'):
            return 'active' if self.active else 'inactive'
        if args[:2] == ('systemctl', 'is-enabled'):
            return 'enabled' if self.enabled else 'disabled'
        if args[0] == 'ss':
            return ''
        operation = args[1]
        if operation == self.fail:
            raise ValueError('TRAFFIC_SERVICE_COMMAND_FAILED')
        if operation == 'stop':
            self.active = False
        elif operation in ('start', 'restart'):
            self.active = True
        elif operation in ('enable', 'disable'):
            self.enabled = operation == 'enable'
        return ''

    def pki(self, stage):
        (stage / 'pki').mkdir()
        for name in deploy.PKI_NAMES:
            (stage / 'pki' / name).write_bytes(b'isolated fixture')
        return {name: deploy.digest(b'isolated fixture') for name in deploy.PKI_NAMES}

    def assert_previous(self, active=True, enabled=True):
        self.assertEqual(os.readlink(self.root / 'current'), str(self.old))
        self.assertEqual(self.unit.read_bytes(), self.old_unit)
        self.assertEqual((self.active, self.enabled), (active, enabled))
        self.assertFalse(list(self.root.glob('stage-*')))
        self.assertFalse(list(self.root.glob('link-*')))

    def test_preparation_failure_never_interrupts_old_runtime(self):
        with patch.object(deploy, 'provision_pki', side_effect=ValueError('TRAFFIC_PKI_FAILED')):
            self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_PKI_FAILED')
        self.assert_previous()
        self.assertFalse(any(args[1] in ('stop', 'start', 'restart', 'enable', 'disable', 'daemon-reload')
            for args in self.commands if args[0] == 'systemctl'))

    def test_failed_restart_restores_old_artifacts_and_service(self):
        self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_SERVICE_COMMAND_FAILED')
        self.assert_previous()
        self.assertTrue((self.root / 'versions' / self.payload['bundle_sha256']).is_dir())

    def test_post_apply_failure_restores_old_inactive_disabled_state(self):
        self.active = self.enabled = False
        self.fail = None
        self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_POST_APPLY_VERIFICATION_FAILED')
        self.assert_previous(False, False)
        self.assertNotIn(('systemctl', 'start', deploy.SERVICE), self.commands)

    def test_failed_recovery_has_distinct_error(self):
        self.fail = 'start'
        self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_ROLLBACK_VERIFICATION_FAILED')
        self.assertFalse(self.active)

    def test_changed_previous_manifest_cannot_verify_recovery(self):
        self.fail = None
        def changed_on_start(*args, **kwargs):
            value = self.command(*args, **kwargs)
            if args[:2] == ('systemctl', 'start'):
                (self.old / 'runtime-manifest.json').write_bytes(b'changed during recovery')
            return value
        with patch.object(deploy, 'command', side_effect=changed_on_start):
            self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_ROLLBACK_VERIFICATION_FAILED')

    def test_first_install_failure_removes_activation_but_preserves_failed_version(self):
        self.active = self.enabled = False
        self.unit.unlink()
        (self.root / 'current').unlink()
        self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_SERVICE_COMMAND_FAILED')
        self.assertFalse(self.unit.exists())
        self.assertFalse((self.root / 'current').is_symlink())
        self.assertFalse(self.active or self.enabled)
        self.assertTrue((self.root / 'versions' / self.payload['bundle_sha256']).is_dir())

    def test_unverified_old_active_runtime_blocks_before_activation(self):
        self.valid_old = False
        self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_PREVIOUS_RUNTIME_UNVERIFIED')
        self.assert_previous()

    def test_concurrent_installer_is_blocked(self):
        import fcntl
        with (self.root / 'operation.lock').open('w') as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(deploy.invoke(self.payload)['error'], 'TRAFFIC_OPERATION_ACTIVE')
        self.assert_previous()

    def test_previous_version_uses_its_verified_listener_configuration(self):
        source = b'old source'
        (self.old / 'old.py').write_bytes(source)
        configuration = json.dumps({'port':42501, 'proxy_port':42502, 'control_port':42503,
            'application_ports':{'tls':42512}}).encode()
        (self.old / 'agent-private.json').write_bytes(configuration)
        pki_hashes = self.pki(self.old)
        (self.old / 'dependencies').mkdir()
        (self.old / 'dependencies' / 'fixture').write_bytes(b'old dependency')
        payload = {'hashes':{'old.py':deploy.digest(source)}, 'config_sha256':deploy.digest(configuration),
                   'bundle_sha256':'a'*64}
        manifest = {**payload, 'pki_hashes':pki_hashes, 'dependency_hashes':{'fixture':deploy.digest(b'old dependency')}}
        (self.old / 'runtime-manifest.json').write_text(json.dumps(manifest))
        self.active = False
        def listeners(*args, **kwargs):
            if args[0]=='ss':
                ports=(42501,42502,42503,42512) if '-lnt' in args else (42501,42502)
                return '\n'.join(f'LISTEN 0 128 0.0.0.0:{port} 0.0.0.0:*' for port in ports)
            return self.command(*args, **kwargs)
        with patch.object(deploy,'command',side_effect=listeners):
            observed=actual_state(payload)
        self.assertTrue(observed['hashes_match'] and observed['listeners'])
        self.assertEqual(observed['tcp_ports'],[42501,42502,42503,42512])
        self.assertNotIn(42532,observed['tcp_ports'])


if __name__ == '__main__':
    unittest.main()
