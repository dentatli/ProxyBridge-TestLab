import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from pb_target_flag_candidate import candidate,registration_stage


class BoundedFlagRegistration(unittest.TestCase):
    def test_registration_roundtrip_preserves_action_escaping(self):
        stage=registration_stage()
        for point in candidate()['points']:
            prefix='bp'+str(point['id'])+' '+point['target']+' "'
            start=stage.index(prefix)+len(prefix)
            end=stage.index('"; bd'+str(point['id']),start)
            decoded=stage[start:end].replace('\\"','"').replace('\\\\','\\')
            self.assertEqual(decoded,point['action'])

    def test_registration_keeps_old_points_disabled_and_never_enables(self):
        stage=registration_stage()
        for i in (2,3,4,5,6):self.assertIn('bd'+str(i)+';',stage)
        self.assertNotIn('; be',stage)
        self.assertNotIn('; g;',stage)
        self.assertFalse(candidate()['load_allowed'])


if __name__=='__main__':unittest.main()
