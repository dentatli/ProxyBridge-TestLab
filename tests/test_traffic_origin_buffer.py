"""The real local receiver works; a capped buffer cannot silently run a test."""
import asyncio
import os
import unittest
from unittest.mock import AsyncMock, Mock, patch
from trafficlab.agent import Agent, create_origin_datagram_endpoint, LOCAL_ORIGIN_UDP_RECEIVE_BUFFER
from trafficlab.worker import udp_flow


class OriginBufferTests(unittest.IsolatedAsyncioTestCase):
    @unittest.skipUnless(os.name == 'nt', 'Local Windows profile; remote OS buffer limits differ')
    async def test_local_receiver_keeps_signed_udp_validation(self):
        agent = Agent(b'x' * 32)
        agent.identity_mode = 'local-windows-v1'
        transport, _ = await create_origin_datagram_endpoint(asyncio.get_running_loop(), agent, '127.0.0.1', 0)
        try:
            self.assertGreaterEqual(agent.origin_udp_receive_buffer['effective_bytes'], LOCAL_ORIGIN_UDP_RECEIVE_BUFFER)
            job = {'host':'127.0.0.1','port':transport.get_extra_info('sockname')[1], 'secret':agent.secret.hex(),
                   'run_id':'buffer-test','seconds':.06,'rate_packets_per_second':1}
            result = await asyncio.to_thread(udp_flow, job, 'flow')
            self.assertTrue(result['complete'])
            self.assertEqual(result['received'], 1)
            self.assertEqual(agent.metrics('buffer-test')['udp_received'], 1)
        finally:
            transport.close()

    async def test_small_effective_buffer_refuses_before_bind_or_traffic(self):
        agent = Agent(b'x' * 32)
        agent.identity_mode = 'local-windows-v1'
        sock = Mock(); sock.getsockopt.return_value = 65536
        loop = Mock(); loop.create_datagram_endpoint = AsyncMock()
        with patch('trafficlab.agent.socket.socket', return_value=sock):
            with self.assertRaisesRegex(ValueError, 'RECEIVE_BUFFER_INSUFFICIENT'):
                await create_origin_datagram_endpoint(loop, agent, '127.0.0.1', 0)
        sock.bind.assert_not_called()
        sock.close.assert_called_once()
        loop.create_datagram_endpoint.assert_not_called()
