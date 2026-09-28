"""Recover hash-verified task baselines and mechanically generate the review diff."""
import difflib
import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ART = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def variants(data):
    yield data
    lf = data.replace(b"\r\n", b"\n")
    yield lf
    yield lf.replace(b"\n", b"\r\n")


def main():
    recovered = []
    missing = []
    for entry in (ART / "task-3a-before/manifest.sha256").read_text().splitlines():
        expected, relative = entry.split("  ", 1)
        if relative.startswith("artifacts/"):
            continue  # historical ledger is not implementation scope
        current = (ROOT / relative).read_bytes()
        candidates = [("current unchanged", current)]
        # Reverse only this slice's additions; acceptance still requires the
        # pre-existing exact byte hash, never a guessed baseline.
        text = current.decode("utf-8-sig").replace("\r\n", "\n")
        if relative == "config/server-protocol-ports.json":
            candidates.append(("hash-verified reversal of reserved-port addition", text.replace('    "negative_proxy_unavailable": 42704,\n', '').encode()))
        if relative.endswith("/ServerProtocolPortCatalog.cs"):
            candidates.append(("hash-verified reversal of required-name addition", text.replace('"negative_proxy_unavailable", ', '').encode()))
        if relative == "tests/fixtures/failure-control/contract_test.py":
            original = re.sub(r"from negative_proxy import \(.*?\)\n", "", text, flags=re.S)
            prefix = original[:original.index("NEGATIVE_PROXY_CONFIG =")].rstrip("\n")
            suffix = original[original.index('print("PASS: offline failure-control contract")'):]
            for blank_count in range(1, 5):
                candidates.append(("hash-verified reversal of negative-proxy fixture additions", (prefix + "\n" * blank_count + suffix).encode()))
        for folder in sorted(ART.glob("task-*-*")):
            candidate = folder / relative
            if folder.is_dir() and candidate.is_file():
                candidates.append((str(candidate.relative_to(ROOT)), candidate.read_bytes()))
        blob = subprocess.run(["git", "show", "HEAD:" + relative], cwd=ROOT, capture_output=True)
        if blob.returncode == 0:
            candidates.append(("HEAD blob", blob.stdout))
        baseline = None
        source = "absent"
        if expected == "ABSENT":
            baseline = b""
        else:
            for label, data in candidates:
                for variant in variants(data):
                    if digest(variant) == expected:
                        baseline, source = variant, label
                        break
                if baseline is not None:
                    break
        if baseline is None:
            missing.append(relative)
        else:
            recovered.append((relative, baseline, current, source, expected))
    if missing:
        raise SystemExit("BASELINE_UNAVAILABLE: " + ", ".join(missing))
    output = []
    provenance = ["# Task 3a review baseline provenance", "", "Every baseline matches task-3a-before/manifest.sha256 (byte SHA-256).",
                  "Diff text normalizes CRLF to LF. Historical progress.md is excluded from code scope.", ""]
    for relative, before, after, source, expected in recovered:
        provenance.append(f"- `{relative}`: {source}; baseline `{expected}`.")
        old = before.decode("utf-8-sig").splitlines(keepends=True)
        new = after.decode("utf-8-sig").splitlines(keepends=True)
        old = [line.replace("\r\n", "\n") for line in old]
        new = [line.replace("\r\n", "\n") for line in new]
        if old != new:
            output.append(f"diff --git a/{relative} b/{relative}\n")
            if expected == "ABSENT":
                output.append("new file mode 100644\n")
            output.extend(difflib.unified_diff(old, new, fromfile="/dev/null" if expected == "ABSENT" else "a/" + relative, tofile="b/" + relative))
    (ART / "task-3a-review.diff").write_text("".join(output), encoding="utf-8", newline="\n")
    (ART / "task-3a-review-provenance.md").write_text("\n".join(provenance) + "\n", encoding="utf-8", newline="\n")
    print(f"REVIEW_DIFF_GENERATED: {len(recovered)} scoped files; baselines verified")


if __name__ == "__main__":
    main()
