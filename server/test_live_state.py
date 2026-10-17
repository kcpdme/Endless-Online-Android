"""Regression for original EO movement ownership and nonblocking collection."""
import time, unittest
from unittest.mock import patch
from collections import deque
from copy import deepcopy
from eo_session import EOError,number,Reader
from live_session import LiveSession

def fixture():
    s=LiveSession.__new__(LiveSession)
    s.init_services()
    s.pending_moves=deque();s.position_seq=0;s.last_input_seq=0;s.pending_pickups={};s.drop_guards={}
    s.metrics=dict(moves=0,walk_acks=0,refreshes=0,corrections=0,collects=0,pickups=0)
    s.dirty=False;s.position_update=False;s.correction=False;s.expect_walk_refresh=False;s.sent_state=None
    s.state={'map_id':5,'self':{'player_id':100,'map_id':5,'x':40,'y':40,'direction':0},'characters':[],'npcs':[],'items':[]}
    s.stats={};s.inventory=[];s.events=[];s.timestamp=1000;s.last_walk=0;s.warp=None;s.player_id=100;s.weight=0;s.max_weight=70
    s.sent=[];s.send=lambda f,a,p=b'':s.sent.append((f,a,p))
    return s

class StreamStateTests(unittest.TestCase):
    def test_boss_children_despawn_by_type_not_spawn_index(self):
        s=fixture();s.state['npcs']=[dict(id=256,index=1,x=40,y=41),dict(id=256,index=2,x=40,y=42),dict(id=99,index=256,x=41,y=40)]
        s.apply_event(26,25,number(256,2))
        self.assertEqual([n['id'] for n in s.state['npcs']],[99])
        self.assertEqual(s.events[-1]['indexes'],[1,2]);self.assertTrue(s.dirty)
        s.apply_event(26,8,number(1,1)+number(40,1)+number(41,1)+number(0,1))
        self.assertEqual(len(s.state['npcs']),1) # a late old movement cannot resurrect a ghost
        s.apply_event(29,3,number(0,1)+b'\xff'+number(1,1)+number(256,2)+number(40,1)+number(41,1)+number(0,1))
        self.assertEqual({n['id'] for n in s.state['npcs']},{99,256}) # genuine native respawn restores it

    def test_spikes_update_hp_and_stream_every_nonlethal_hit(self):
        s=fixture();s.stats={'hp':1000,'max_hp':1000}
        for hp in [950,900,850]:
            s.dirty=False
            s.apply_event(31,16,number(2,1)+number(50,2)+number(hp,2)+number(1000,2))
            self.assertEqual(s.stats['hp'],hp);self.assertEqual(s.state['self']['hp'],hp)
            self.assertTrue(s.dirty);self.assertFalse(s.stats['dead'])
            self.assertEqual(s.events[-1]['source'],'spike')
        s.apply_event(31,17,number(200,2)+number(95,1)+number(0,1)+number(50,3))
        self.assertEqual(s.events[-1]['kind'],'peer_damage')
        self.assertEqual(s.stats['hp'],850)
    def test_lethal_spikes_stop_outstanding_inputs(self):
        s=fixture();s.pending_moves.append(dict(seq=1));s.last_input_seq=1
        s.apply_event(31,16,number(2,1)+number(20,2)+number(0,2)+number(1000,2))
        self.assertTrue(s.stats['dead']);self.assertFalse(s.pending_moves)

    def test_junk_ack_removes_only_acknowledged_amount_without_ground_drop(self):
        s=fixture();s.inventory=[dict(id=360,amount=2)]
        s.apply_event(14,25,number(360,2)+number(1,3)+number(1,4)+number(3,1)+number(70,1))
        self.assertEqual(s.inventory,[dict(id=360,amount=1)])
        self.assertEqual(s.state['items'],[]);self.assertTrue(s.dirty)
        self.assertEqual((s.weight,s.max_weight),(3,70));self.assertFalse(s.sent)
        self.assertEqual(s.events[-1]['kind'],'item_junk')
    def test_junk_rejects_invalid_and_unowned_quantities_without_send(self):
        s=fixture();s.inventory=[dict(id=360,amount=2)]
        for amount in (-1,0,3,16194277):
            with self.assertRaises(EOError):s.junk_item(360,amount)
        with self.assertRaises(EOError):s.junk_item(999,1)
        self.assertFalse(s.sent);self.assertEqual(s.inventory,[dict(id=360,amount=2)])
    def test_native_drop_ack_updates_ground_stack_and_weight_without_refresh(self):
        s=fixture();s.inventory=[dict(id=360,amount=2)]
        s.apply_event(14,24,number(360,2)+number(1,3)+number(1,4)+number(77,2)+number(40,1)+number(40,1)+number(6,1)+number(70,1))
        self.assertEqual(s.inventory,[dict(id=360,amount=1)])
        self.assertEqual(s.state['items'],[dict(uid=77,id=360,amount=1,x=40,y=40)])
        self.assertEqual((s.weight,s.max_weight),(6,70));self.assertFalse(s.sent)
    def test_drop_rejects_unowned_excess_quantity_and_lore_before_send(self):
        s=fixture();s.inventory=[dict(id=360,amount=2)]
        with patch('services.item_definitions',return_value={360:dict(special=0)}):
            for amount in (-1,0,3,16194277):
                with self.assertRaises(EOError):s.drop_item(360,amount)
            with self.assertRaises(EOError):s.drop_item(999,1)
        with patch('services.item_definitions',return_value={360:dict(special=4)}):
            with self.assertRaisesRegex(EOError,'cannot be dropped'):s.drop_item(360,1)
        self.assertFalse(s.sent);self.assertEqual(s.inventory,[dict(id=360,amount=2)])
    def test_face_is_native_direction_only_and_can_follow_committed_walk(self):
        s=fixture();s.pending_moves.append(dict(seq=1));before=s.timestamp
        self.assertTrue(s.face(2)['sent'])
        self.assertEqual((s.sent[0][0],s.sent[0][1]),(7,8))
        self.assertEqual(Reader(s.sent[0][2]).num(),2)
        self.assertEqual(s.state['self']['direction'],2);self.assertEqual(s.timestamp,before)
        with self.assertRaises(EOError):s.face(4)
    def test_first_attack_timestamp_honors_requested_facing_without_face_wait(self):
        s=fixture();s.timestamp=0;s.strike(2)
        self.assertEqual(len(s.sent),1)
        r=Reader(s.sent[0][2]);self.assertEqual(r.num(),2);self.assertEqual(r.num(3),50)
    def test_peer_equipment_push_uses_bahws_order_without_refresh(self):
        s=fixture();s.state['characters']=[dict(player_id=200,equipment_graphics=[0]*9,direction=0)]
        s.apply_event(23,5,number(200,2)+number(1,1)+number(0,1)+b''.join(number(i,2) for i in [1,1,0,33,0]))
        self.assertEqual(s.state['characters'][0]['equipment_graphics'],[1,0,0,0,1,0,0,0,33])
        self.assertTrue(s.dirty);self.assertFalse(s.sent)
        s.apply_event(23,5,number(200,2)+number(1,1)+number(0,1)+b''.join(number(i,2) for i in [1,1,0,0,0]))
        self.assertEqual(s.state['characters'][0]['equipment_graphics'][8],0)
    def test_peer_attack_preserves_event_and_updates_facing(self):
        s=fixture();s.state['characters']=[dict(player_id=200,direction=0)]
        s.apply_event(11,8,number(200,2)+number(2,1))
        self.assertEqual(s.state['characters'][0]['direction'],2)
        self.assertEqual(s.events[-1]['kind'],'peer_attack');self.assertEqual(s.events[-1]['direction'],2)
        self.assertTrue(s.dirty)
    def test_moving_npc_race_uses_original_native_walk_instead_of_synthetic_rejection(self):
        s=fixture();s.state['npcs']=[dict(index=1,id=2,x=41,y=40)]
        result=s.move(3,1,5,41,40)
        self.assertTrue(result['sent']);self.assertEqual(s.sent[0][:2],(6,8));self.assertFalse(s.correction)
        s.apply_event(6,3,b'\xff\xff')
        self.assertEqual((s.state['self']['x'],s.position_seq),(41,1))
    def test_attack_queues_after_walk_without_waiting_another_round_trip(self):
        s=fixture();s.move(3,1,5,41,40)
        self.assertTrue(s.strike(3)['sent'])
        self.assertEqual([entry[:2] for entry in s.sent],[(6,8),(11,10)])
    def test_unchanged_refresh_is_not_a_position_correction(self):
        s=fixture();s.parse_snapshot=lambda r:deepcopy(s.state)
        s.apply_event(25,3,b'')
        self.assertFalse(s.correction);self.assertEqual(s.metrics['corrections'],0)
    def test_collect_returns_without_wait_and_does_not_block_movement(self):
        s=fixture();s.state['items']=[dict(uid=7,id=249,amount=2,x=40,y=40)]
        before=time.monotonic();self.assertTrue(s.collect(7)['sent']);self.assertLess(time.monotonic()-before,.01)
        self.assertTrue(s.move(3,1,5,41,40)['sent'])
        s.apply_event(14,27,number(7,2)+number(249,2)+number(2,3)+number(2,1)+number(70,1))
        self.assertEqual(s.inventory,[dict(id=249,amount=2)]);self.assertFalse(s.pending_pickups);self.assertFalse(s.state['items'])
        self.assertEqual(s.events[-1]['kind'],'pickup')
    def test_failed_collect_expires_as_event_without_socket_wait(self):
        s=fixture();s.pending_pickups[7]=time.monotonic()-1;s.poll_actions()
        self.assertEqual(s.events[-1]['kind'],'pickup_failed');self.assertTrue(s.dirty)
    def test_known_other_owner_is_reported_without_stalling(self):
        s=fixture();s.state['items']=[dict(uid=7,id=249,amount=1,x=40,y=40)];s.drop_guards[7]=(200,time.monotonic()+30)
        with self.assertRaisesRegex(EOError,'reserved for another player'):s.collect(7)
        self.assertFalse(s.sent)
    def test_partial_pickup_keeps_uncollected_amount(self):
        s=fixture();s.state['items']=[dict(uid=7,id=249,amount=4,x=40,y=40)]
        s.apply_event(14,27,number(7,2)+number(249,2)+number(2,3)+number(70,1)+number(70,1))
        self.assertEqual(s.state['items'][0]['amount'],2)

if __name__=='__main__':unittest.main()
