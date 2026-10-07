"""Opt-in fixture compatibility for one pinned CPython close callback."""
import ast
import asyncio
import hashlib
import inspect
import sys
import textwrap

POLICY = 'pinned-proactor-shutdown-reset-close-v1'
SOURCE_SHA256 = '3777dc92992769764dafcb4d7049bb4eb3fd3dd5c64cee67862b1283d439064e'


def build_callback(original, port, emit):
    source = inspect.getsource(original)
    if hashlib.sha256(source.encode()).hexdigest() != SOURCE_SHA256:
        raise ValueError('PROACTOR_CLOSE_CALLBACK_SOURCE_CHANGED')

    def accept_reset(transport, error, exc):
        # Only the already-notified, closing accepted loopback transport.
        # Other callback, protocol, socket.close and detach errors propagate.
        if (exc is not None or not isinstance(error, ConnectionResetError)
                or getattr(error, 'winerror', None) != 10054 or error.__context__ is not None
                or not transport._closing or transport._called_connection_lost
                or transport._server is None or transport._sock is None
                or not isinstance(transport._protocol, asyncio.StreamReaderProtocol)
                or not transport._protocol._closed.done()):
            return False
        local = transport._sock.getsockname()
        return local[0] == '127.0.0.1' and local[1] == port

    tree = ast.parse(textwrap.dedent(source))
    function = tree.body[0]
    finally_body = function.body[1].finalbody
    shutdown = finally_body[0].body[0]
    if ast.unparse(shutdown) != 'self._sock.shutdown(socket.SHUT_RDWR)':
        raise ValueError('PROACTOR_CLOSE_CALLBACK_STRUCTURE_CHANGED')
    finally_body[0].body = ast.parse('''
try:
    self._sock.shutdown(socket.SHUT_RDWR)
except ConnectionResetError as _pb_error:
    if not _pb_accept_reset(self, _pb_error, exc):
        raise
    _pb_close_reset = True
''').body
    function.body.insert(0, ast.parse('_pb_close_reset = False').body[0])
    # Emit only after the original socket.close, Server._detach and flag update.
    finally_body.extend(ast.parse('''
if _pb_close_reset:
    _pb_emit('PROACTOR_SHUTDOWN_RESET_HANDLED', policy=_pb_policy,
             winerror=10054, local_ip='127.0.0.1', local_port=_pb_port,
             socket_closed=True, listener_detached=True)
''').body)
    ast.fix_missing_locations(tree)
    namespace = dict(original.__globals__, _pb_accept_reset=accept_reset,
                     _pb_emit=emit, _pb_port=port, _pb_policy=POLICY)
    exec(compile(tree, __file__, 'exec'), namespace)
    return namespace[original.__name__]


def install(port, emit):
    if sys.platform != 'win32' or sys.version_info[:3] != (3, 12, 14):
        raise ValueError('PROACTOR_CLOSE_GUARD_RUNTIME_CHANGED')
    from asyncio.proactor_events import _ProactorBasePipeTransport
    original = _ProactorBasePipeTransport._call_connection_lost
    replacement = build_callback(original, port, emit)
    _ProactorBasePipeTransport._call_connection_lost = replacement
    emit('PROACTOR_CLOSE_GUARD_INSTALLED', policy=POLICY,
         callback_source_sha256=SOURCE_SHA256, local_port=port)

    def restore():
        if _ProactorBasePipeTransport._call_connection_lost is not replacement:
            raise ValueError('PROACTOR_CLOSE_GUARD_REPLACED')
        _ProactorBasePipeTransport._call_connection_lost = original
    return restore
