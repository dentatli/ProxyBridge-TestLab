from __future__ import annotations

from pathlib import Path
import sys


repository_root = Path(__file__).resolve().parents[3]
worker_root = repository_root / "src" / "protocol_worker"
sys.path.insert(0, str(worker_root))

from registry import LAZY_RUNNERS, load_registry  # noqa: E402


manifest_path = Path(sys.argv[1]).resolve()
registrations = load_registry(manifest_path)
registration = registrations.get("browser-worker")

assert LAZY_RUNNERS.get("browser-worker") == ("plugins.browser", "run_browser")
assert registration is not None
assert registration.evidence_profile_id == "browser-session"
assert registration.network_access is True
assert callable(registration.runner)

print("PASS: browser worker lazy registry")
