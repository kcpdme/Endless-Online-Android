import unittest
from unittest.mock import patch
from eo_session import number,EOError
from test_live_state import fixture

def n(*pairs):return b''.join(number(value,width) for value,width in pairs)

def session():
    s=fixture();s.init_skills();s.init_party();s.stats.update(hp=50,max_hp=100,tp=20,max_tp=20)
    s.state['self'].update(name='tester',hp=50,maxhp=100,tp=20,maxtp=20)
    return s

class FeatureStateTests(unittest.TestCase):
    def test_drains_are_native_and_support_peer_rows(self):
        s=session();s.apply_event(31,31,n((5,2),(45,2),(100,2),(200,2),(40,1),(6,2)))
        self.assertEqual(s.stats['hp'],45);self.assertEqual(s.state['self']['hp'],45)
        self.assertEqual(s.events[-2]['source'],'drain');self.assertEqual(s.events[-1]['player_id'],200)
        self.assertTrue(s.dirty)
        s.apply_event(31,16,n((1,1),(3,2),(17,2),(20,2)))
        self.assertEqual((s.stats['tp'],s.state['self']['tp']),(17,17))

    def test_malformed_drains_do_not_mutate_state(self):
        s=session()
        for payload in (b'',n((5,2),(45,2),(100,2))+b'X'):
            with self.assertRaises(EOError):s.apply_event(31,31,payload)
            self.assertEqual(s.stats['hp'],50)

    def test_pk_packets_identify_attacker_and_victim_and_clear_dead_movement(self):
        s=session();s.pending_moves.append({'seq':1});s.last_input_seq=1
        s.apply_event(23,3,n((200,2),(100,2),(50,3),(0,1),(0,1),(1,1)))
        self.assertEqual(s.events[-1]['attacker_id'],200);self.assertTrue(s.stats['dead'])
        self.assertEqual(s.stats['hp'],0);self.assertFalse(s.pending_moves)
        s=session();s.apply_event(23,3,n((0,2),(200,2),(10,3),(0,1),(40,1),(0,1)))
        self.assertEqual(s.events[-1]['kind'],'peer_damage');self.assertEqual(s.events[-1]['attacker_id'],100)
        self.assertEqual(s.stats['hp'],50)
        s.apply_event(23,17,n((200,2),(100,2),(10,3),(0,1),(40,1),(0,1),(4,2)))
        self.assertEqual(s.events[-1]['spell_id'],4)

    def test_quake_and_npc_chatter_are_distinct_from_npc_movement(self):
        s=session();s.state['npcs']=[dict(id=192,index=5,x=40,y=41,direction=0)]
        s.apply_event(31,10,n((1,1),(8,1)));self.assertEqual(s.events[-1]['kind'],'quake')
        s.apply_event(26,8,b'\xff\xff'+n((5,1),(5,1))+b'Hello')
        self.assertEqual(s.events[-1]['message'],'Hello');self.assertEqual(s.state['npcs'][0]['x'],40)
        with self.assertRaises((EOError,RuntimeError)):s.apply_event(26,8,b'\xff\xff'+n((5,1),(8,1))+b'Hi')

    def test_account_operations_require_verified_menu_identity(self):
        s=session()
        with self.assertRaises(EOError):s.delete_character(1,'tester')
        with self.assertRaises(EOError):s.change_password('old','newpassword')
        s.state=None;s.account_name='tester';s.characters=[dict(id=1,name='tester')]
        with self.assertRaises(EOError):s.delete_character(1,'another')
        with self.assertRaises(EOError):s.delete_character(2,'tester')
        self.assertEqual(s.sent,[])

    def test_service_mutations_require_context_and_correct_location(self):
        s=session()
        for kind,action in [('board','post'),('jukebox','play'),('law','approve'),('priest','request'),('reset','reset')]:
            with self.assertRaises(EOError):s.feature_action(kind,action,text='tester',body='test')
        for action in ('accept','vow'):
            with self.assertRaises(EOError):s.feature_action('priest',action)
        s.feature_context=dict(kind='board',map_id=6,x=40,y=40,board_id=0)
        with self.assertRaises(EOError):s.feature_action('board','post',text='test',body='test')
        self.assertEqual(s.sent,[])

    def test_find_and_wedding_async_events(self):
        s=session();s.apply_event(22,241,b'tester');self.assertEqual(s.find_status,'nearby on this map')
        s.apply_event(46,1,n((1,2))+b'partner');self.assertEqual(s.wedding_pending['action'],'accept')
        s.apply_event(46,3,n((6,2)));self.assertEqual(s.wedding_pending['action'],'vow')

    def test_native_quest_item_costs_and_non_gold_rewards(self):
        s=session();s.inventory=[dict(id=337,amount=5)]
        s.apply_event(14,28,n((337,2),(0,4),(0,1)))
        self.assertEqual(s.item_amount(337),0)
        s.apply_event(14,26,n((492,2),(1,3),(0,1)))
        self.assertEqual(s.item_amount(492),1);self.assertTrue(s.dirty)
        with self.assertRaises(EOError):s.apply_event(14,26,n((492,2),(1,3),(0,1))+b"X")
        self.assertEqual(s.item_amount(492),1)

    def test_invalid_emotes_and_unsafe_text_never_send(self):
        s=session()
        for ident in (0,11,12,13,15,999):
            with self.assertRaises(EOError):s.feature_action('emotes','emote',ident)
        for text in ('','bad\x00text','bad\xfftext','X'*257):
            with self.assertRaises(EOError):s.feature_action('report','help',body=text)
        self.assertEqual(s.sent,[])

    def test_multiline_messages_preserve_lines_without_protocol_delimiters(self):
        from native_features import message_text
        self.assertEqual(message_text('First\r\nSecond',multiline=True),'First\nSecond')
        with self.assertRaises(EOError):message_text('Subject\nInjected')
        with self.assertRaises(EOError):message_text('Body\xffInjected',multiline=True)

if __name__=='__main__':unittest.main()
