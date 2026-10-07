"""Recover observed terminal rows with pyte; never claim a complete event log."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys

PACKAGE_ROOT = Path(__file__).resolve().parent.parent / "bin/terminal-decoder/packages"
MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_OBSERVATIONS = 10000
COLUMNS, ROWS = 240, 80  # The fixed geometry in pb_console_host.c.


def decode(path: Path) -> dict:
    if path.stat().st_size > MAX_INPUT_BYTES:
        raise ValueError("TERMINAL_INPUT_LIMIT")
    data = path.read_bytes()
    if len(data) > MAX_INPUT_BYTES:
        raise ValueError("TERMINAL_INPUT_LIMIT")
    text = data.decode("utf-8", errors="strict")
    sys.path.insert(0, str(PACKAGE_ROOT))
    versions = {name: importlib.metadata.version(name) for name in ("pyte", "wcwidth")}
    if versions != {"pyte": "0.8.2", "wcwidth": "0.2.13"}:
        raise ValueError("TERMINAL_DECODER_VERSION_MISMATCH")
    import pyte

    class ObservedScreen(pyte.Screen):
        def __init__(self):
            self.observations = []
            self.seen = set()
            self.unsupported = []
            super().__init__(COLUMNS, ROWS)

        def remember(self, line):
            line = line.rstrip()
            if line and line not in self.seen:
                if len(self.observations) >= MAX_OBSERVATIONS:
                    raise ValueError("TERMINAL_OBSERVATION_LIMIT")
                self.seen.add(line)
                self.observations.append(line)

        def current_row(self):
            if hasattr(self, "cursor"):
                row = self.buffer.get(self.cursor.y, {})
                self.remember("".join(row[x].data if x in row else " " for x in range(self.columns)))

        def snapshot(self):
            if hasattr(self, "cursor") and hasattr(self, "mode"):
                for line in self.display:
                    self.remember(line)

        def index(self):
            # Retain visible rows before scrolling; screen history has a limit.
            self.current_row()
            super().index()

        def cursor_position(self, line=None, column=None):
            self.current_row()
            super().cursor_position(line, column)

        def erase_in_display(self, how=0, *args, **kwargs):
            self.snapshot()
            super().erase_in_display(how, *args, **kwargs)

        def reset(self):
            self.snapshot()
            super().reset()

        def debug(self, *args, **kwargs):
            if len(self.unsupported) < 32:
                self.unsupported.append(str(args)[:160])

    screen = ObservedScreen()
    stream = pyte.Stream(screen)
    for offset in range(0, len(text), 65536):
        stream.feed(text[offset:offset + 65536])
    screen.snapshot()
    return {
        "schema_version": 1,
        "status": "DECODED_OBSERVATIONS",
        "decoder_versions": versions,
        "input_sha256": hashlib.sha256(data).hexdigest(),
        "terminal_columns": COLUMNS,
        "terminal_rows": ROWS,
        "capture_scope": "rendered-terminal-observations",
        "source_event_stream_complete": False,
        "source_event_order_preserved": False,
        "observations_deduplicated": True,
        "unsupported_events": screen.unsupported,
        "observed_lines": screen.observations,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = decode(args.input)
    except Exception as error:
        # Avoid exposing private paths/terminal content through error strings.
        reason = str(error) if isinstance(error, ValueError) else type(error).__name__
        result = {"schema_version": 1, "status": "DECODE_FAILED", "reason": reason,
                  "source_event_stream_complete": False, "observed_lines": []}
        print(json.dumps(result, ensure_ascii=True))
        return 1
    print(json.dumps(result, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
