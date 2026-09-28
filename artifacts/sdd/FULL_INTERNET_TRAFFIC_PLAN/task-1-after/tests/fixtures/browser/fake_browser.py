from __future__ import annotations

import hashlib
import json
import os
import sys
import time


def _argument_value(prefix: str) -> str:
    matches = [argument[len(prefix):] for argument in sys.argv[1:] if argument.startswith(prefix)]
    if len(matches) != 1 or not matches[0]:
        raise SystemExit(21)
    return matches[0]


def main() -> int:
    arguments = sys.argv[1:]
    if any(argument.startswith("--testlab-") for argument in arguments):
        return 20
    _argument_value("--headless=")
    if "--dump-dom" not in arguments:
        return 21
    _argument_value("--virtual-time-budget=")
    _argument_value("--user-data-dir=")
    if not arguments[-1].startswith(("http://", "https://")):
        return 21

    mode = os.environ.get("PB_BROWSER_FIXTURE_MODE", "success")
    if mode == "exit-before-path":
        return 0

    payload = b"browser-canary-payload"
    marker: object = {
        "dom_marker": "PB_TESTLAB_BROWSER_READY",
        "negotiated_protocol": "h2",
        "response_status": 200,
        "content_sha256": hashlib.sha256(payload).hexdigest(),
    }
    if mode == "malformed-marker":
        rendered = "not-json"
    else:
        if mode == "wrong-content-hash":
            marker["content_sha256"] = "0" * 64
        rendered = json.dumps(marker, separators=(",", ":"))
    script = '<script id="proxybridge-testlab-browser-result" type="application/json">' + rendered + "</script>"
    if mode == "multiple-markers":
        script += script
    print("<html><body>" + script + "</body></html>")
    sys.stdout.flush()
    time.sleep(0.2)
    return 0


raise SystemExit(main())
