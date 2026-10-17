"""Exact native potion/EXP/cure packets and no-consumption guards."""
import unittest
from unittest.mock import patch
from eo_session import number,EOError
from test_live_state import fixture

class ConsumableStateTests(unittest.TestCase):
    def test_quick_potion_returns_immediately_while_walking_and_casting(self):
        import time
        s=fixture();s.inventory=[dict(id=2,amount=2)];s.state['self'].update(hp=1,maxhp=50,tp=0,maxtp=20)
        s.pending_moves.append(dict(seq=1));s.casting={'released':False}
        with patch('consumables.item_definitions',return_value={2:dict(type=3,hp=20,tp=0)}):
            before=time.monotonic();reply=s.use_potion(2);self.assertLess(time.monotonic()-before,.02)
            self.assertTrue(reply['sent']);self.assertEqual(s.item_amount(2),2)
            self.assertEqual(s.stats.get('hp'),None);self.assertEqual(s.sent[-1][:2],(14,10))
            self.assertEqual(len(s.potion_queue()),1)
        s.apply_event(14,3,number(3,1)+number(2,2)+number(1,4)+number(3,1)+number(70,1)+number(20,4)+number(21,2)+number(0,2))
        self.assertIsNone(s.pending_potion);self.assertEqual(s.item_amount(2),1);self.assertEqual(s.stats['hp'],21)
        self.assertEqual(len(s.pending_moves),1);self.assertIsNotNone(s.casting)
    def test_four_rapid_taps_pipeline_without_optimistic_consumption(self):
        s=fixture();s.inventory=[dict(id=2,amount=20)];s.state['self'].update(hp=1,maxhp=1000,tp=0,maxtp=20)
        with patch('consumables.item_definitions',return_value={2:dict(type=3,hp=20,tp=0)}):
            for _ in range(4):self.assertTrue(s.use_potion(2)['sent'])
            with self.assertRaisesRegex(EOError,'queued'):s.use_potion(2)
        self.assertEqual(len(s.sent),4);self.assertEqual(s.item_amount(2),20)
        for i in range(4):
            s.apply_event(14,3,number(3,1)+number(2,2)+number(19-i,4)+number(3,1)+number(70,1)+number(20,4)+number(21+20*i,2)+number(0,2))
        self.assertIsNone(s.pending_potion);self.assertEqual(s.item_amount(2),16);self.assertEqual(s.stats['hp'],81)
    def test_queued_potions_do_not_overconsume_past_full_health(self):
        s=fixture();s.inventory=[dict(id=2,amount=20)];s.state['self'].update(hp=40,maxhp=50,tp=0,maxtp=20)
        with patch('consumables.item_definitions',return_value={2:dict(type=3,hp=20,tp=0)}):
            s.use_potion(2)
            with self.assertRaisesRegex(EOError,'cover'):s.use_potion(2)
        self.assertEqual(len(s.sent),1);self.assertEqual(s.item_amount(2),20)

    def test_native_noop_potion_ack_keeps_item_and_releases_pending(self):
        s=fixture();s.inventory=[dict(id=2,amount=2)];s.state['self'].update(hp=50,maxhp=50,tp=0,maxtp=20)
        s.set_potion_queue([dict(id=2,until=99999999,hp=20,tp=0)])
        s.apply_event(14,3,number(3,1)+number(2,2)+number(2,4)+number(3,1)+number(70,1)+number(0,4)+number(50,2)+number(0,2))
        self.assertIsNone(s.pending_potion);self.assertEqual(s.item_amount(2),2)
        self.assertEqual(s.events[-1]['consumed'],0);self.assertEqual(s.stats['hp'],50)

    def test_legacy_item_use_cannot_mistake_an_earlier_potion_reply(self):
        s=fixture();s.inventory=[dict(id=2,amount=2)];s.state['self'].update(hp=1,maxhp=50,tp=0,maxtp=20)
        s.set_potion_queue([dict(id=2,until=99999999,hp=20,tp=0)])
        with patch('consumables.item_definitions',return_value={2:dict(type=3,hp=20,tp=0)}):
            with self.assertRaisesRegex(EOError,'potions to finish'):s.use_item(2)
        self.assertEqual(s.sent,[]);self.assertEqual(s.item_amount(2),2)

    def test_async_potion_rejection_does_not_disconnect_or_change_inventory(self):
        s=fixture();s.pending_potion={'id':2,'until':99999999};s.using_item=2;s.inventory=[dict(id=2,amount=2)]
        s.apply_event(14,5,number(2,2))
        self.assertEqual(s.item_amount(2),2);self.assertIsNone(s.pending_potion)
        self.assertEqual(s.events[-1]['kind'],'item_use_failed');self.assertTrue(s.dirty)
    def test_async_potion_timeout_unlocks_without_inventing_healing(self):
        s=fixture();s.pending_potion={'id':2,'until':0};s.using_item=2
        s.poll_actions();self.assertIsNone(s.pending_potion)
        self.assertEqual(s.events[-1]['kind'],'item_use_failed')

    def test_heal_reply_updates_exact_remaining_weight_hp_and_tp(self):
        s=fixture();s.inventory=[dict(id=9,amount=4)];s.state['self'].update(hp=1,maxhp=50,tp=0,maxtp=20)
        s.apply_event(14,3,number(3,1)+number(9,2)+number(3,4)+number(3,1)+number(70,1)+number(20,4)+number(21,2)+number(10,2))
        self.assertEqual((s.item_amount(9),s.weight,s.stats['hp'],s.stats['tp']),(3,3,21,10))
        self.assertEqual(s.state['self']['hp'],21);self.assertEqual(s.events[-1]['hp_gain'],20);self.assertTrue(s.dirty)

    def test_full_health_never_sends_or_decrements_a_health_potion(self):
        s=fixture();s.inventory=[dict(id=2,amount=2)];s.state['self'].update(hp=50,maxhp=50,tp=0,maxtp=20)
        with patch('consumables.item_definitions',return_value={2:dict(type=3,hp=20,tp=0)}):
            with self.assertRaisesRegex(EOError,'already full'):s.use_item(2)
        self.assertEqual(s.sent,[]);self.assertEqual(s.item_amount(2),2)

    def test_exp_reward_without_level_up_keeps_existing_level(self):
        s=fixture();s.state['self']['level']=10;s.inventory=[dict(id=500,amount=1)]
        payload=number(6,1)+number(500,2)+number(0,4)+number(0,1)+number(70,1)+number(150000,4)+number(0,1)+b''.join(number(i,2) for i in (5,6,50,30,10))
        s.apply_event(14,3,payload)
        self.assertEqual(s.state['self']['level'],10);self.assertEqual(s.stats['experience'],150000);self.assertEqual(s.item_amount(500),0)

    def test_trade_guard_precedes_item_use(self):
        s=fixture();s.trade={'player_id':200}
        with self.assertRaisesRegex(EOError,'trade'):s.use_item(2)
        self.assertEqual(s.sent,[])

    def test_cure_uses_native_stat_order_and_destroys_only_cursed_gear(self):
        s=fixture();s.inventory=[dict(id=13,amount=1)];s.equipment={'weapon':99,'boots':80}
        definitions={99:dict(special=5,graphic_value=9),80:dict(special=0,graphic_value=1)}
        values=[50,30,2,3,7,5,6,9,1,4,10,11,12]
        with patch('consumables.item_definitions',return_value=definitions):
            s.apply_event(14,3,number(25,1)+number(13,2)+number(0,4)+number(2,1)+number(70,1)+b''.join(number(i,2) for i in values))
        self.assertEqual(s.equipment,{'weapon':0,'boots':80});self.assertEqual(s.stats['intelligence'],3);self.assertEqual(s.stats['wisdom'],7)
        self.assertEqual(s.state['self']['equipment_graphics'][8],0);self.assertEqual(s.item_amount(13),0)

if __name__=='__main__':unittest.main()
