"""Native party, group and targeted heal protocols and bard validation."""
import unittest,time
from unittest.mock import patch
from eo_session import EOError,number,Reader
from test_skills_state import setup,payload

def fixture():
 s=setup();s.init_party();s.spells += [dict(id=i,level=0) for i in (3,6,8,17,18)]
 s.state['characters']=[dict(player_id=200,name='devpeer',x=41,y=40)]
 s.party_members=[dict(player_id=100,name='devactor',leader=True,level=1,hp_percent=33),dict(player_id=200,name='devpeer',leader=False,level=1,hp_percent=10)]
 s.snapshot=lambda:dict(party=s.party_members,invitation=s.party_invitation)
 return s
class PartyStateTests(unittest.TestCase):
 def test_group_chant_uses_group_release_and_ack_owns_hp_and_tp(self):
  s=fixture();s.cast_spell(3,'group');s.casting['release_at']=0;s.poll_spells()
  self.assertEqual(s.sent[-1][:2],(12,33));r=Reader(s.sent[-1][2]);self.assertEqual(r.num(2),3)
  self.assertEqual(s.stats['tp'],20)
  packet=payload((3,2),(100,2),(0,2),(20,2))+b'\xff'*5+payload((100,2),(100,1),(30,2))+b'\xff'*5+payload((200,2),(50,1),(21,2))
  s.apply_event(12,33,packet)
  self.assertIsNone(s.casting);self.assertEqual((s.stats['hp'],s.stats['tp']),(30,0));self.assertEqual(s.party_members[1]['hp_percent'],50)
  other=fixture();other.player_id=200;other.apply_event(12,33,packet)
  self.assertEqual((other.stats['hp'],other.stats['tp']),(21,20));self.assertEqual(other.events[-1]['kind'],'spell_group')
 def test_group_requires_party_and_cancels_if_party_leaves_during_chant(self):
  s=fixture();s.party_members=[]
  with self.assertRaisesRegex(EOError,'party'):s.cast_spell(3,'group')
  self.assertFalse(s.sent)
  s=fixture();s.cast_spell(18,'group');s.party_members=[];s.casting['release_at']=0;s.poll_spells()
  self.assertIsNone(s.casting);self.assertEqual(s.events[-1]['kind'],'spell_failed')
 def test_admin_and_large_heal_target_self_or_nearby_player(self):
  for ident in (6,8):
   for pid in (100,200):
    s=fixture();s.state['self']['tp']=100;s.cast_spell(ident,'player',pid);s.casting['release_at']=0;s.poll_spells()
    r=Reader(s.sent[-1][2]);self.assertEqual(r.num(),1);r.take(3);self.assertEqual((r.num(2),r.num(2)),(ident,pid))
 def test_player_leaving_during_chant_cancels(self):
  s=fixture();s.cast_spell(6,'player',200);s.state['characters']=[];s.casting['release_at']=0;s.poll_spells()
  self.assertIsNone(s.casting);self.assertIn('no longer',s.events[-1]['message'])
 def test_target_heal_native_hp_and_recover_tp(self):
  s=fixture();s.cast_spell(6,'player',100)
  s.apply_event(12,31,payload((100,2),(100,2),(0,1),(6,2),(5000,4),(100,1),(30,2)))
  s.apply_event(42,8,payload((30,2),(18,2)))
  self.assertEqual((s.stats['hp'],s.stats['tp']),(30,18));self.assertIsNone(s.casting)
 def test_invite_join_accept_decline_native_packets_and_expiry(self):
  s=fixture();s.party_members=[];s.party_action('invite',200);self.assertEqual(s.sent[-1],(24,1,payload((1,1),(200,2))))
  s.apply_event(24,1,payload((0,1),(200,2))+b'devpeer');s.party_action('accept');self.assertEqual(s.sent[-1],(24,2,payload((0,1),(200,2))))
  s.apply_event(24,1,payload((1,1),(200,2))+b'devpeer');s.party_action('decline');self.assertIsNone(s.party_invitation)
  with self.assertRaises(EOError):s.party_action('accept')
 def test_create_roster_hp_join_remove_and_close(self):
  s=fixture();row=lambda pid,lead,name:payload((pid,2),(lead,1),(5,1),(60,1))+name+b'\xff'
  s.apply_event(24,6,row(100,1,b'devactor')+row(200,0,b'devpeer'));self.assertEqual(len(s.party_members),2)
  s.apply_event(24,7,row(300,0,b'devthird')[:-1]);self.assertEqual(len(s.party_members),3)
  s.apply_event(24,5,payload((200,2),(90,1)));self.assertEqual(s.party_members[1]['hp_percent'],90)
  s.apply_event(24,4,number(300,2));self.assertEqual(len(s.party_members),2)
  s.apply_event(24,14,b'\xff');self.assertFalse(s.party_members)
 def test_nonleader_and_outsider_cannot_kick(self):
  s=fixture();s.player_id=200
  with self.assertRaises(EOError):s.party_action('kick',100)
  s.player_id=100
  with self.assertRaises(EOError):s.party_action('kick',300)
  s.party_action('kick',200);self.assertEqual(s.sent[-1],(24,4,number(200,2)))
 def test_party_chat_decode_and_no_nonmember_send(self):
  s=fixture();s.apply_event(18,13,number(200,2)+b'hi');self.assertEqual(s.events[-1]['channel'],'party')
  s.party_members=[]
  with self.assertRaises(EOError):s.chat_send('party','hi')
 def test_party_exp_gain_and_native_level_flag(self):
  s=fixture();s.stats.update(experience=100,level=1,stat_points=0,skill_points=0)
  with patch('party.level_points',return_value={'StatPerLevel':3,'SkillPerLevel':3}):s.apply_event(24,33,payload((100,2),(25,4),(1,1)))
  self.assertEqual((s.stats['experience'],s.stats['level'],s.stats['stat_points'],s.stats['skill_points']),(125,2,3,3));self.assertEqual(s.sent[-1][:2],(25,1))
 def test_bard_requires_learned_skill_equipped_native_instrument_valid_note(self):
  s=fixture();s.equipment={'weapon':349}
  s.bard_note(35);self.assertEqual(s.sent[-1],(21,10,payload((49,1),(35,1))));self.assertEqual(s.events[-1]['kind'],'bard_note')
  for note in (-1,36,True,1.5):
   with self.assertRaises(EOError):s.bard_note(note)
  s.spells=[]
  with self.assertRaises(EOError):s.bard_note(0)
  s=fixture();s.equipment={'weapon':21}
  with self.assertRaises(EOError):s.bard_note(0)
 def test_bard_observer_uses_native_note_instrument_direction(self):
  s=fixture();s.apply_event(21,15,payload((200,2),(2,1),(50,1),(0,1)))
  self.assertEqual(s.events[-1],dict(family=21,action=15,bytes=5,kind='bard_note',player_id=200,direction=2,instrument=50,note=0))
if __name__=='__main__':unittest.main()
