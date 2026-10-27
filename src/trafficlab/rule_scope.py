"""Exact destination-port scope shared by persistent and CLI product rules."""
from __future__ import annotations
from typing import Any


def port_filter(ports: int | tuple[int, ...]) -> str:
    values = (ports,) if type(ports) is int else ports
    if not isinstance(values, tuple) or not 1 <= len(values) <= 32 or any(
            type(port) is not int or not 1 <= port <= 65535 for port in values):
        raise ValueError('TRAFFIC_RULE_PORTS_INVALID')
    return ','.join(map(str, sorted(set(values))))


def case_ports(specification: dict[str, Any], transport_port: int) -> tuple[int, ...]:
    from trafficlab.application_wire import APPLICATION_PORTS
    if specification.get('id') == 'soak':
        from trafficlab.endurance import APPLICATIONS
        ports = (transport_port, *(APPLICATION_PORTS[name] for name in APPLICATIONS))
    elif specification.get('application'):
        ports = (APPLICATION_PORTS[specification['application']],)
    else:
        ports = (transport_port,)
    return tuple(map(int, port_filter(ports).split(',')))
