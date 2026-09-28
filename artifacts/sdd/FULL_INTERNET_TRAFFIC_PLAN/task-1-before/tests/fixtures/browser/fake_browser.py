from __future__ import annotations

import hashlib
import json
import sys


payload = b"browser-canary-payload"
marker = json.dumps({
    "dom_marker": "PB_TESTLAB_BROWSER_READY",
    "browser_identity": "Fake Chromium",
    "browser_version": "1.0.0",
    "negotiated_protocol": "h2",
    "response_status": 200,
    "content_sha256": hashlib.sha256(payload).hexdigest(),
}, separators=(",", ":"))
print(f'<html><body><script id="proxybridge-testlab-browser-result" type="application/json">{marker}</script></body></html>')
sys.stdout.flush()
