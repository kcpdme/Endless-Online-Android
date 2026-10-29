import unittest
from unittest.mock import patch
from eo_session import EOError
from test_live_state import fixture
from admin_actions import DESTINATIONS

class AdminTests(unittest.TestCase):
    def test_regular_and_pre_entry_sessions_cannot_use_any_admin_operation(self):
        for state in (None,fixture().state):
            for operation,args in [('admin_open',()),*[('admin_teleport',(d['key'],)) for d in DESTINATIONS],('admin_item',(1,)),('admin_spawn',(1,))]:
                s=fixture();s.state=state
                with self.assertRaisesRegex(EOError,'Admin access'):getattr(s,operation)(*args)
                self.assertEqual(s.sent,[])

    @patch('admin_actions.command_settings',return_value={'AdminPrefix':'$','warp':'2','sitem':'3','snpc':'3'})
    def test_rank_and_input_validation_never_send_commands(self,_):
        s=fixture();s.stats['admin']=1
        self.assertEqual(s.admin_open()['capabilities'],dict(teleport=False,item=False,spawn=False))
        for operation,args in [('admin_teleport',('apozen',)),('admin_item',(1,)),('admin_spawn',(1,))]:
            with self.assertRaisesRegex(EOError,'rank'):getattr(s,operation)(*args)
        s.stats['admin']=4
        with self.assertRaisesRegex(EOError,'listed'):s.admin_teleport('119 24 29;$sitem 1')
        with patch('admin_actions.item_definitions',return_value={1:{}}),patch('admin_actions.npc_ids',return_value={1}):
            for invalid in (0,-1,99999,True,1.0,'1','$sitem 1'):
                for operation in ('admin_item','admin_spawn'):
                    with self.assertRaisesRegex(EOError,'valid'):getattr(s,operation)(invalid)
        self.assertEqual(s.sent,[])

    @patch('admin_actions.command_settings',return_value={'AdminPrefix':'$','warp':'2','sitem':'3','snpc':'3'})
    def test_pending_movement_and_trade_reject_admin_actions(self,_):
        for attribute,value in [('pending_moves',[{}]),('trade',{'active':True}),('casting',{'id':1}),('warp',{'map_id':5})]:
            s=fixture();s.stats['admin']=4;setattr(s,attribute,value)
            with self.assertRaises(EOError):s.admin_teleport('apozen')
            self.assertEqual(s.sent,[])

    def test_presets_are_walkable_and_away_from_portals_and_spawn_centres(self):
        import json
        from pathlib import Path
        maps={w['id']:w for w in (json.loads(p.read_text()) for p in (Path(__file__).resolve().parents[1]/'client/content/maps').glob('*.json'))}
        self.assertEqual(len(DESTINATIONS),14)
        self.assertEqual({d['key']:(d['map_id'],d['x'],d['y']) for d in DESTINATIONS[5:]},
                         dict(monkey_island=(271,25,54),pyramid=(229,82,112),admin_room=(21,12,6),anundo=(161,32,36),atlantis=(255,12,19),kingworms_room=(229,20,20),sky_haven=(71,34,14),dragon_cave=(270,8,14),aeven=(5,40,40)))
        for d in DESTINATIONS:
            w=maps[d['map_id']];point=(d['x'],d['y'])
            self.assertTrue(0<=d['x']<w['width'] and 0<=d['y']<w['height'])
            self.assertNotIn(point,set(map(tuple,w['server_blocked'])))
            self.assertNotIn(point,{(p['x'],p['y']) for p in w['warps']})
            self.assertNotIn(point,{(p['x'],p['y']) for p in w['npcs']})

if __name__=='__main__':unittest.main()
