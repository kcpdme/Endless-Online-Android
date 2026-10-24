"""Native inn recovery requires a quote and real payment acknowledgement."""
import unittest
from unittest.mock import patch
from eo_session import EOError,number,string
from test_live_state import fixture

class InnStateTests(unittest.TestCase):
    def opened(self):
        s=fixture();s.state['self'].update(hp=20,maxhp=100,tp=4,maxtp=30)
        s.state['npcs']=[dict(id=150,index=7,x=40,y=39)]
        s.inn=dict(npc_index=7,npc_id=150,map_id=5,x=40,y=39,vendor_id=2,session_id=0)
        s.inventory=[dict(id=1,amount=1000)];s.snapshot=lambda:dict(inn=s.inn)
        return s
    def test_open_uses_original_citizen_flow(self):
        s=self.opened()
        s._wait_service=lambda f,a:s.apply_event(f,13,number(2,3)+number(0,1)+number(0,2)+b'\xff'+string('Question1')+string('Question2')+b'Question3')
        with patch('inns.npc_types',return_value={150:7}),patch.object(s,'_inn_sync_home'):
            s.inn_open(7)
        self.assertEqual(s.sent,[(49,13,number(7,2))]);self.assertEqual(s.inn['questions'],['Question1','Question2','Question3'])
    def test_quote_and_accept_are_separate_and_not_client_fabricated(self):
        s=self.opened();s._wait_service=lambda f,a:s.apply_event(f,1,number(106,4))
        s.inn_quote();self.assertEqual(s.inn['cost'],106);self.assertEqual(s.item_amount(1),1000);self.assertEqual(s.state['self']['hp'],20)
        s._wait_service=lambda f,a:s.apply_event(f,2,number(894,4))
        s.inn_sleep();self.assertEqual(s.item_amount(1),894);self.assertEqual(s.state['self']['hp'],100);self.assertEqual(s.state['self']['tp'],30);self.assertIsNone(s.inn)
        self.assertEqual([x[:2] for x in s.sent],[(49,1),(49,2)])
    def test_invalid_quote_money_and_range_rejected(self):
        s=self.opened()
        with self.assertRaises(EOError):s.inn_sleep()
        s.inn['cost']=1001
        with self.assertRaises(EOError):s.inn_sleep()
        s.state['self']['x']=80
        with self.assertRaises(EOError):s.inn_quote()
        self.assertFalse(s.sent)
    def test_full_health_and_tp_declines_without_timeout(self):
        s=self.opened();s.state['self'].update(hp=100,tp=30)
        with self.assertRaisesRegex(EOError,'already full'):s.inn_quote()
        self.assertFalse(s.sent)
    def test_cancel_and_walking_invalidate_quote(self):
        s=self.opened();s.inn['cost']=100;s.inn_close();self.assertIsNone(s.inn);self.assertFalse(s.sent)
        s=self.opened();s.move(3,1,5,41,40);self.assertIsNone(s.inn)
    def test_registration_requires_three_safe_answers_and_a_live_inn(self):
        s=self.opened();s.inn['questions']=['One','Two','Three']
        for answers in ([],['a'],['a','b',''],['a','b','x'*81],['a','b','bad\xff'],['a','b',123]):
            with self.assertRaises(EOError):s.inn_register(answers)
        self.assertFalse(s.sent)
        s.inn=None
        with self.assertRaises(EOError):s.inn_register(['a','b','c'])
        self.assertFalse(s.sent)
    def test_registration_changes_home_only_after_native_success(self):
        s=self.opened();s.inn['questions']=['One','Two','Three'];s.inn['current_home']={'name':'Aeven'}
        s._wait_service=lambda f,a:s.apply_event(f,3,number(2,1))
        with patch.object(s,'_inn_sync_home') as sync:
            s.inn_register([' a ','b','c']);sync.assert_not_called()
        self.assertFalse(s.inn['registration']['accepted']);self.assertEqual(s.inn['current_home']['name'],'Aeven')
        self.assertEqual(s.sent[-1],(49,3,number(0,2)+b'\xff'+number(2,2)+b'\xff'+string('a')+string('b')+b'c'))
        def home():s.inn['current_home']={'name':'Estaq'}
        s._wait_service=lambda f,a:s.apply_event(f,3,number(0,1))
        with patch.object(s,'_inn_sync_home',side_effect=home):s.inn_register(['a','b','c'])
        self.assertTrue(s.inn['registration']['accepted']);self.assertIn('Estaq',s.inn['notice'])
    def test_removal_rejection_preserves_home_and_success_queries_native(self):
        s=self.opened();s.inn['current_home']={'name':'Centaur'}
        s._wait_service=lambda f,a:s.apply_event(f,4,number(0,1))
        with patch.object(s,'_inn_sync_home') as sync:s.inn_remove();sync.assert_not_called()
        self.assertFalse(s.inn['removed']);self.assertEqual(s.inn['current_home']['name'],'Centaur')
        self.assertEqual(s.sent[-1],(49,4,number(2,2)))
        def home():s.inn['current_home']={'name':'Aeven'}
        s._wait_service=lambda f,a:s.apply_event(f,4,number(1,1))
        with patch.object(s,'_inn_sync_home',side_effect=home):s.inn_remove()
        self.assertTrue(s.inn['removed']);self.assertIn('Aeven',s.inn['notice'])
    def test_malformed_citizenship_ack_does_not_claim_success(self):
        for action,payload in ((3,number(4,1)),(4,number(2,1)),(3,b''),(4,b''),(3,number(0,1)+b'X')):
            s=self.opened()
            with self.assertRaises(RuntimeError):s.apply_event(49,action,payload)
            self.assertNotIn('registration',s.inn);self.assertNotIn('removed',s.inn)

    def test_malformed_ack_cannot_spend_gold_or_heal(self):
        s=self.opened()
        with self.assertRaises(RuntimeError):s.apply_event(49,2,b'\x01')
        self.assertEqual(s.item_amount(1),1000);self.assertEqual(s.state['self']['hp'],20)

if __name__=='__main__':unittest.main()
