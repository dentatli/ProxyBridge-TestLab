from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def _argument_value(arguments: list[str], prefix: str) -> str:
    matches = [argument[len(prefix):] for argument in arguments if argument.startswith(prefix)]
    if len(matches) != 1 or not matches[0]:
        raise SystemExit(21)
    return matches[0]


def main() -> int:
    arguments = sys.argv[1:]
    fixed = {
        "--headless=new",
        "--disable-background-networking",
        "--disable-sync",
        "--no-first-run",
        "--no-default-browser-check",
        "--dump-dom",
    }
    if len(arguments) != len(fixed) + 3 or set(argument for argument in arguments if argument in fixed) != fixed:
        return 21
    if arguments.count("--headless=new") != 1 or arguments.count("--dump-dom") != 1:
        return 21
    budget = _argument_value(arguments, "--virtual-time-budget=")
    if not budget.isdecimal() or not 0 < int(budget) <= 1_000:
        return 21
    user_data_dir = Path(_argument_value(arguments, "--user-data-dir="))
    if not user_data_dir.is_dir() or any(user_data_dir.iterdir()):
        return 21
    if Path.cwd().name != "downloads-" + os.environ.get("PB_BROWSER_FIXTURE_MODE", "success"):
        return 21
    if sum(argument.startswith(("http://", "https://")) for argument in arguments) != 1 or not arguments[-1].startswith(("http://", "https://")):
        return 21
    if any(argument.startswith("--testlab-") for argument in arguments):
        return 20

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
    if mode == "late-child":
        time.sleep(0.2)
        child_environment = dict(os.environ)
        child_environment.pop("PYTHONPATH", None)
        subprocess.Popen([sys.executable, "-c", "import time; time.sleep(1.0)"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=child_environment)
        return 0
    time.sleep(0.2)
    return 0


raise SystemExit(main())
