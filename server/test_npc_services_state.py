"""Visible original service NPCs may stand behind impassable shop counters."""
import unittest
from eo_session import EOError,number,string
from test_live_state import fixture

class NPCServiceRangeTests(unittest.TestCase):
    def marble(self):
        s=fixture();s.state['map_id']=125;s.state['self'].update(map_id=125,x=6,y=4)
        s.state['npcs']=[dict(index=0,id=87,x=2,y=4)]
        s.snapshot=lambda:dict(shop=s.shop)
        return s
    def test_marble_shop_opens_from_customer_side_without_movement(self):
        s=self.marble();s.wait=lambda *args,**kwargs:number(87,2)+string('Marble')+b'\xff'
        data=s.shop_open(0)
        self.assertEqual(data['shop']['name'],'Marble');self.assertEqual(s.sent,[(13,13,number(0,2))]);self.assertFalse(s.pending_moves)
        s._near_shop()
    def test_shop_transactions_recheck_view_range_and_presence(self):
        s=self.marble();s.shop=dict(npc_index=0,map_id=125)
        s._near_shop();s.state['self']['x']=14
        with self.assertRaisesRegex(EOError,'closer'):s._near_shop()
        self.assertIsNone(s.shop)
    def test_shop_does_not_open_for_unseen_or_distant_npc(self):
        s=self.marble();s.state['self']['x']=14
        with self.assertRaises(EOError):s.shop_open(0)
        s.state['self']['x']=6
        with self.assertRaises(EOError):s.shop_open(99)
        self.assertFalse(s.sent)
    def test_bank_and_skillmaster_context_uses_live_npc_not_saved_tile(self):
        s=self.marble();context=dict(npc_index=0,map_id=125,x=2,y=4)
        s._near_service(context);s.state['npcs'].clear()
        with self.assertRaisesRegex(EOError,'within view'):s._near_service(context)
        s.state['npcs']=[dict(index=0,id=87,x=2,y=4)];context['map_id']=5
        with self.assertRaisesRegex(EOError,'again'):s._near_service(context)

if __name__=='__main__':unittest.main()
