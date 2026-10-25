"""Private Windows loopback origin: offline dependencies, isolated PKI and pinned files."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import ipaddress
import json
import os
import shutil
import sys
from pathlib import Path
from trafficlab.protocol import json_bytes


def digest(path: Path) -> str:
    if path.is_symlink() or (os.name == 'nt' and path.stat().st_file_attributes & 0x400):
        raise ValueError('TRAFFIC_LOCAL_REPARSE_POINT')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(request: dict) -> dict:
    from trafficlab.dependencies import enable, verify
    enable()
    verify()
    import asyncssh
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
    from trafficlab.application_wire import APPLICATION_PORTS, SERVER_NAME
    directory = Path(request['directory']).resolve()
    directory.mkdir(exist_ok=False)
    sources = request['source_hashes']
    if not sources or any(digest(Path(name)) != value for name, value in sources.items()):
        raise ValueError('TRAFFIC_LOCAL_SOURCE_CHANGED')
    home = Path(sys.executable).parent
    executable = directory / ('pb_testlab_adapter_origin.exe' if request.get('native_engine') else 'pb_testlab_origin.exe')
    shutil.copyfile(sys.executable, executable)
    if digest(executable) != digest(Path(sys.executable)):
        raise ValueError('TRAFFIC_LOCAL_INTERPRETER_CHANGED')
    for name in ('python311.dll', 'python3.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'):
        if (home / name).is_file():
            shutil.copyfile(home / name, directory / name)
            if digest(directory/name) != digest(home/name):
                raise ValueError('TRAFFIC_LOCAL_INTERPRETER_CHANGED')
    pki = directory / 'pki'
    pki.mkdir()
    now = datetime.datetime.now(datetime.timezone.utc)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'TestLab private loopback CA')])
    ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca_key.public_key())
          .serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(minutes=5))
          .not_valid_after(now+datetime.timedelta(days=30)).add_extension(x509.BasicConstraints(ca=True, path_length=0), True)
          .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), True)
          .sign(ca_key, hashes.SHA256()))
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    cert = (x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, SERVER_NAME)]))
            .issuer_name(ca_name).public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now-datetime.timedelta(minutes=5)).not_valid_after(now+datetime.timedelta(days=30))
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), True)
            .add_extension(x509.SubjectAlternativeName([x509.DNSName(SERVER_NAME), x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]), False)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), False).sign(ca_key, hashes.SHA256()))
    (pki/'ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    (pki/'server.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (pki/'server.key').write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    (pki/'ssh_host.key').write_bytes(asyncssh.generate_private_key('ssh-ed25519').export_private_key('openssh'))
    config = {'secret':request['secret'], 'bind':'127.0.0.1', 'origin_addresses':['127.0.0.1'],
              'port':42501, 'proxy_port':42502, 'control_port':42503, 'max_connections':2048,
              'application_ports':APPLICATION_PORTS, 'identity_mode':'local-windows-v1',
              'stop_path':str(directory/'stop.requested'),
              'tls_certificate_file':str(pki/'server.pem'), 'tls_key_file':str(pki/'server.key'),
              'tls_ca_file':str(pki/'ca.pem'), 'ssh_host_key_file':str(pki/'ssh_host.key')}
    if request.get('native_engine'):
        native = request['native_engine']
        if not isinstance(native, dict) or type(native.get('port')) is not int or not 1024 <= native['port'] <= 65535 or \
                not isinstance(native.get('executable'), str) or not Path(native['executable']).is_absolute() or \
                sources.get(native['executable']) != digest(Path(native['executable'])):
            raise ValueError('TRAFFIC_NATIVE_ENGINE_IDENTITY_INVALID')
        config['native_engine'] = {'port':native['port'], 'executable':native['executable']}
        if 'pid' in native:
            if type(native['pid']) is not int or native['pid'] <= 0:
                raise ValueError('TRAFFIC_NATIVE_ENGINE_IDENTITY_INVALID')
            config['native_engine']['pid'] = native['pid']
    configuration = directory/'config-private.json'
    configuration.write_bytes(json_bytes(config))
    files = {**sources, **{str(path):digest(path) for path in directory.rglob('*') if path.is_file()}}
    manifest = {'schema_version':1, 'mode':'local-windows-v1', 'files':files,
                'bundle_sha256':hashlib.sha256(json_bytes({'mode':'local-windows-v1', 'files':files})).hexdigest()}
    (directory/'local-manifest.json').write_bytes(json_bytes(manifest))
    return {'bundle_sha256':manifest['bundle_sha256'], 'configuration':str(configuration), 'executable':str(executable),
            'python_home':str(home), 'stop_path':config['stop_path']}


def identity(configuration: Path, applications) -> dict:
    from trafficlab.dependencies import verify
    manifest = json.loads((configuration.parent/'local-manifest.json').read_bytes())
    if manifest.get('mode') != 'local-windows-v1' or any(digest(Path(name)) != value for name, value in manifest['files'].items()):
        raise ValueError('TRAFFIC_LOCAL_IDENTITY_CHANGED')
    bundle = hashlib.sha256(json_bytes({'mode':'local-windows-v1', 'files':manifest['files']})).hexdigest()
    if bundle != manifest['bundle_sha256']:
        raise ValueError('TRAFFIC_LOCAL_IDENTITY_CHANGED')
    verify()
    return {'verified':True, 'bundle_sha256':bundle, 'application':applications.tls_identity(),
            'scope':'same-Windows-host-loopback-pinned-files-private-PKI', 'platform':'windows-local'}


def main() -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--prepare', action='store_true')
    action.add_argument('--application-ports', action='store_true')
    args = parser.parse_args()
    if args.application_ports:
        from trafficlab.application_wire import APPLICATION_PORTS
        print(json.dumps(APPLICATION_PORTS), flush=True)
        return 0
    try:
        request = json.loads(sys.stdin.buffer.read(1024*1024))
        print(json.dumps(prepare(request)), flush=True)
        return 0
    except (OSError, ValueError, KeyError):
        print('TRAFFIC_LOCAL_PREPARATION_FAILED', file=sys.stderr, flush=True)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
