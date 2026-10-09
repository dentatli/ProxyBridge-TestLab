"""Own versioned Ubuntu 22.04 service. SSH stdin supplies private configuration, never argv."""
from __future__ import annotations

import base64
import hashlib
import ipaddress
import json
import os
import pwd
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path("/opt/proxybridge-testlab-traffic")
UNIT = Path("/etc/systemd/system/proxybridge-testlab-traffic.service")
SERVICE = "proxybridge-testlab-traffic.service"
PORTS = {42501, 42502, 42503}


def command(*args: str, required: bool = True) -> str:
    result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20)
    if required and result.returncode:
        raise ValueError("TRAFFIC_SERVICE_COMMAND_FAILED")
    return result.stdout.strip()


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def platform() -> None:
    release = dict(line.split("=", 1) for line in Path("/etc/os-release").read_text().splitlines() if "=" in line)
    if os.getuid() != 0 or release.get("ID", "").strip('"') != "ubuntu" or release.get("VERSION_ID", "").strip('"') != "22.04":
        raise ValueError("TRAFFIC_REQUIRES_ROOT_UBUNTU_22_04")
    if not Path("/run/systemd/system").is_dir():
        raise ValueError("TRAFFIC_REQUIRES_SYSTEMD")
    for path in (ROOT, ROOT / "versions", UNIT):
        if path.is_symlink():
            raise ValueError("TRAFFIC_INSTALL_PATH_SYMLINK")


def state(payload: dict[str, Any]) -> dict[str, Any]:
    platform()
    current = ROOT / "current"
    matches = False
    if current.is_symlink():
        version = current.resolve(strict=True)
        if version.parent == ROOT / "versions" and version.is_dir():
            matches = all((version / name).is_file() and not (version / name).is_symlink() and digest((version / name).read_bytes()) == expected
                          for name, expected in payload["hashes"].items())
            config = version / "agent-private.json"
            matches = matches and config.is_file() and digest(config.read_bytes()) == payload["config_sha256"]
            manifest = version / "runtime-manifest.json"
            matches = matches and manifest.is_file() and json.loads(manifest.read_bytes()) == {
                "hashes": payload["hashes"], "config_sha256": payload["config_sha256"], "bundle_sha256": payload["bundle_sha256"]}
    active = command("systemctl", "is-active", SERVICE, required=False) == "active"
    enabled = command("systemctl", "is-enabled", SERVICE, required=False) == "enabled"
    tcp = command("ss", "-H", "-lnt")
    udp = command("ss", "-H", "-lnu")
    def listening(text: str, port: int) -> bool:
        return any(re.search(r":" + str(port) + r"(?:\s|$)", line) for line in text.splitlines())
    listeners = all(listening(tcp, port) for port in PORTS) and all(listening(udp, port) for port in (42501, 42502))
    if matches and active:
        pid = command("systemctl", "show", SERVICE, "--property=MainPID", "--value")
        argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if pid.isdecimal() and pid != "0" else []
        matches = str(version / "agent-private.json").encode() in argv
    return {"state": "READY" if matches and active and enabled and listeners else "SETUP_REQUIRED",
            "hashes_match": matches, "service_active": active, "service_enabled": enabled, "listeners": listeners,
            "bundle_sha256": payload["bundle_sha256"], "verified_ubuntu": "22.04", "tcp_ports": sorted(PORTS), "udp_ports": [42501, 42502]}


def apply(payload: dict[str, Any]) -> dict[str, Any]:
    before = state(payload)
    if before["state"] == "READY":
        return {**before, "applied": False}
    for name in payload["sources"]:
        if not re.fullmatch(r"(?:trafficlab/[a-z_]+\.py|traffic-workloads\.json)", name):
            raise ValueError("TRAFFIC_ARTIFACT_NAME_INVALID")
    if any(digest(base64.b64decode(encoded, validate=True)) != payload["hashes"][name] for name, encoded in payload["sources"].items()):
        raise ValueError("TRAFFIC_ARTIFACT_HASH_MISMATCH")
    if digest(base64.b64decode(payload["configuration"], validate=True)) != payload["config_sha256"]:
        raise ValueError("TRAFFIC_CONFIGURATION_HASH_MISMATCH")
    if not re.fullmatch("[a-f0-9]{64}", payload["bundle_sha256"]):
        raise ValueError("TRAFFIC_BUNDLE_INVALID")
    own_active = command("systemctl", "is-active", SERVICE, required=False) == "active"
    occupied = command("ss", "-H", "-lntup")
    for line in occupied.splitlines():
        if any(re.search(r":" + str(port) + r"(?:\s|$)", line) for port in PORTS):
            # Do not assume any listener on a reserved port belongs to this service.
            pid_match = re.search(r"pid=(\d+)", line)
            if not own_active or pid_match is None or SERVICE not in Path(f"/proc/{pid_match[1]}/cgroup").read_text():
                raise ValueError("TRAFFIC_PORT_CONFLICT")
    if shutil.which("ufw") and "Status: active" in command("ufw", "status"):
        # Existing networking policy is not silently widened by a new runtime installer.
        raise ValueError("TRAFFIC_FIREWALL_REVIEW_REQUIRED")
    try:
        account = pwd.getpwnam("proxybridge-testlab")
    except KeyError:
        command("useradd", "--system", "--home", "/nonexistent", "--shell", "/usr/sbin/nologin", "proxybridge-testlab")
        account = pwd.getpwnam("proxybridge-testlab")
    ROOT.mkdir(mode=0o755, exist_ok=True)
    (ROOT / "versions").mkdir(mode=0o755, exist_ok=True)
    version = ROOT / "versions" / payload["bundle_sha256"]
    if version.exists() and version.is_symlink():
        raise ValueError("TRAFFIC_VERSION_SYMLINK")
    source_ip = os.environ.get("SSH_CONNECTION", "").split()[0]
    source_ip = str(ipaddress.ip_address(source_ip))
    old_unit = UNIT.read_bytes() if UNIT.exists() else None
    old_enabled = command("systemctl", "is-enabled", SERVICE, required=False) == "enabled"
    old_link = os.readlink(ROOT / "current") if (ROOT / "current").is_symlink() else None
    if (ROOT / "current").exists() and old_link is None:
        raise ValueError("TRAFFIC_CURRENT_PATH_NOT_OWN_LINK")
    if old_unit is not None and b"# ProxyBridge-TestLab owned traffic runtime" not in old_unit:
        raise ValueError("TRAFFIC_SERVICE_NOT_OWNED")
    unit = f"""# ProxyBridge-TestLab owned traffic runtime
[Unit]
Description=ProxyBridge TestLab authenticated traffic origin and proxy
After=network-online.target
[Service]
Type=simple
User=proxybridge-testlab
Group=proxybridge-testlab
WorkingDirectory={version}
ExecStart=/usr/bin/python3 -B -m trafficlab.agent --config {version}/agent-private.json
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
LimitNOFILE=16384
IPAddressDeny=any
IPAddressAllow=localhost
IPAddressAllow={source_ip}
[Install]
WantedBy=multi-user.target
""".encode()
    stage = Path(tempfile.mkdtemp(prefix="stage-", dir=ROOT))
    try:
        for name, encoded in payload["sources"].items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(base64.b64decode(encoded, validate=True))
        config = stage / "agent-private.json"
        config.write_bytes(base64.b64decode(payload["configuration"], validate=True))
        (stage / "runtime-manifest.json").write_text(json.dumps({"hashes":payload["hashes"], "config_sha256":payload["config_sha256"], "bundle_sha256":payload["bundle_sha256"]},sort_keys=True))
        for folder, _dirs, files in os.walk(stage):
            os.chmod(folder, 0o755)
            for filename in files:
                file = Path(folder) / filename
                os.chmod(file, 0o640 if file == config else 0o644)
                os.chown(file, 0, account.pw_gid)
        if version.exists():
            # Matching versions are immutable; repair uses a fresh owned directory, preserving the old evidence.
            version = ROOT / "versions" / (payload["bundle_sha256"] + "-" + stage.name)
            unit = unit.replace(str(ROOT / "versions" / payload["bundle_sha256"]).encode(), str(version).encode())
        stage.rename(version)
        (ROOT / "next").symlink_to(version)
        (ROOT / "next").replace(ROOT / "current")
        UNIT.write_bytes(unit)
        command("systemctl", "daemon-reload")
        command("systemctl", "enable", SERVICE)
        command("systemctl", "restart", SERVICE)
        import time
        for _ in range(30):
            after = state(payload)
            if after["state"] == "READY":
                return {**after, "applied": True, "rollback_attempted": False}
            time.sleep(0.1)
        raise ValueError("TRAFFIC_POST_APPLY_VERIFICATION_FAILED")
    except Exception:
        command("systemctl", "stop", SERVICE, required=False)
        if old_unit is None:
            UNIT.unlink(missing_ok=True)
            command("systemctl", "disable", SERVICE, required=False)
        else:
            UNIT.write_bytes(old_unit)
            if not old_enabled:
                command("systemctl", "disable", SERVICE, required=False)
        if old_link is not None:
            (ROOT / "rollback").symlink_to(old_link)
            (ROOT / "rollback").replace(ROOT / "current")
        else:
            (ROOT / "current").unlink(missing_ok=True)
        command("systemctl", "daemon-reload", required=False)
        if own_active:
            command("systemctl", "start", SERVICE, required=False)
        raise
    finally:
        if stage.exists() and stage.parent == ROOT and stage.name.startswith("stage-"):
            shutil.rmtree(stage)


def invoke(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return apply(payload) if payload["action"] == "apply" else state(payload)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        # Exceptions may include private configuration or filesystem paths; return only known codes.
        import sys
        error = sys.exc_info()[1]
        code = str(error) if isinstance(error, ValueError) and re.fullmatch("TRAFFIC_[A-Z0-9_]+", str(error)) else "TRAFFIC_REMOTE_OPERATION_FAILED"
        return {"state": "ERROR", "error": code}
