"""Native chest ACKs, locks, open context and shared loot regressions."""
import unittest
from unittest.mock import patch
from eo_session import EOError,number
from test_live_state import fixture

rows=lambda *items:b''.join(number(i,2)+number(n,3) for i,n in items)
class ChestStateTests(unittest.TestCase):
    def opened(self):
        s=fixture();s.chest=dict(map_id=5,x=40,y=39,items=[dict(id=21,amount=2)])
        s.inventory=[dict(id=21,amount=5),dict(id=1,amount=100)]
        return s
    def test_open_uses_original_coords_packet_and_empty_is_valid(self):
        s=fixture()
        def ack(a):
            self.assertEqual(a,13);s.apply_event(33,13,number(40,1)+number(39,1));return b''
        s._wait_chest=ack;s.snapshot=lambda:dict(chest=s.chest)
        self.assertEqual(s.chest_open(40,39)['chest']['items'],[])
        self.assertEqual(s.sent,[(33,13,number(40,1)+number(39,1))])
    def test_deposit_and_take_only_mutate_bag_after_native_reply(self):
        s=self.opened();s.snapshot=lambda:dict(chest=s.chest)
        def ack(action):
            self.assertEqual(s.item_amount(21),5)
            s.apply_event(33,3,number(21,2)+number(3,4)+number(3,1)+number(70,1)+rows((21,4)))
        s._wait_chest=ack
        with patch('chests.item_definitions',return_value={21:dict(special=0)}):s.chest_change(False,21,2)
        self.assertEqual(s.item_amount(21),3);self.assertEqual(s.chest['items'],[dict(id=21,amount=4)])
        s.apply_event(33,27,number(21,2)+number(4,3)+number(7,1)+number(70,1))
        self.assertEqual(s.item_amount(21),7);self.assertEqual(s.chest['items'],[]);self.assertEqual(s.weight,7)
        self.assertEqual(s.sent[0],(33,7,number(40,1)+number(39,1)+number(21,2)+number(2,3)))
    def test_native_take_is_whole_stack_not_requested_quantity(self):
        s=self.opened();s.snapshot=lambda:{};s._wait_chest=lambda action:None
        s.chest_change(True,21,999)
        self.assertEqual(s.sent,[(33,9,number(40,1)+number(39,1)+number(21,2))]);self.assertEqual(s.item_amount(21),5)
    def test_gold_and_peer_updates_do_not_fabricate_rewards(self):
        s=self.opened();s.apply_event(33,5,rows((1,50000)))
        self.assertEqual(s.item_amount(1),100)
        s.apply_event(33,27,number(1,2)+number(50000,3)+number(5,1)+number(70,1))
        self.assertEqual(s.item_amount(1),50100)
    def test_locks_and_broken_chests_do_not_open_or_grant_items(self):
        for payload,word in [(number(1,2),'locked'),(b'N','broken')]:
            s=self.opened();s.apply_event(33,14,payload)
            self.assertIsNone(s.chest);self.assertIn(word,s.chest_rejection);self.assertEqual(s.item_amount(21),5)
    def test_distance_trade_closed_and_lore_are_rejected_before_send(self):
        s=self.opened();s.chest['x']=43
        with self.assertRaises(EOError):s.chest_change(True,21)
        s=self.opened();s.trade={'player_id':200}
        with self.assertRaisesRegex(EOError,'trade'):s.chest_change(True,21)
        s=self.opened()
        with patch('chests.item_definitions',return_value={21:dict(special=4)}):
            with self.assertRaisesRegex(EOError,'cannot'):s.chest_change(False,21)
        s.chest=None
        with self.assertRaises(EOError):s.chest_change(True,21)
        self.assertEqual(s.sent,[])
    def test_closed_or_departed_chest_ignores_shared_update(self):
        s=self.opened();s.snapshot=lambda:{};s.chest_close();s.apply_event(33,5,rows((21,99)));self.assertIsNone(s.chest);self.assertEqual(s.sent,[])
        s=self.opened();s.state['self']['x']=50;s.apply_event(33,5,rows((21,99)));self.assertIsNone(s.chest)
    def test_truncated_ack_is_atomic(self):
        s=self.opened()
        with self.assertRaises(EOError):s.apply_event(33,27,number(21,2)+number(2,3)+number(1,1)+number(70,1)+b'x')
        self.assertEqual(s.item_amount(21),5)
if __name__=='__main__':unittest.main()
