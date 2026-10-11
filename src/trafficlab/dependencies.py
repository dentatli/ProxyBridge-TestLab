"""Verified offline wheels for this runtime only; no package manager or global install."""
from __future__ import annotations
import hashlib
import json
import os
import platform
import re
import sys
import tempfile
import threading
import zipfile
from pathlib import Path, PurePosixPath

LOCK = 'traffic-dependencies.lock.json'
_gate = threading.Lock()
_enabled = False
_files: dict[str, str] = {}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(lock_path: Path, wheels: Path, destination: Path, target: str, write: bool = True) -> dict[str, str]:
    lock = json.loads(lock_path.read_bytes())
    if lock.get('schema_version') != 1 or lock.get('network_installation_allowed') is not False:
        raise ValueError('TRAFFIC_DEPENDENCY_LOCK_INVALID')
    artifacts = [row for row in lock['artifacts'] if row['platform'] == target]
    if len(artifacts) != len(lock['packages']):
        raise ValueError('TRAFFIC_DEPENDENCY_SET_INCOMPLETE')
    if write:
        destination.mkdir(parents=True, exist_ok=False)
    hashes: dict[str, str] = {}
    for row in artifacts:
        name = row['file']
        if not re.fullmatch(r'[A-Za-z0-9_.-]+\.whl', name):
            raise ValueError('TRAFFIC_DEPENDENCY_NAME_INVALID')
        wheel = wheels / name
        if wheel.is_symlink() or wheel.stat().st_size != row['bytes'] or digest(wheel) != row['sha256']:
            raise ValueError('TRAFFIC_DEPENDENCY_HASH_MISMATCH')
        with zipfile.ZipFile(wheel) as archive:
            if sum(item.file_size for item in archive.infolist()) > 128 * 1024 * 1024:
                raise ValueError('TRAFFIC_DEPENDENCY_TOO_LARGE')
            for item in archive.infolist():
                path = PurePosixPath(item.filename)
                if path.is_absolute() or '..' in path.parts or '\\' in item.filename or ':' in item.filename or item.external_attr >> 16 & 0o170000 == 0o120000:
                    raise ValueError('TRAFFIC_DEPENDENCY_PATH_INVALID')
                if item.is_dir():
                    continue
                relative = path.as_posix()
                if relative in hashes:
                    raise ValueError('TRAFFIC_DEPENDENCY_PATH_COLLISION')
                data = archive.read(item)
                file = destination / relative
                if write:
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_bytes(data)
                hashes[relative] = hashlib.sha256(data).hexdigest()
    return hashes


def verify() -> None:
    if any(Path(path).is_symlink() or digest(Path(path)) != expected for path, expected in _files.items()):
        raise ValueError('TRAFFIC_DEPENDENCY_IDENTITY_CHANGED')


def enable() -> None:
    global _enabled, _files
    with _gate:
        if _enabled:
            return
        root = Path(__file__).resolve().parent.parent
        if (root / LOCK).is_file():
            manifest = json.loads((root / 'runtime-manifest.json').read_bytes())
            hashes = manifest['dependency_hashes']
            directory = root / 'dependencies'
            if directory.is_symlink() or not hashes:
                raise ValueError('TRAFFIC_DEPENDENCY_IDENTITY_CHANGED')
        else:
            if sys.platform != 'win32' or sys.version_info[:2] != (3, 11) or platform.machine().lower() not in ('amd64', 'x86_64'):
                raise ValueError('TRAFFIC_DEPENDENCY_PLATFORM_UNSUPPORTED')
            vendor = root.parent / 'vendor'
            cache = Path(os.environ['LOCALAPPDATA']) / 'ProxyBridge-TestLab' / 'traffic-lab' / 'dependency-cache'
            cache.mkdir(parents=True, exist_ok=True)
            version = cache / digest(vendor / LOCK)
            if not version.exists():
                with tempfile.TemporaryDirectory(prefix='stage-', dir=cache) as temporary:
                    stage = Path(temporary)
                    hashes = extract(vendor / LOCK, vendor / 'traffic-wheelhouse' / 'win-x64', stage / 'dependencies', 'win-x64')
                    (stage / 'manifest.json').write_text(json.dumps(hashes, sort_keys=True))
                    try:
                        stage.rename(version)
                    except FileExistsError:
                        pass  # Another worker published the same immutable cache; verify it below.
            if version.is_symlink():
                raise ValueError('TRAFFIC_DEPENDENCY_IDENTITY_CHANGED')
            directory = version / 'dependencies'
            hashes = extract(vendor / LOCK, vendor / 'traffic-wheelhouse' / 'win-x64', directory, 'win-x64', write=False)
        if any(PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts or '\\' in name or ':' in name for name in hashes):
            raise ValueError('TRAFFIC_DEPENDENCY_PATH_INVALID')
        _files = {str(directory / name): expected for name, expected in hashes.items()}
        verify()
        sys.path.insert(0, str(directory))
        _enabled = True
