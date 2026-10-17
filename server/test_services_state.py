"""Protocol regressions for storage guards and event-driven trade state."""
import unittest
from unittest.mock import patch
from eo_session import EOError,number,string
from test_live_state import fixture

def offers(*groups):
    return b''.join(number(pid,2)+b''.join(number(item,2)+number(qty,4) for item,qty in rows)+b'\xff' for pid,rows in groups)

class ServicesStateTests(unittest.TestCase):
    def test_trade_locks_inventory_and_storage_even_bank_withdraw(self):
        s=fixture();s.trade={'player_id':200};s.bank=dict(map_id=5,x=40,y=40,gold=500,token=0)
        with self.assertRaisesRegex(EOError,'trade'):s.bank_change(True,100)
        with self.assertRaisesRegex(EOError,'trade'):s.move(3,1,5,41,40)
        with self.assertRaisesRegex(EOError,'trade'):s.strike(0)
        self.assertEqual(s.sent,[])

    def test_locker_uses_server_remaining_quantity_and_whole_stack_get(self):
        s=fixture();s.inventory=[dict(id=21,amount=5)];s.locker=dict(map_id=5,x=40,y=39,items=[])
        s.apply_event(37,3,number(21,2)+number(3,4)+number(3,1)+number(70,1)+number(21,2)+number(2,3))
        self.assertEqual(s.item_amount(21),3);self.assertEqual(s.locker['items'],[dict(id=21,amount=2)])
        s.apply_event(37,27,number(21,2)+number(2,3)+number(5,1)+number(70,1))
        self.assertEqual(s.item_amount(21),5);self.assertEqual(s.locker['items'],[])

    def test_offer_change_resets_both_confirmations_and_never_moves_items(self):
        s=fixture();s.inventory=[dict(id=21,amount=5)];s.trade=dict(player_id=200,offers={},agreed=True,peer_agreed=True)
        s.apply_event(32,17,offers((100,[(21,2)]),(200,[(1,100)])))
        self.assertFalse(s.trade['agreed']);self.assertFalse(s.trade['peer_agreed']);self.assertEqual(s.item_amount(21),5)
        s.apply_event(32,14,number(200,2));self.assertIsNone(s.trade);self.assertEqual(s.item_amount(21),5)

    def test_trade_completion_decodes_by_owner_even_if_received_group_comes_first(self):
        s=fixture();s.inventory=[dict(id=21,amount=5),dict(id=1,amount=10)];s.trade=dict(player_id=200)
        with patch('services.item_definitions',return_value={21:dict(weight=1),1:dict(weight=0)}):
            s.apply_event(32,10,offers((200,[(1,100)]),(100,[(21,2)])))
        self.assertEqual(s.item_amount(1),110);self.assertEqual(s.item_amount(21),3);self.assertIsNone(s.trade)
        self.assertEqual(s.events[-1]['kind'],'trade_complete')

    def test_inspecting_another_player_never_replaces_your_gear(self):
        s=fixture();s.state['characters']=[dict(player_id=200,x=41,y=40)];s.equipment={'weapon':21}
        payload=b''.join(string(t) for t in ['other','Aeven','','','',''])+number(200,2)+number(0,1)*3+b''.join(number(281 if i==8 else 0,2) for i in range(15))
        s._wait_service=lambda *args:payload
        data=s.inspect_player(200)
        self.assertEqual(data['equipment']['weapon'],281);self.assertEqual(s.equipment,{'weapon':21})

    def test_native_roster_uses_global_players_request_and_preserves_public_metadata(self):
        s=fixture();s.request_online_players()
        self.assertEqual(s.sent,[(22,1,b'')])
        row=lambda name,title,icon,clas,guild:string(name)+string(title)+number(0,1)+number(icon,1)+number(clas,1)+string(guild)
        payload=number(8,1)+number(2,2)+b'\xff'+row('zeta','Traveler',0,5,'ABC')+row('alpha','',0,0,'   ')
        s.apply_event(255,255,payload)
        self.assertEqual([r['name'] for r in s.online_roster],['alpha','zeta'])
        self.assertEqual(s.online_roster[1]['guild'],'ABC');self.assertEqual(s.online_roster[1]['class_id'],5)
        self.assertTrue(s.dirty);self.assertEqual(s.events[-1]['kind'],'online_players')
        s.request_online_players();self.assertEqual(len(s.sent),1)
        self.assertEqual(s.events[-1]['players'],s.online_roster)
    def test_malformed_roster_is_rejected_without_fabricating_online_names(self):
        s=fixture()
        for payload in (number(8,1)+number(1,2)+b'\xff', number(8,1)+number(0,2)+b'x'):
            with self.assertRaises((RuntimeError,ValueError)):s.parse_online_players(payload)
        self.assertIsNone(s.online_roster)
    def test_original_local_pid_and_private_name_chat_formats(self):
        s=fixture();s.state['characters']=[dict(player_id=200,name='another')]
        s.apply_event(18,8,number(200,2)+b'hello')
        self.assertEqual((s.events[-1]['name'],s.events[-1]['channel'],s.events[-1]['message']),('another','local','hello'))
        s.apply_event(18,20,string('another')+string('private'))
        self.assertEqual((s.events[-1]['name'],s.events[-1]['channel']),('another','private'))
        s.apply_event(18,3,number(1,2)+b'missing')
        self.assertIn('not found',s.events[-1]['message'])

if __name__=='__main__':unittest.main()
