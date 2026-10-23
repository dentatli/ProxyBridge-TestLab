"""Isolated SSH exec and SFTP memory objects; no OS shell or filesystem access."""
from __future__ import annotations
import asyncio
import hmac
import json
from typing import Any
from trafficlab.dependencies import enable
from trafficlab.protocol import ID, MAX_LINE, json_bytes, mac
from trafficlab.application_wire import response
from trafficlab.ssh_wire import read_line

enable()
import asyncssh


class SshOrigin:
    def __init__(self, origins: Any, key: str):
        self.origins, self.key = origins, key
        self.connections: dict[Any, dict[str, Any]] = {}

    def exchange(self, conn: Any, raw: bytes, kind: str) -> bytes:
        if len(raw) > MAX_LINE:
            raise ValueError('APPLICATION_SSH_MESSAGE_TOO_LARGE')
        message = json.loads(raw)
        if message.get('identity', {}).get('run_id') != conn.get_extra_info('username'):
            raise ValueError('APPLICATION_SSH_USER_IDENTITY_CHANGED')
        session = self.connections[conn]
        value, row, payload = self.origins.authenticate(message, kind, session['peer'], session)
        reply = json_bytes(response(self.origins.agent.secret, value, session['peer'], message['payload']))
        row['rx_bytes'] += len(payload)
        row['tx_bytes'] += len(payload)
        return reply

    async def process(self, process: Any) -> None:
        if process.command != 'testlab-echo':
            process.exit(126)
            return
        try:
            while True:
                raw = await asyncio.wait_for(read_line(process.stdin), 5)
                if not raw:
                    process.exit(0)
                    return
                process.stdout.write(self.exchange(process.channel.get_connection(), raw, 'ssh') + b'\n')
                await process.stdout.drain()
        except (ValueError, KeyError, TypeError, OSError, asyncio.TimeoutError):
            process.exit(1)

    async def start(self, bind: str, port: int) -> Any:
        owner = self
        class Server(asyncssh.SSHServer):
            def connection_made(self, conn):
                self.conn = conn
                if owner.origins.agent.active >= owner.origins.agent.max_connections:
                    conn.close()
                    return
                owner.origins.agent.active += 1
                owner.connections[conn] = {'peer': list(conn.get_extra_info('peername')[:2])}
                self.expiry = asyncio.get_running_loop().call_later(150, conn.close)

            def connection_lost(self, _exc):
                session = owner.connections.pop(self.conn, None)
                if session is not None:
                    self.expiry.cancel()
                    owner.origins.agent.active -= 1
                    if session.get('row') is not None:
                        session['row']['active'] -= 1
                        session['row']['completed'] += 1

            def password_auth_supported(self):
                return True

            def validate_password(self, username, password):
                return bool(ID.fullmatch(username)) and hmac.compare_digest(password, mac(owner.origins.agent.secret, b'ssh-auth:', username.encode('ascii')))

            def connection_requested(self, *_args):
                return False

            def server_requested(self, *_args):
                return False

        return await asyncssh.listen(bind, port, server_factory=Server, server_host_keys=[self.key],
            process_factory=self.process, sftp_factory=lambda chan: MemorySftp(chan, self),
            encoding=None, line_editor=False, allow_pty=False, agent_forwarding=False,
            x11_forwarding=False, login_timeout=5, kex_algs=['curve25519-sha256'],
            encryption_algs=['aes128-gcm@openssh.com', 'chacha20-poly1305@openssh.com'], window=16384, max_pktsize=8192)

    async def close(self) -> None:
        connections = list(self.connections)
        for conn in connections:
            conn.close()
        await asyncio.gather(*(conn.wait_closed() for conn in connections))


class MemorySftp(asyncssh.SFTPServer):
    def __init__(self, chan, owner):
        super().__init__(chan)
        self.owner, self.conn = owner, chan.get_connection()
        self.reply: bytes | None = None
        self.handles = 0

    def map_path(self, _path):
        raise asyncssh.SFTPPermissionDenied('Only TestLab memory objects are available')

    def realpath(self, path):
        if path in (b'.', b'/'):
            return b'/'
        if path not in (b'/request', b'/response'):
            self.map_path(path)
        return path

    def stat(self, path):
        self.realpath(path)
        return asyncssh.SFTPAttrs(size=len(self.reply or b'') if path == b'/response' else 0)

    lstat = stat

    def open(self, path, pflags, _attrs):
        if self.handles >= 2:
            raise asyncssh.SFTPFailure('Object handle limit')
        if path == b'/request' and pflags == (asyncssh.FXF_WRITE | asyncssh.FXF_CREAT | asyncssh.FXF_TRUNC):
            handle = {'write': True, 'data': bytearray()}
        elif path == b'/response' and pflags == asyncssh.FXF_READ and self.reply is not None:
            handle = {'write': False, 'data': self.reply}
        else:
            self.map_path(path)
        self.handles += 1
        return handle

    def fstat(self, handle):
        return asyncssh.SFTPAttrs(size=len(handle['data']))

    def write(self, handle, offset, data):
        if not handle['write'] or offset != len(handle['data']) or offset + len(data) > MAX_LINE:
            raise asyncssh.SFTPFailure('Invalid bounded write')
        handle['data'].extend(data)
        return len(data)

    def read(self, handle, offset, size):
        if handle['write'] or size > MAX_LINE:
            raise asyncssh.SFTPFailure('Invalid bounded read')
        return handle['data'][offset:offset + size]

    def close(self, handle):
        self.handles -= 1
        if handle['write']:
            self.reply = None
            try:
                self.reply = self.owner.exchange(self.conn, bytes(handle['data']), 'sftp')
            except (ValueError, KeyError, TypeError, OSError):
                raise asyncssh.SFTPFailure('Unverified TestLab request') from None
