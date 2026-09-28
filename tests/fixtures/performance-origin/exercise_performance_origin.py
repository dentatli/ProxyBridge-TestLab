import json
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from performance_origin import PerformanceOrigin, PerformanceOriginError


class FixtureAdapter:
    def __init__(self, snapshots):
        self._snapshots = list(snapshots)
        self._index = 0

    def snapshot(self):
        value = self._snapshots[self._index]
        self._index += 1
        return value


def rejected(action):
    try:
        action()
    except PerformanceOriginError as error:
        return error.code
    raise AssertionError("fixture action was accepted")


def clone(value):
    return json.loads(json.dumps(value))


fixture = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
request = fixture["request"]
snapshots = fixture["snapshots"]
origin = PerformanceOrigin(FixtureAdapter(snapshots))
records = [origin.begin(request)]
records.append(origin.sample(request["workload_id"], request["window_id"]))
records.append(origin.sample(request["workload_id"], request["window_id"]))
records.append(origin.end(request["workload_id"], request["window_id"]))

duplicate = PerformanceOrigin(FixtureAdapter([snapshots[0]]))
duplicate.begin(request)

clock = clone(snapshots[1])
clock["monotonic_ns"] = snapshots[0]["monotonic_ns"]
clock_origin = PerformanceOrigin(FixtureAdapter([snapshots[0], clock]))
clock_origin.begin(request)

identity = clone(snapshots[1])
identity["peer_identity"]["port"] = 41002
identity_origin = PerformanceOrigin(FixtureAdapter([snapshots[0], identity]))
identity_origin.begin(request)

regression = clone(snapshots[1])
regression["tcp_bytes"] = 999
regression_origin = PerformanceOrigin(FixtureAdapter([snapshots[0], regression]))
regression_origin.begin(request)

incomplete_origin = PerformanceOrigin(FixtureAdapter(snapshots))
incomplete_origin.begin(request)
incomplete_origin.sample(request["workload_id"], request["window_id"])

result = {
    "records": records,
    "errors": {
        "duplicate_begin": rejected(lambda: duplicate.begin(request)),
        "window_mismatch": rejected(lambda: origin.sample(request["workload_id"], "wrong-window")),
        "clock": rejected(lambda: clock_origin.sample(request["workload_id"], request["window_id"])),
        "identity": rejected(lambda: identity_origin.sample(request["workload_id"], request["window_id"])),
        "counter": rejected(lambda: regression_origin.sample(request["workload_id"], request["window_id"])),
        "incomplete": rejected(lambda: incomplete_origin.end(request["workload_id"], request["window_id"])),
        "duplicate_end": rejected(lambda: origin.end(request["workload_id"], request["window_id"]))
    }
}
print(json.dumps(result, separators=(",", ":")))
