"""Loss-gated TCPIP event inventory. No root-cause or per-connection coverage claim."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

PROVIDER = '2f07e2ee-15db-40f1-90ef-9d7ba282188a'
NS = {'e': 'http://schemas.microsoft.com/win/2004/08/events/event'}


def evaluate(directory):
    state = json.loads((directory / 'capture-state.json').read_text(encoding='utf-8-sig'))
    errors = []
    if (any(state.get(k) is not True for k in ('Started', 'Stopped', 'Exported'))
            or state.get('Error') or state.get('Provider', '').strip('{}').lower() != PROVIDER
            or state.get('Keywords') != '0x2080' or state.get('Level') != 5):
        errors.append('ETW_CAPTURE_STATE_INVALID')
    counters = state.get('Counters') or {}
    if any(counters.get(k) != 0 for k in ('ControlStatus', 'EventsLost', 'LogBuffersLost', 'RealTimeBuffersLost')):
        errors.append('ETW_LOSS_OR_FINAL_STATISTICS_UNKNOWN')
    counts, targets, processing = Counter(), [], Counter()
    headers = []
    xml = directory / 'events.xml'
    for _, event in ET.iterparse(xml, events=('end',)):
        if event.tag != '{' + NS['e'] + '}Event':
            continue
        system = event.find('e:System', NS)
        provider = system.find('e:Provider', NS).get('Guid', '').strip('{}').lower()
        event_id = int(system.findtext('e:EventID', namespaces=NS))
        data = {v.get('Name'): (v.text or '').strip() for v in event.findall('e:EventData/e:Data', NS)}
        if provider == PROVIDER:
            counts[event_id] += 1
            if event.find('e:ProcessingErrorData', NS) is not None:
                processing[event_id] += 1
            if event_id in (1315, 1553):
                targets.append(dict(event_id=event_id, version=system.findtext('e:Version', namespaces=NS),
                    time=system.find('e:TimeCreated', NS).get('SystemTime'), data=data,
                    processing_error=event.find('e:ProcessingErrorData', NS) is not None))
        elif event_id == 0 and system.findtext('e:Opcode', namespaces=NS) == '0':
            headers.append(data)
        event.clear()
    if len(headers) != 1 or any(int(headers[0].get(k, '-1'), 0) != 0 for k in ('EventsLost', 'BuffersLost')):
        errors.append('ETW_HEADER_LOSS_OR_HEADER_UNKNOWN')
    if processing:
        errors.append('TCPIP_EVENT_DECODING_INCOMPLETE')
    return dict(schema_version=1, status='ETW_CAPTURE_EXPORTED_REVIEW_PENDING' if not errors else 'ETW_CAPTURE_INCOMPLETE',
        errors=errors, final_counters=counters, event_counts=dict(counts),
        tcpip_processing_errors=dict(processing), redirect_events=targets,
        source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in (directory / 'capture-state.json', directory / 'tcpip.etl', xml)},
        connection_correlation_verified=False, root_cause_proven=False,
        limitation='Event inventory only; absent events do not prove an absent kernel path. CodePath is uninterpreted.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-directory', type=Path, required=True)
    directory = parser.parse_args().capture_directory
    result = evaluate(directory)
    (directory / 'etw-report.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('status', 'errors', 'event_counts')}))
    return bool(result['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
