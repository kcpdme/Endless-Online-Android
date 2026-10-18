"""Native-only area completion, soda ACK/emote timers and original drunk chat."""
import random
import time
import unittest
from unittest.mock import patch
from test_skills_state import setup, payload
from test_live_state import fixture
from eo_session import number, Reader, EOError
from drunk_chat import make_drunk


class AreaStateTests(unittest.TestCase):
    def test_both_ice_blasts_cast_without_opponent_and_keep_original_chant(self):
        for spell in (14, 21):
            s=setup();s.spells.append(dict(id=spell,level=7));s.state['npcs']=[]
            result=s.cast_spell(spell,'area')
            self.assertEqual(result['seconds'],.48);self.assertEqual(s.casting['target_kind'],'area')
            self.assertEqual(s.stats['tp'],20)
            s.casting['release_at']=0;s.poll_spells()
            self.assertEqual([(f,a) for f,a,p in s.sent],[(12,1),(12,30)])
            self.assertEqual(s.stats['tp'],20,'Never predict native TP/damage')
            s.apply_event(231,3,payload((100,2),(spell,2),(40,1),(40,1),(19,2),(0,1)))
            self.assertIsNone(s.casting);self.assertEqual(s.stats['tp'],19)
            self.assertEqual(s.events[-1]['kind'],'spell_area');self.assertEqual(s.events[-1]['targets'],0)

    def test_area_ack_own_tp_only_and_protected_ordinary_self_targets(self):
        s=setup();s.apply_event(231,3,payload((200,2),(14,2),(41,1),(40,1),(77,2),(5,1)))
        self.assertEqual(s.stats['tp'],20);self.assertEqual(s.events[-1]['player_id'],200)
        for args in [(4,'area'),(4,'self'),(14,'npc',2)]:
            with self.assertRaises(EOError):s.cast_spell(*args)
        self.assertEqual(s.sent,[])

    def test_area_ack_rejects_impossible_target_count_or_unrelated_spell(self):
        for spell,count in ((14,6),(4,1)):
            s=setup()
            with self.assertRaises(EOError):s.apply_event(231,3,payload((100,2),(spell,2),(40,1),(40,1),(19,2),(count,1)))
            self.assertEqual(s.stats['tp'],20)

    def test_area_chant_survives_one_enemy_despawning_and_standard_kills_credit_exp(self):
        s=setup();s.spells.append(dict(id=14,level=0));s.cast_spell(14,'area')
        s.apply_event(26,25,number(1,2));self.assertIsNotNone(s.casting)
        s.casting['release_at']=0;s.poll_spells()
        p=payload((14,2),(100,2),(0,1),(2,2),(0,2),(0,2),(41,1),(40,1),(0,4),(5,3),(19,2),(1100,4))
        s.apply_event(44,16,p);self.assertEqual(s.stats['experience'],1100)
        s.apply_event(231,3,payload((100,2),(14,2),(40,1),(40,1),(19,2),(1,1)))
        self.assertIsNone(s.casting);self.assertEqual(s.stats['tp'],19)


class DrinkStateTests(unittest.TestCase):
    def soda(self,item=210,potency=10):
        s=fixture();s.inventory=[dict(id=item,amount=2)];s.state['self'].update(hp=50,maxhp=50,tp=30,maxtp=30)
        with patch('consumables.item_definitions',return_value={item:dict(type=22,beer_potency=potency)}),patch('consumables.time.monotonic',return_value=100):
            s.apply_event(14,3,payload((22,1),(item,2),(1,4),(1,1),(70,1)))
        return s

    def test_native_soda_ack_decrements_once_starts_original_duration_and_native_emote(self):
        for item,potency,seconds in ((210,10,25),(211,100,137.5)):
            s=self.soda(item,potency)
            self.assertEqual(s.item_amount(item),1);self.assertEqual(s.drunk_until,100+seconds)
            self.assertEqual(s.sent,[(9,21,number(11,1))])
            self.assertEqual(s.events[-1]['drunk_seconds'],seconds)
            self.assertEqual((s.state['self']['hp'],s.state['self']['tp']),(50,30))
            with patch('consumables.time.monotonic',return_value=100+seconds):s.poll_drunk()
            self.assertEqual(s.drunk_until,0);self.assertEqual(s.events[-1]['kind'],'drunk_ended')

    def test_unchanged_quantity_never_starts_cosmetic_effect(self):
        s=fixture();s.inventory=[dict(id=210,amount=2)]
        s.apply_event(14,3,payload((22,1),(210,2),(2,4),(1,1),(70,1)))
        self.assertEqual(getattr(s,'drunk_until',0),0);self.assertEqual(s.sent,[])

    def test_native_peer_emote_decode(self):
        s=fixture();s.apply_event(9,8,payload((200,2),(11,1)))
        self.assertEqual(s.events[-1]['kind'],'player_emote');self.assertEqual(s.events[-1]['player_id'],200);self.assertTrue(s.dirty)

    def test_original_chat_slurs_stars_hiccups_latin1_and_bounded_expansion(self):
        slurred=make_drunk('hello everyone i am exploring aeven',random.Random(4))
        self.assertNotEqual(slurred,'hello everyone i am exploring aeven')
        samples=' '.join(make_drunk('aeiou hello everyone i am exploring aeven',random.Random(i)) for i in range(20))
        self.assertIn('*hic*',samples);self.assertIn('*',samples)
        for value in ('a'*128,'x'*128,'é'*128,'a b '*32):
            result=make_drunk(value,random.Random(9));self.assertLessEqual(len(result.encode('latin1')),128)

    def test_chat_echo_and_native_payload_share_slur_but_admin_commands_untouched(self):
        s=fixture();s.state['self']['name']='devdrink';s.drunk_until=time.monotonic()+100;s.last_chat=0;s.snapshot=lambda:dict(events=list(s.events))
        with patch('drunk_chat.make_drunk',return_value='h*llo *hic*'):
            data=s.chat_send('local','hello')
        self.assertEqual(s.sent[-1],(18,21,b'h*llo *hic*'));self.assertTrue(data['events'][-1]['drunk'])
        self.assertEqual(data['events'][-1]['message'],'h*llo *hic*')
        s.stats['admin']=4;s.last_chat=0;s.chat_send('global','$warpmeto devother')
        self.assertEqual(s.sent[-1],(18,21,b'$warpmeto devother'))


if __name__=='__main__':unittest.main()
