"""Global idle must include owned pre-TLS sockets and reject missing kernel evidence."""
import unittest
from pathlib import Path
from trafficlab.socket_idle import tcp_inodes,owned_tcp_connections


class SocketIdleTests(unittest.TestCase):
    def test_listener_is_excluded_but_established_and_close_wait_are_busy(self):
        header='sl local_address rem_address st tx_queue tr retrnsmt uid timeout inode\n'
        rows='\n'.join(f'{index}: 00000000:{port:04X} 00000000:0000 {state:02X} 0 0 0 0 0 {inode}'
            for index,port,state,inode in ((0,42523,10,10),(1,42523,1,11),(2,42523,8,12),(3,42502,1,13)))
        self.assertEqual(tcp_inodes(header+rows,{42523}),{'11','12'})

    def test_malformed_table_cannot_be_idle(self):
        for value in ('','not a tcp table','local_address inode\ntruncated',
                      'local_address inode\n0: bad 0 01 0 0 0 0 0 1'):
            with self.assertRaises(ValueError):
                tcp_inodes(value,{42523})

    def test_unavailable_proc_or_observer_returns_unknown(self):
        self.assertIsNone(owned_tcp_connections({42523},5,Path('missing-testlab-proc')))
        self.assertIsNone(owned_tcp_connections({42523},True))
        self.assertIsNone(owned_tcp_connections(set(),5))


if __name__=='__main__':
    unittest.main()
