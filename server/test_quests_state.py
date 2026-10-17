"""Original Quest packets and native class/karma changes; no invented rewards."""
import unittest
from unittest.mock import patch
from eo_session import EOError,number,string
from test_live_state import fixture


def dialog(links=((1,'Karma menu'),(2,'Class menu')),pages=('Hello stranger',),quest_id=4):
    return (number(1,1)+b''.join(number(n,2) for n in (4,quest_id,0,0))+b'\xff'+number(4,2)+string('Karma Quest (rep)')+
            b''.join(number(1,2)+string(text) for text in pages)+
            b''.join(number(2,2)+number(i,2)+string(text) for i,text in links))


class QuestsStateTests(unittest.TestCase):
    def opened(self):
        s=fixture();s.state['npcs']=[dict(id=166,index=7,x=40,y=39)]
        s.quest_context=dict(npc_index=7,npc_id=166,map_id=5,x=40,y=39)
        s.apply_event(50,34,dialog());return s

    def test_open_uses_original_quest_request_and_native_pages_links(self):
        s=fixture();s.state['npcs']=[dict(id=166,index=7,x=40,y=39)];s.snapshot=lambda:dict(quest_dialog=s.quest_dialog)
        s._wait_service=lambda f,a:s.apply_event(f,34,dialog())
        with patch('quests.npc_types',return_value={166:15}):result=s.quest_open(7)
        self.assertEqual(s.sent,[(50,10,number(7,2)+number(0,2))])
        self.assertEqual(result['quest_dialog']['pages'],['Hello stranger'])
        self.assertEqual(result['quest_dialog']['links'],[dict(id=1,text='Karma menu'),dict(id=2,text='Class menu')])

    def test_links_close_current_dialog_without_faking_class_or_karma(self):
        s=self.opened();s.stats=dict(class_id=0,karma=1000);s.snapshot=lambda:{}
        s.quest_reply(2)
        self.assertEqual(s.sent,[(50,2,b''.join(number(n,2) for n in (0,0,4,4))+number(2,1)+number(2,1))])
        self.assertIsNone(s.quest_dialog);self.assertIsNotNone(s.quest_context)
        self.assertEqual(s.stats,dict(class_id=0,karma=1000))
        with self.assertRaises(EOError):s.quest_reply(2)
        s.apply_event(50,34,dialog(((5,'Make me Warrior'),)))
        self.assertEqual(s.quest_dialog['links'][0]['id'],5)

    def test_unknown_npc_quest_link_range_and_trade_rejected(self):
        s=self.opened()
        for action in (0,-1,99,252):
            with self.assertRaises(EOError):s.quest_reply(action)
        with patch('quests.npc_types',return_value={166:15}):
            with self.assertRaises(EOError):s.quest_open(7,999)
            with self.assertRaises(EOError):s.quest_open(999)
        s.trade=dict(player_id=200)
        with self.assertRaises(EOError):s.quest_reply(1)
        s.trade=None;s.state['self']['x']=60
        with self.assertRaises(EOError):s.quest_reply(1)
        self.assertEqual(s.sent,[])

    def test_cancel_never_sends_ok_and_ignores_late_pages(self):
        s=self.opened();s.snapshot=lambda:{};s.quest_close();s.apply_event(50,34,dialog())
        self.assertIsNone(s.quest_dialog);self.assertIsNone(s.quest_context);self.assertEqual(s.sent,[])

    def test_walking_invalidates_quest_context(self):
        s=self.opened();s.move(3,1,5,41,40)
        self.assertIsNone(s.quest_dialog);self.assertIsNone(s.quest_context)

    def test_native_class_ack_preserves_distinct_attributes_and_updates_capacity(self):
        s=fixture();s.stats=dict(level=120,hp=100,experience=800)
        values=(6,11,12,13,14,15,16,1000,2000,3000,110,21,22,23,24,25)
        s.apply_event(42,18,b''.join(number(n,2) for n in values))
        self.assertEqual(s.stats['class_id'],6);self.assertEqual(s.stats['intelligence'],12);self.assertEqual(s.stats['wisdom'],13)
        self.assertEqual(s.stats['max_hp'],1000);self.assertEqual(s.stats['armor'],25);self.assertEqual(s.max_weight,110)
        self.assertEqual(s.stats['level'],120);self.assertEqual(s.events[-1]['kind'],'class_changed');self.assertTrue(s.dirty)

    def test_native_karma_reply_zero_level_does_not_reset_character_level(self):
        s=fixture();s.stats=dict(level=120,karma=1000)
        s.apply_event(42,3,number(12345,4)+number(1100,2)+number(0,1))
        self.assertEqual(s.stats['karma'],1100);self.assertEqual(s.stats['level'],120);self.assertEqual(s.stats['experience'],12345)
        self.assertEqual(s.events[-1]['kind'],'quest_stats');self.assertTrue(s.dirty)
        s.apply_event(35,13,b'Class menu opened');self.assertEqual(s.events[-1]['message'],'Class menu opened')

    def test_truncated_dialog_and_class_stats_are_atomic(self):
        s=self.opened();old=s.quest_dialog.copy();s.stats=dict(class_id=1)
        with self.assertRaises((RuntimeError,ValueError)):s.apply_event(50,34,dialog()[:-1])
        self.assertEqual(s.quest_dialog,old)
        with self.assertRaises(RuntimeError):s.apply_event(42,18,number(6,2))
        self.assertEqual(s.stats,dict(class_id=1))

    def test_native_quest_item_removal_updates_only_acknowledged_inventory(self):
        s=fixture();s.inventory=[dict(id=21,amount=5)]
        s.apply_event(14,11,number(21,2)+number(3,4)+number(3,1))
        self.assertEqual(s.item_amount(21),3);self.assertEqual(s.weight,3);self.assertEqual(s.state['items'],[])


if __name__=='__main__':unittest.main()
