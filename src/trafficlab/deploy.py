"""Own versioned Ubuntu 22.04 service. SSH stdin supplies private configuration, never argv."""
from __future__ import annotations

import base64
import hashlib
import ipaddress
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any

ROOT = Path("/opt/proxybridge-testlab-traffic")
UNIT = Path("/etc/systemd/system/proxybridge-testlab-traffic.service")
SERVICE = "proxybridge-testlab-traffic.service"
PORTS = {42501, 42502, 42503, 42511, 42512, 42513, 42514, 42515, 42516, 42517, 42518, 42519,
         42522, 42523, 42524, 42525, 42526, 42527, 42528, 42529, 42530, 42531, 42532, 42533, 42535}
UDP_PORTS = {42501, 42502, 42515, 42520, 42521}
PKI_NAMES = ('ca.pem', 'server.pem', 'server.key', 'ssh_host.key')


class RollbackFailure(ValueError):
    """Recovery did not prove restoration; never report the original install error alone."""


def replace_link(target: str | Path, destination: Path) -> None:
    temporary = destination.parent / ('link-' + uuid.uuid4().hex)
    try:
        temporary.symlink_to(target)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def replace_unit(content: bytes) -> None:
    descriptor, name = tempfile.mkstemp(prefix='.testlab-unit-', dir=UNIT.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(content)
        temporary.chmod(0o644)
        temporary.replace(UNIT)
    finally:
        temporary.unlink(missing_ok=True)


def restored(old_link: str | None, old_unit: bytes | None, active: bool, enabled: bool,
             old_payload: dict[str, Any] | None) -> bool:
    current = ROOT / 'current'
    if old_link is None:
        if current.exists() or current.is_symlink():
            return False
    elif not current.is_symlink() or os.readlink(current) != old_link:
        return False
    if (UNIT.read_bytes() if UNIT.exists() else None) != old_unit:
        return False
    if (command('systemctl', 'is-active', SERVICE, required=False) == 'active') != active:
        return False
    if (command('systemctl', 'is-enabled', SERVICE, required=False) == 'enabled') != enabled:
        return False
    # A previously active service must recover its exact sources, PKI, process and listeners.
    if not active:
        return True
    if old_payload is None:
        return False
    if digest((current / 'runtime-manifest.json').read_bytes()) != old_payload['manifest_sha256']:
        return False
    observed = state(old_payload)
    return all(observed[key] is True for key in ('hashes_match', 'service_active', 'listeners'))


def provision_pki(stage: Path) -> dict[str, str]:
    directory = stage / "pki"
    directory.mkdir(mode=0o700)
    ca_key, ca, leaf_key, leaf = (directory / name for name in ("ca.key", "ca.pem", "server.key", "server.pem"))
    command("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "365", "-sha256",
            "-subj", "/CN=ProxyBridge-TestLab isolated application CA", "-keyout", str(ca_key), "-out", str(ca),
            "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign")
    csr = directory / "server.csr"
    command("openssl", "req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=traffic.testlab.invalid",
            "-keyout", str(leaf_key), "-out", str(csr))
    extensions = directory / "server.ext"
    extensions.write_text("basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:traffic.testlab.invalid\n")
    command("openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca), "-CAkey", str(ca_key), "-set_serial", "1",
            "-days", "365", "-sha256", "-extfile", str(extensions), "-out", str(leaf))
    # The CA signing key is temporary; neither trust stores nor existing certificates are changed.
    ca_key.unlink()
    csr.unlink()
    extensions.unlink()
    import asyncssh
    (directory / 'ssh_host.key').write_bytes(asyncssh.generate_private_key('ssh-ed25519').export_private_key('openssh'))
    return {name: digest((directory / name).read_bytes()) for name in PKI_NAMES}


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
    tcp_ports, udp_ports = PORTS, UDP_PORTS
    if current.is_symlink():
        version = current.resolve(strict=True)
        if version.parent == ROOT / "versions" and version.is_dir():
            matches = all((version / name).is_file() and not (version / name).is_symlink() and digest((version / name).read_bytes()) == expected
                          for name, expected in payload["hashes"].items())
            config = version / "agent-private.json"
            matches = matches and config.is_file() and digest(config.read_bytes()) == payload["config_sha256"]
            manifest = version / "runtime-manifest.json"
            matches = matches and all((version / "pki" / name).is_file() and not (version / "pki" / name).is_symlink()
                                      for name in PKI_NAMES)
            document = json.loads(manifest.read_bytes()) if manifest.is_file() else {}
            dependencies = document.get('dependency_hashes', {})
            matches = matches and bool(dependencies) and all(not (version / 'dependencies' / name).is_symlink()
                and (version / 'dependencies' / name).is_file() and digest((version / 'dependencies' / name).read_bytes()) == expected
                for name, expected in dependencies.items())
            matches = matches and document == {
                "hashes": payload["hashes"], "config_sha256": payload["config_sha256"], "bundle_sha256": payload["bundle_sha256"],
                "pki_hashes": {name: digest((version / "pki" / name).read_bytes()) for name in PKI_NAMES}, 'dependency_hashes': dependencies}
            if matches:
                # Rollback must verify the previous version's listeners, which may predate new cases.
                configuration = json.loads(config.read_bytes())
                application_ports = configuration.get('application_ports', {})
                udp_kinds = {'dns-udp', 'quic', 'http3'}
                tcp_ports = {configuration[key] for key in ('port', 'proxy_port', 'control_port')}
                udp_ports = {configuration[key] for key in ('port', 'proxy_port')}
                tcp_ports.update(port for kind, port in application_ports.items() if kind not in udp_kinds)
                udp_ports.update(port for kind, port in application_ports.items() if kind in udp_kinds)
                if any(type(port) is not int or not 1 <= port <= 65535 for port in tcp_ports | udp_ports):
                    raise ValueError('TRAFFIC_CONFIGURATION_PORTS_INVALID')
    active = command("systemctl", "is-active", SERVICE, required=False) == "active"
    enabled = command("systemctl", "is-enabled", SERVICE, required=False) == "enabled"
    tcp = command("ss", "-H", "-lnt")
    udp = command("ss", "-H", "-lnu")
    def listening(text: str, port: int) -> bool:
        return any(re.search(r":" + str(port) + r"(?:\s|$)", line) for line in text.splitlines())
    listeners = all(listening(tcp, port) for port in tcp_ports) and all(listening(udp, port) for port in udp_ports)
    if matches and active:
        pid = command("systemctl", "show", SERVICE, "--property=MainPID", "--value")
        argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if pid.isdecimal() and pid != "0" else []
        matches = str(version / "agent-private.json").encode() in argv
    return {"state": "READY" if matches and active and enabled and listeners else "SETUP_REQUIRED",
            "hashes_match": matches, "service_active": active, "service_enabled": enabled, "listeners": listeners,
            "bundle_sha256": payload["bundle_sha256"], "verified_ubuntu": "22.04", "tcp_ports": sorted(tcp_ports), "udp_ports": sorted(udp_ports)}


def apply(payload: dict[str, Any]) -> dict[str, Any]:
    before = state(payload)
    if before["state"] == "READY":
        return {**before, "applied": False}
    for name in payload["sources"]:
        if not re.fullmatch(r"(?:trafficlab/[a-z_]+\.py|traffic-workloads\.json|traffic-dependencies\.lock\.json|wheels/[A-Za-z0-9_.-]+\.whl)", name):
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
        if any(re.search(r":" + str(port) + r"(?:\s|$)", line) for port in PORTS | UDP_PORTS):
            # Do not assume any listener on a reserved port belongs to this service.
            pid_match = re.search(r"pid=(\d+)", line)
            if not own_active or pid_match is None or SERVICE not in Path(f"/proc/{pid_match[1]}/cgroup").read_text():
                raise ValueError("TRAFFIC_PORT_CONFLICT")
    if shutil.which("ufw") and "Status: active" in command("ufw", "status"):
        # Existing networking policy is not silently widened by a new runtime installer.
        raise ValueError("TRAFFIC_FIREWALL_REVIEW_REQUIRED")
    try:
        import pwd
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
    old_payload = None
    if own_active:
        if old_link is None or old_unit is None:
            raise ValueError('TRAFFIC_PREVIOUS_RUNTIME_UNVERIFIED')
        manifest_bytes = (ROOT / 'current' / 'runtime-manifest.json').read_bytes()
        manifest = json.loads(manifest_bytes)
        old_payload = {key: manifest[key] for key in ('hashes', 'config_sha256', 'bundle_sha256')}
        old_payload['manifest_sha256'] = digest(manifest_bytes)
        previous = state(old_payload)
        if not all(previous[key] is True for key in ('hashes_match', 'service_active', 'listeners')):
            raise ValueError('TRAFFIC_PREVIOUS_RUNTIME_UNVERIFIED')
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
    activation_started = False
    try:
        for name, encoded in payload["sources"].items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(base64.b64decode(encoded, validate=True))
        config = stage / "agent-private.json"
        config.write_bytes(base64.b64decode(payload["configuration"], validate=True))
        import sys
        sys.path.insert(0, str(stage))
        from trafficlab.dependencies import extract
        dependency_hashes = extract(stage / 'traffic-dependencies.lock.json', stage / 'wheels', stage / 'dependencies', 'linux-x64')
        sys.path.insert(0, str(stage / 'dependencies'))
        pki_hashes = provision_pki(stage)
        (stage / "runtime-manifest.json").write_text(json.dumps({"hashes":payload["hashes"], "config_sha256":payload["config_sha256"], "bundle_sha256":payload["bundle_sha256"], "pki_hashes":pki_hashes, 'dependency_hashes': dependency_hashes},sort_keys=True))
        for folder, _dirs, files in os.walk(stage):
            os.chmod(folder, 0o755)
            for filename in files:
                file = Path(folder) / filename
                os.chmod(file, 0o640 if file == config or file.name in ("server.key", 'ssh_host.key') else 0o644)
                os.chown(file, 0, account.pw_gid)
        if version.exists():
            # Matching versions are immutable; repair uses a fresh owned directory, preserving the old evidence.
            version = ROOT / "versions" / (payload["bundle_sha256"] + "-" + stage.name)
            unit = unit.replace(str(ROOT / "versions" / payload["bundle_sha256"]).encode(), str(version).encode())
        stage.rename(version)
        activation_started = True
        replace_link(version, ROOT / 'current')
        replace_unit(unit)
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
        if not activation_started:
            # Source/dependency/PKI preparation cannot interrupt the existing runtime.
            raise
        try:
            command("systemctl", "stop", SERVICE)
            if old_unit is None:
                command("systemctl", "disable", SERVICE)
                UNIT.unlink(missing_ok=True)
            else:
                replace_unit(old_unit)
                command("systemctl", "enable" if old_enabled else "disable", SERVICE)
            if old_link is not None:
                replace_link(old_link, ROOT / 'current')
            else:
                (ROOT / "current").unlink(missing_ok=True)
            command("systemctl", "daemon-reload")
            if own_active:
                command("systemctl", "start", SERVICE)
            import time
            for _ in range(30):
                if restored(old_link, old_unit, own_active, old_enabled, old_payload):
                    break
                time.sleep(0.1)
            else:
                raise RollbackFailure('TRAFFIC_ROLLBACK_VERIFICATION_FAILED')
        except Exception as recovery_error:
            raise RollbackFailure('TRAFFIC_ROLLBACK_VERIFICATION_FAILED') from recovery_error
        raise
    finally:
        if stage.exists() and stage.parent == ROOT and stage.name.startswith("stage-"):
            shutil.rmtree(stage)


def invoke(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        if payload['action'] != 'apply':
            return state(payload)
        platform()
        ROOT.mkdir(mode=0o755, exist_ok=True)
        import fcntl
        descriptor = os.open(ROOT / 'operation.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('TRAFFIC_OPERATION_ACTIVE') from None
            return apply(payload)
        finally:
            os.close(descriptor)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        # Exceptions may include private configuration or filesystem paths; return only known codes.
        import sys
        error = sys.exc_info()[1]
        code = str(error) if isinstance(error, ValueError) and re.fullmatch("TRAFFIC_[A-Z0-9_]+", str(error)) else "TRAFFIC_REMOTE_OPERATION_FAILED"
        return {"state": "ERROR", "error": code}
