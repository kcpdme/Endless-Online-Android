"""Native-authoritative Run packets and current class targeting contract."""
import unittest
from unittest.mock import patch
from eo_session import EOError, number
from test_live_state import fixture
from combat_progression import movement_seconds
from balance_profile import SPELLS


def packet(pid=100, enabled=1, tp=75, speed=1250):
    return number(pid,2)+number(enabled,1)+number(tp,2)+number(speed,2)


class RunTests(unittest.TestCase):
    def test_only_ack_changes_speed_and_tp(self):
        s=fixture();s.stats['tp']=100
        self.assertEqual(movement_seconds(s),.42)
        s.apply_event(6,10,packet())
        self.assertEqual((s.stats['tp'],s.state['self']['tp']),(75,75))
        self.assertEqual(movement_seconds(s),.336)
        s.apply_event(6,10,packet(enabled=0,tp=0,speed=1000))
        self.assertEqual(movement_seconds(s),.42)
        self.assertFalse(s.running_enabled)

    def test_peer_ack_cannot_enable_owner(self):
        s=fixture();s.state['characters']=[dict(player_id=200)]
        s.apply_event(6,10,packet(pid=200,speed=1500))
        self.assertFalse(getattr(s,'running_enabled',False))
        self.assertEqual(s.state['characters'][0]['move_seconds'],.28)

    def test_invalid_packets_fail_closed(self):
        for payload in (b'',packet()[:-1],packet()+b'x',packet(enabled=2),packet(speed=2000)):
            with self.assertRaises(EOError):fixture().apply_run_packet(6,10,payload)
        self.assertFalse(fixture().apply_run_packet(7,10,packet()))

    @patch('balance_rules.profile',return_value={'running_rules':{'normal_multiplier':1.25}})
    def test_request_is_boolean_only_and_awaits_own_matching_ack(self,_):
        s=fixture();s.stats['tp']=100;s.snapshot=lambda:{'native_ack':getattr(s,'running_enabled',False)}
        packets=iter([packet(pid=200),packet(enabled=0,speed=1000),packet()])
        def wait(*args,**kwargs):
            payload=next(packets);s.apply_run_packet(6,10,payload);return payload
        s.wait=wait
        for invalid in (1,0,None,'yes',{},1.25):
            with self.assertRaises(EOError):s.set_running(invalid)
        self.assertEqual(s.sent,[])
        self.assertEqual(s.set_running(True),{'native_ack':True})
        self.assertEqual(s.sent,[(6,10,number(1,1))])
        s.stats['tp']=0
        with self.assertRaises(EOError):s.set_running(True)

    @patch('balance_rules.profile',return_value={'spells':{'14':{'area_radius':2}}})
    def test_admin_does_not_bypass_magician_area_rule(self,_):
        from balance_rules import check_spell
        s=fixture();s.stats.update(class_id=6,admin=4)
        with self.assertRaisesRegex(EOError,'Only Magicians'):check_spell(s,14)
        s.stats['class_id']=3;check_spell(s,14)

if __name__=='__main__':unittest.main()
