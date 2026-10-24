"""Capacity controls cannot turn bad product data or loss into a PASS."""
import copy
import unittest
from unittest.mock import patch
from trafficlab.udp_capacity import capacity_candidate, run_capacity_control


class UdpCapacityTests(unittest.TestCase):
    def setUp(self):
        self.job={'id':'queue','run_id':'queue.case.SOCKS5','runtime_mode':'local','case_id':'udp-connections',
                  'duration':'SHORT','load':'LOW','host':'127.0.0.1','proxy_port':42502}
        self.catalog={'schema_version':1,'method':'controlled-traffic-v1','cases':[{'id':'udp-connections','recipe':'udp_connections'}],
                      'duration_seconds':{'SHORT':6},'loads':{'LOW':{'connections':4,'packets_per_second':100,'connection_steps':[8,32,128]}}}
        self.stage={'phase':'udp-flows-128','complete':True,'origin':{'udp_received':80,'proxy':{'udp_sent':100}},
                    'results':[{'task':'udp','flows':[{'loss_fraction':.2,'errors':[],'invalid':0}]}]}

    def test_candidate_preserves_the_failed_load_and_rejects_wrong_data(self):
        candidate=capacity_candidate(self.job,self.catalog,{'stages':[self.stage]})
        self.assertEqual((candidate['connections'],candidate['seconds'],candidate['rate_packets_per_second']), (128,6,100))
        for key in ('invalid','unexpected_source_packets','send_errors'):
            stage=copy.deepcopy(self.stage);stage['results'][0]['flows'][0][key]=1
            self.assertIsNone(capacity_candidate(self.job,self.catalog,{'stages':[stage]}))

    def test_control_only_marks_unverified_and_keeps_exact_profile(self):
        candidate=capacity_candidate(self.job,self.catalog,{'stages':[self.stage]})
        for limited in (True,False):
            stage=copy.deepcopy(self.stage)
            if not limited:stage['results'][0]['flows'][0]['loss_fraction']=0
            with patch('trafficlab.udp_capacity.run',return_value={'complete':not limited,'stages':[stage]})as run, \
                 patch('trafficlab.udp_capacity.stage_route',return_value=True):
                result=run_capacity_control(self.job,self.catalog,candidate,'out','progress')
            self.assertEqual(result['laboratory_limited'],limited)
            self.assertEqual(result['capacity_sufficient'],not limited)
            self.assertFalse(result['product_result_confirmed'])
            job,catalog=run.call_args.args[:2]
            self.assertEqual(job['test_proxy']['username'],'queue')
            self.assertEqual(catalog['loads']['LOW']['connections'],128)
            self.assertEqual(catalog['loads']['LOW']['packets_per_second'],100)
            self.assertEqual(catalog['duration_seconds']['SHORT'],6)

    def test_unverified_route_cannot_reclassify_product_failure(self):
        candidate=capacity_candidate(self.job,self.catalog,{'stages':[self.stage]})
        with patch('trafficlab.udp_capacity.run',return_value={'complete':False,'stages':[self.stage]}), \
             patch('trafficlab.udp_capacity.stage_route',return_value=False):
            result=run_capacity_control(self.job,self.catalog,candidate,'out','progress')
        self.assertFalse(result['laboratory_limited'])
