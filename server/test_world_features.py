"""Native seating, command routing, ground expiry and item-weight regressions."""
import unittest
from eo_session import EOError, number, string
from configure_world import patch_item_weights, weightless_consumable
from test_live_state import fixture
from test_services_state import offers
from unittest.mock import patch


class WorldFeaturesTests(unittest.TestCase):
    def test_admin_commands_use_native_nearby_in_every_tab_without_chat_echo(self):
        for channel in ('local','global','private'):
            s=fixture();s.stats['admin']=4;s.snapshot=lambda:dict(events=list(s.events))
            result=s.chat_send(channel,'$warpmeto other','other')
            self.assertEqual(s.sent,[(18,21,b'$warpmeto other')]);self.assertEqual(result['events'],[])

    def test_non_admin_commands_never_gain_a_role_or_use_global(self):
        s=fixture();s.state['self']['name']='player';s.snapshot=lambda:{}
        s.chat_send('global','$warpmeto other')
        self.assertEqual(s.sent,[(18,21,b'$warpmeto other')]);self.assertEqual(s.stats,{})
        self.assertEqual(s.events[-1]['channel'],'local')

    def test_command_responses_are_native_server_messages(self):
        s=fixture();s.apply_event(18,23,b'Character not found')
        self.assertEqual(s.events[-1]['message'],'Character not found')
        self.assertEqual(s.events[-1]['channel'],'system')

    def test_chair_self_ack_and_stand_use_native_position_without_walking(self):
        s=fixture();s.snapshot=lambda:dict(player=dict(s.state['self']))
        def reply(f,actions):
            self.assertEqual(f,8)
            if actions=={8}:s.apply_event(8,8,number(100,2)+number(40,1)+number(39,1)+number(0,1)+number(0,1))
            else:s.apply_event(8,14,number(100,2)+number(40,1)+number(40,1))
        s._wait_service=reply
        self.assertEqual(s.sit(40,39)['player']['sitting'],1)
        self.assertEqual(s.sent[-1],(8,1,number(1,1)+number(40,1)+number(39,1)))
        with self.assertRaisesRegex(EOError,'Stand'):s.move(0,1,5,40,40)
        self.assertEqual(s.sit()['player']['sitting'],0)
        self.assertEqual(s.sent[-1],(8,1,number(2,1)))
        self.assertEqual((s.state['self']['x'],s.state['self']['y']),(40,40))
        self.assertTrue(s.position_update);self.assertFalse(s.pending_moves)

    def test_floor_sit_and_peers_standing_use_different_original_packets(self):
        s=fixture();s.state['characters']=[dict(player_id=200,x=39,y=40)]
        s.apply_event(41,8,number(200,2)+number(39,1)+number(40,1)+number(2,1)+number(0,1))
        self.assertEqual(s.state['characters'][0]['sitting'],2)
        s.apply_event(41,4,number(200,2)+number(39,1)+number(39,1))
        self.assertEqual(s.state['characters'][0]['sitting'],0);self.assertEqual(s.state['characters'][0]['y'],39)
        s._wait_service=lambda f,a:s.apply_event(41,8,number(100,2)+number(40,1)+number(40,1)+number(0,1)+number(0,1))
        s.snapshot=lambda:{};s.sit();self.assertEqual(s.sent[-1],(41,1,number(1,1)))

    def test_chair_distance_and_trade_guards_and_malformed_reply_are_atomic(self):
        s=fixture()
        with self.assertRaises(EOError):s.sit(42,42)
        s.trade={'player_id':200}
        with self.assertRaises(EOError):s.sit(40,39)
        s.trade=None
        with self.assertRaises(EOError):s.apply_event(8,8,number(100,2)+number(40,1))
        self.assertNotIn('sitting',s.state['self']);self.assertEqual(s.sent,[])

    def test_native_expiry_only_removes_ground_uid_not_inventory_or_chest(self):
        s=fixture();s.state['items']=[dict(uid=20,id=21),dict(uid=21,id=21)]
        s.inventory=[dict(id=21,amount=3)];s.chest=dict(map_id=5,x=40,y=39,items=[dict(id=21,amount=5)])
        s.apply_event(14,4,number(20,2))
        self.assertEqual(s.state['items'],[dict(uid=21,id=21)]);self.assertTrue(s.dirty)
        self.assertEqual(s.item_amount(21),3);self.assertEqual(s.chest['items'][0]['amount'],5)

    def test_original_admin_weight_privilege_survives_trade(self):
        s=fixture();s.max_weight=251;s.trade=dict(player_id=200);s.inventory=[]
        with patch('services.item_definitions',return_value={21:dict(weight=1)}):
            s.apply_event(32,10,offers((200,[(21,5)])))
        self.assertEqual(s.item_amount(21),5);self.assertEqual(s.weight,0)

    def test_weight_patch_only_changes_potions_scrolls_and_revision(self):
        records=[]
        for name,kind,weight in [('Health Potion',3,1),('King Scroll',4,2),('Potion of Love',23,1),('Cure Potion',25,1),('Elixer',3,1),('Apple',3,1),('Scav Bow',10,5)]:
            fields=bytearray(number(0,1)*58);fields[2]=number(kind,1)[0];fields[55]=number(weight,1)[0]
            records.append(number(len(name),1)+name.encode()+fields)
        original=b'EIF'+number(123,4)+number(len(records),2)+number(0,1)+b''.join(records)
        updated,ids=patch_item_weights(original)
        self.assertEqual(ids,[1,2,3,4,5]);self.assertEqual(patch_item_weights(updated),(updated,[]))
        allowed=set(range(3,7));offset=10
        for rec in records[:5]:allowed.add(offset+len(rec)-58+55);offset+=len(rec)
        self.assertTrue(all(i in allowed for i,(a,b) in enumerate(zip(original,updated)) if a!=b))
        self.assertEqual(len(updated),len(original))
        self.assertFalse(weightless_consumable(3,'Small Bread'))
        for name in ('Royal Potion','Elemental Potion','Scroll Of Truth'):
            self.assertTrue(weightless_consumable(0,name))
        with self.assertRaises(RuntimeError):patch_item_weights(original[:-1])


if __name__=='__main__':unittest.main()
