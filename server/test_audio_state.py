"""Original Music_Player and Effect_Player delivery, without world mutations."""
import unittest
from copy import deepcopy
from eo_session import number,EOError
from test_live_state import fixture

class AudioStateTests(unittest.TestCase):
    def test_native_quest_sound_retains_one_based_id_and_flushes(self):
        s=fixture();before=deepcopy(s.state)
        s.apply_event(40,8,number(50,1))
        self.assertEqual(s.events[-1]['kind'],'sound');self.assertEqual(s.events[-1]['sound_id'],50)
        self.assertTrue(s.dirty);self.assertEqual(before,s.state)
    def test_potion_packet_preserves_all_observers_and_zero_based_graphics(self):
        s=fixture();before=deepcopy(s.state)
        s.apply_event(31,8,number(101,2)+number(0,2)+number(102,2)+number(9,2))
        self.assertEqual(s.events[-2:],[dict(kind='potion_effect',player_id=101,effect_id=0),dict(kind='potion_effect',player_id=102,effect_id=9)])
        self.assertTrue(s.dirty);self.assertEqual(before,s.state)
    def test_truncated_potion_batch_does_not_emit_partial_effects(self):
        s=fixture()
        with self.assertRaisesRegex(EOError,'Truncated'):s.apply_event(31,8,number(101,2)+number(9,2)+b'x')
        self.assertFalse(any(e.get('kind')=='potion_effect' for e in s.events));self.assertFalse(s.dirty)
    def test_invalid_server_sound_does_not_emit(self):
        s=fixture()
        with self.assertRaises(EOError):s.apply_event(40,8,number(50,1)+b'x')
        self.assertFalse(any(e.get('kind')=='sound' for e in s.events));self.assertFalse(s.dirty)
if __name__=='__main__':unittest.main()
