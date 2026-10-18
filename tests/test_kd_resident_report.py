"""Receipt fixtures only: do not open the device or start any service."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_kd_session_report import resident_cleanup_confirmed


class ResidentReceiptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'proxy').mkdir()
        self.mode = dict(driver_lifecycle='resident-disabled', resident_disable_observed=True,
                         driver_stop_observed=False)
        self.receipt = dict(schema_version=1, session_id='fixture-session', operation='PBDRV_IOCTL_DISABLE',
                            ioctl='0x22a00c', device=r'\\.\ProxyBridgeDrv', completed=True,
                            service_state='Running', driver_unloaded=False)
        for phase in ('before', 'after'):
            self.write(f'resident-disable-{phase}', dict(self.receipt, phase=phase))
            self.write(f'interception-{phase}', dict(wfp=dict(status='SERVICE_FILE_VERIFIED', service_state='Running'),
                       current_driver_preparation_allowed=True))
            self.write(f'loaded-drivers-{phase}', dict(query_complete=True, selected_driver_loaded=True,
                       known_interception_drivers=['ProxyBridgeDrv.sys']))
            self.write(f'product-processes-{phase}', [])

    def write(self, name, value):
        (self.root / 'proxy' / (name + '.json')).write_text(json.dumps(value), encoding='utf-8')

    def test_valid_receipts_require_loaded_disabled_not_unloaded(self):
        self.assertTrue(resident_cleanup_confirmed(self.root, self.mode))
        self.assertFalse(resident_cleanup_confirmed(self.root, dict(self.mode, driver_stop_observed=True)))

    def test_failed_disable_wrong_session_or_enable_is_rejected(self):
        for change in (dict(completed=False), dict(session_id='another'), dict(ioctl='0x22a008'),
                       dict(operation='PBDRV_IOCTL_ENABLE'), dict(service_state='Stopped')):
            with self.subTest(change=change):
                self.write('resident-disable-after', dict(self.receipt, phase='after', **change))
                self.assertFalse(resident_cleanup_confirmed(self.root, self.mode))

    def test_missing_receipt_is_not_accepted(self):
        (self.root / 'proxy/resident-disable-after.json').unlink()
        with self.assertRaises(OSError):
            resident_cleanup_confirmed(self.root, self.mode)

    def test_remaining_product_or_unloaded_driver_is_rejected(self):
        self.write('product-processes-after', [dict(pid=123)])
        self.assertFalse(resident_cleanup_confirmed(self.root, self.mode))
        self.write('product-processes-after', [])
        self.write('loaded-drivers-after', dict(query_complete=True, selected_driver_loaded=False,
                   known_interception_drivers=[]))
        self.assertFalse(resident_cleanup_confirmed(self.root, self.mode))


if __name__ == '__main__':
    unittest.main()
