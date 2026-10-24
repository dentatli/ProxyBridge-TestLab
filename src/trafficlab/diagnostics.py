"""Bounded failure evidence: endpoints and codes, never packet contents."""
from __future__ import annotations


def datagram_source(result, actual, expected, *, phase):
    if tuple(actual[:2]) == tuple(expected[:2]):
        return True
    result['unexpected_source_packets'] = result.get('unexpected_source_packets', 0) + 1
    result.setdefault('first_source_mismatch', {'expected': list(expected[:2]), 'actual': list(actual[:2]), 'phase': phase})
    return False


def require_datagram_source(result, actual, expected, code, *, phase):
    if not datagram_source(result, actual, expected, phase=phase):
        raise ValueError(code)


def invalid_datagram(result, error):
    known = {'TRAFFIC_AUTHENTICATION_FAILED', 'TRAFFIC_DATAGRAM_RUN_MISMATCH',
             'TRAFFIC_DATAGRAM_FLOW_MISMATCH', 'TRAFFIC_DATAGRAM_PAYLOAD_MISMATCH'}
    reason = str(error) if isinstance(error, ValueError) and str(error) in known else 'TRAFFIC_DATAGRAM_MALFORMED'
    counts = result.setdefault('invalid_reasons', {})
    counts[reason] = counts.get(reason, 0) + 1
