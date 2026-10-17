"""Native casting timestamps, target authorization, inventory and observer decoding."""
import time, unittest
from unittest.mock import patch
from test_live_state import fixture
from eo_session import EOError,Reader,number

def setup():
    s=fixture();s.init_skills();s.spells=[dict(id=1,level=0),dict(id=4,level=0),dict(id=5,level=0)]
    s.state['self'].update(hp=10,maxhp=30,tp=20,maxtp=30,level=1)
    s.state['npcs']=[dict(id=1,index=2,x=41,y=40)]
    s.stats.update(hp=10,tp=20,skill_points=2)
    return s

def payload(*fields):return b''.join(number(value,size) for value,size in fields)

class SkillsStateTests(unittest.TestCase):
    def test_chant_does_not_block_and_release_uses_original_ticks(self):
        s=setup();before=time.monotonic();result=s.cast_spell(4,'npc',2)
        self.assertLess(time.monotonic()-before,.02);self.assertEqual(result['seconds'],.96)
        start=s.timestamp;self.assertEqual(s.sent[0][:2],(12,1));self.assertEqual(s.state['self']['tp'],20)
        s.casting['release_at']=time.monotonic()-1;s.poll_actions()
        self.assertEqual(s.sent[-1][:2],(12,31));r=Reader(s.sent[-1][2]);self.assertEqual(r.num(),2);r.take(3)
        self.assertEqual((r.num(2),r.num(2),r.num(3)),(4,2,start+96))
        self.assertFalse(s.metrics['refreshes']);self.assertEqual(len(s.sent),2)
    def test_self_heal_original480ms_chant_and_no_second_gateway_cooldown(self):
        s=setup()
        with patch('skills.time.monotonic',return_value=100):
            result=s.cast_spell(1,'self')
        self.assertEqual(result['seconds'],.48)
        with patch('skills.time.monotonic',return_value=100.479):s.poll_spells()
        self.assertEqual(len(s.sent),1,'Never release Self Heal before the original480ms chant')
        with patch('skills.time.monotonic',return_value=100.48):s.poll_spells()
        self.assertEqual(s.sent[-1][:2],(12,30))
        self.assertTrue(s.casting['released'])
        s.apply_event(12,30,payload((100,2),(1,2),(4,4),(47,1),(14,2),(19,2)))
        with patch('skills.time.monotonic',return_value=100.50):
            s.cast_spell(1,'self')
        self.assertIsNotNone(s.casting,'Native SpellCooldownTime owns recovery; gateway must not reject a valid new preparation')

    def test_full_health_self_heal_is_not_sent_or_left_casting(self):
        s=setup();s.state['self']['hp']=30
        with self.assertRaisesRegex(EOError,'already full'):s.cast_spell(1,'self')
        self.assertIsNone(s.casting);self.assertEqual(s.sent,[]);self.assertEqual(s.stats['tp'],20)
    def test_heal_ack_still_completes_if_potion_filled_hp_during_chant(self):
        s=setup();s.cast_spell(1,'self');s.state['self']['hp']=30
        s.apply_event(12,30,payload((100,2),(1,2),(4,4),(100,1),(30,2),(19,2)))
        self.assertIsNone(s.casting);self.assertEqual(s.events[-1]['hp_gain'],0);self.assertEqual(s.stats['tp'],19)
    def test_small_thunder_native_hit_and_no_dropped_reply_for_pruned_target(self):
        s=setup();s.cast_spell(5,'npc',2);s.casting['released']=True;s.state['npcs'].clear()
        s.apply_event(44,3,payload((5,2),(100,2),(0,1),(2,2),(3,3),(99,2),(18,2)))
        self.assertIsNone(s.casting);self.assertEqual(s.stats['tp'],18)
        self.assertEqual(s.events[-1]['x'],41);self.assertTrue(s.events[-1]['own_cast'])
    def test_target_died_during_chant_cancels_before_release(self):
        s=setup();s.cast_spell(5,'npc',2);s.state['npcs'].clear();s.casting['release_at']=0;s.poll_spells()
        self.assertIsNone(s.casting);self.assertEqual(s.events[-1]['kind'],'spell_failed')
        self.assertIn('no longer',s.events[-1]['message'])
    def test_spell_kill_announces_native_exp_difference_only_to_recipient(self):
        s=setup();s.stats['experience']=1000
        p=payload((5,2),(100,2),(0,1),(2,2),(0,2),(0,2),(41,1),(40,1),(0,4),(3,3),(18,2),(1100,4))
        s.apply_event(44,16,p);self.assertEqual(s.events[-1]['exp_gain'],100)
        observer=setup();observer.player_id=200;observer.stats['experience']=500
        observer.apply_event(44,16,p[:-4]);self.assertNotIn('exp_gain',observer.events[-1]);self.assertEqual(observer.stats['experience'],500)

    def test_unknown_tp_target_and_range_refused_before_sending(self):
        s=setup()
        for args in [(6,'npc',2),(1,'npc',2),(4,'npc',99),(4,'player',100)]:
            with self.assertRaises(EOError):s.cast_spell(*args)
        s.state['self']['tp']=0
        with self.assertRaisesRegex(EOError,'TP'):s.cast_spell(4,'npc',2)
        s.state['self']['tp']=20;s.state['npcs'][0]['x']=60
        with self.assertRaisesRegex(EOError,'far'):s.cast_spell(4,'npc',2)
        self.assertFalse(s.sent)
    def test_movement_preserves_chant_and_release_has_independent_timestamp(self):
        s=setup();s.cast_spell(4,'npc',2);start=s.casting['timestamp']
        for seq in range(1,5):
            s.move(0,seq,5,40,40+seq)
        self.assertIsNotNone(s.casting);self.assertEqual(s.stats['tp'],20)
        latest=s.timestamp;s.casting['release_at']=time.monotonic()-1;s.poll_actions()
        r=Reader(s.sent[-1][2]);r.take(8)
        self.assertEqual(r.num(3),start+96);self.assertEqual(s.timestamp,latest)
        self.assertTrue(s.casting['released'])
    def test_damage_and_tp_are_native_acknowledged_only_for_caster(self):
        p=payload((4,2),(100,2),(0,1),(2,2),(5,3),(50,2),(19,2))
        s=setup();s.cast_spell(4,'npc',2);s.apply_event(44,3,p)
        self.assertEqual(s.stats['tp'],19);self.assertIsNone(s.casting);self.assertEqual(s.events[-1]['spell_id'],4)
        observer=setup();observer.player_id=200;observer.apply_event(44,3,p)
        self.assertEqual(observer.stats['tp'],20)
    def test_spell_kill_drop_exp_and_levelup_use_cast_prefix(self):
        s=setup();s.cast_spell(4,'npc',2);s.casting['released']=True
        p=payload((4,2),(100,2),(0,1),(2,2),(8,2),(249,2),(41,1),(40,1),(2,4),(5,3),(19,2),(1100,4),(2,1),(3,2),(3,2),(40,2),(40,2),(20,2))
        s.apply_event(44,2,p)
        self.assertEqual(s.stats['experience'],1100);self.assertEqual(s.stats['level'],2);self.assertEqual(s.stats['tp'],19)
        self.assertFalse(s.state['npcs']);self.assertEqual(s.state['items'][0]['id'],249);self.assertEqual(s.drop_guards[8][0],100)
        observer=setup();observer.player_id=200;observer.apply_event(44,16,p[:22]);self.assertEqual(observer.stats['tp'],20)
        self.assertNotIn('experience',observer.stats)
    def test_other_player_kill_during_our_chant_does_not_replace_our_tp(self):
        s=setup();s.cast_spell(4,'npc',2)
        p=payload((4,2),(200,2),(0,1),(2,2),(0,2),(0,2),(41,1),(40,1),(0,4),(10,3),(99,2))
        s.apply_event(44,16,p)
        self.assertEqual(s.stats['tp'],20)
        self.assertIsNone(s.casting) # another player killed the selected target; stop waiting

    def test_self_heal_native_hp_tp_and_observer_effect(self):
        s=setup();s.cast_spell(1,'self')
        s.apply_event(12,30,payload((100,2),(1,2),(4,4),(47,1),(14,2),(19,2),(1,2)))
        self.assertEqual((s.stats['hp'],s.stats['tp']),(14,19));self.assertIsNone(s.casting)
        self.assertEqual(s.events[-1]['kind'],'spell_heal')
    def test_skill_train_learn_forget_acknowledgements(self):
        s=setup();s.apply_event(16,2,payload((1,2),(4,2),(1,2)))
        self.assertEqual(s.stats['skill_points'],1);self.assertEqual(next(x['level'] for x in s.spells if x['id']==4),1)
        s.apply_event(16,9,payload((5,2),(500,4)));self.assertEqual(s.item_amount(1),500)
        self.assertTrue(any(x['id']==5 for x in s.spells))
        s.apply_event(16,4,number(5,2));self.assertFalse(any(x['id']==5 for x in s.spells))
    def test_cast_timeout_unlocks_without_inventory_or_tp_invention(self):
        s=setup();s.cast_spell(4,'npc',2);s.casting.update(released=True,timeout_at=time.monotonic()-1);s.poll_actions()
        self.assertIsNone(s.casting);self.assertEqual(s.stats['tp'],20);self.assertEqual(s.events[-1]['kind'],'spell_failed')
    def test_storage_and_duplicate_cast_are_blocked_during_chant(self):
        s=setup();s.cast_spell(4,'npc',2)
        with self.assertRaisesRegex(EOError,'finish'):s.cast_spell(4,'npc',2)
        with self.assertRaisesRegex(EOError,'finish'):s.drop_item(2,1)

class SkillTrainingFeedbackTests(unittest.TestCase):
    def test_training_ack_reports_new_level_after_native_spending(self):
        s=fixture();s.spells=[dict(id=1,level=7)];s.stats['skill_points']=3
        s.apply_event(16,2,number(2,2)+number(1,2)+number(8,2))
        self.assertEqual(s.spells,[dict(id=1,level=8)])
        self.assertEqual(s.stats['skill_points'],2)
        self.assertEqual((s.events[-1]['action'],s.events[-1]['old_level'],s.events[-1]['level']),('trained',7,8))

if __name__=='__main__':unittest.main()
