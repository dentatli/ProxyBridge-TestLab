from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parent
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))
VENDOR_ROOT = SCRIPT_ROOT / "_vendor"
if VENDOR_ROOT.is_dir() and str(VENDOR_ROOT) not in sys.path:
    sys.path.insert(0, str(VENDOR_ROOT))

from model import WorkerContractError, load_plan, validate_evidence_record
from registry import load_registry, resolve_plugin


def _parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True, allow_abbrev=False)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--output-jsonl", required=True)
    parser.add_argument("--manifest", default=str(SCRIPT_ROOT / "plugins" / "manifest.json"))
    return parser.parse_args()


def _write_jsonl_exclusive(path: Path, records: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = b"".join(
        (json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        for record in records
    )
    try:
        with path.open("xb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError as exc:
        raise WorkerContractError("OUTPUT_ALREADY_EXISTS") from exc
    except OSError as exc:
        if path.exists():
            try:
                path.unlink()
            except OSError:
                pass
        raise WorkerContractError("OUTPUT_WRITE_FAILED") from exc


def main() -> int:
    try:
        arguments = _parse_arguments()
        plan = load_plan(Path(arguments.plan).resolve())
        registry = load_registry(Path(arguments.manifest).resolve())
        registration = resolve_plugin(plan, registry)
        records = registration.runner(plan)
        if not records:
            raise WorkerContractError("PLUGIN_RETURNED_NO_EVIDENCE")
        for record in records:
            validate_evidence_record(record, plan, set(registration.required_fields))
        _write_jsonl_exclusive(Path(arguments.output_jsonl).resolve(), records)
        print(f"PROTOCOL_WORKER_OK records={len(records)}")
        return 0
    except WorkerContractError as exc:
        print(f"PROTOCOL_WORKER_ERROR {exc}", file=sys.stderr)
        return 20
    except Exception:
        print("PROTOCOL_WORKER_ERROR UNEXPECTED_FAILURE", file=sys.stderr)
        return 21


if __name__ == "__main__":
    raise SystemExit(main())
