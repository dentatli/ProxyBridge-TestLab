"""Offline ETW fixtures: loss/decoding gates, no provider or network activity."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pb_etw_redirect_report import evaluate, PROVIDER


class EtwReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = dict(Started=True, Stopped=True, Exported=True, Error='',
                          Provider=PROVIDER, Keywords='0x2080', Level=5,
                          Counters=dict(ControlStatus=0, EventsLost=0, LogBuffersLost=0, RealTimeBuffersLost=0))
        (self.root / 'tcpip.etl').write_bytes(b'fixture')

    def report(self, extra='', header_loss='0'):
        (self.root / 'capture-state.json').write_text(json.dumps(self.state))
        (self.root / 'events.xml').write_text('''<Events><Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
<System><Provider Guid="{9e814aad-3204-11d2-9a82-006008a86939}"/><EventID>0</EventID><Opcode>0</Opcode></System>
<EventData><Data Name="EventsLost">''' + header_loss + '''</Data><Data Name="BuffersLost">0</Data></EventData></Event>''' + extra + '</Events>')
        return evaluate(self.root)

    def test_clean_empty_capture_does_not_claim_coverage(self):
        report = self.report()
        self.assertFalse(report['errors'])
        self.assertFalse(report['connection_correlation_verified'])
        self.assertFalse(report['root_cause_proven'])

    def test_stop_loss_and_missing_counters_fail_closed(self):
        self.state['Counters']['EventsLost'] = 1
        self.assertIn('ETW_LOSS_OR_FINAL_STATISTICS_UNKNOWN', self.report()['errors'])
        self.state['Counters'] = None
        self.assertIn('ETW_LOSS_OR_FINAL_STATISTICS_UNKNOWN', self.report()['errors'])

    def test_header_loss_rejected_even_when_control_counters_zero(self):
        self.assertIn('ETW_HEADER_LOSS_OR_HEADER_UNKNOWN', self.report(header_loss='1')['errors'])

    def test_target_decode_error_is_not_silent_absence(self):
        event = '''<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><System>
<Provider Guid="{''' + PROVIDER + '''}"/><EventID>1553</EventID><Version>0</Version><TimeCreated SystemTime="fixture"/>
</System><ProcessingErrorData><ErrorCode>15005</ErrorCode></ProcessingErrorData></Event>'''
        report = self.report(event)
        self.assertEqual(report['event_counts'][1553], 1)
        self.assertIn('TCPIP_EVENT_DECODING_INCOMPLETE', report['errors'])


if __name__ == '__main__':
    unittest.main()
