import unittest
from unittest.mock import patch
from eo_session import EOError,number
from test_live_state import fixture
class BarberTests(unittest.TestCase):
    def opened(self):
        s=fixture();s.state['npcs']=[dict(id=32,index=7,x=40,y=39)];s.stats['level']=5;s.inventory=[dict(id=1,amount=5000)]
        s.state['self'].update(hairstyle=1,haircolor=0);s.snapshot=lambda:dict(barber=s.barber)
        s._wait_service=lambda f,a:number(0,4)
        with patch('barber.npc_types',return_value={32:10}):s.barber_open(7)
        return s
    def test_open_price_and_native_receipt(self):
        s=self.opened();self.assertEqual(s.sent,[(38,13,number(7,2))]);self.assertEqual(s.barber['price'],1000)
        s._wait_service=lambda f,a:s.apply_event(38,5,number(4000,4)+number(100,2)+number(2,1)+number(0,1)+number(20,1)+number(9,1))
        s.barber_buy(20,9);self.assertEqual(s.sent[-1],(38,11,number(20,1)+number(9,1)))
        self.assertEqual(s.item_amount(1),4000);self.assertEqual(s.state['self']['hairstyle'],20);self.assertEqual(s.state['self']['haircolor'],9)
    def test_invalid_range_same_look_gold_distance_and_movement(self):
        s=self.opened();s.sent.clear()
        for args in [(-1,0),(21,0),(1,-1),(1,10),(1,0)]:
            with self.assertRaises(EOError):s.barber_buy(*args)
        s.inventory=[]
        with self.assertRaisesRegex(EOError,'Gold'):s.barber_buy(2,2)
        s.inventory=[dict(id=1,amount=5000)];s.state['self']['x']=100
        with self.assertRaises(EOError):s.barber_buy(2,2)
        self.assertEqual(s.sent,[])
    def test_wrong_npc_and_atomic_truncated_receipts(self):
        s=self.opened();old=dict(s.state['self']);gold=s.item_amount(1)
        for payload in [b'',number(0,4)+number(101,2)+number(2,1)+number(0,1)+number(2,1)+number(3,1)]:
            with self.assertRaises((RuntimeError,EOError)):s.apply_event(38,5,payload)
            self.assertEqual(s.state['self'],old);self.assertEqual(s.item_amount(1),gold)
        with patch('barber.npc_types',return_value={32:6}):
            with self.assertRaises(EOError):s.barber_open(7)
        s.barber_close()
        with self.assertRaises(EOError):s.barber_buy(2,3)
    def test_rejected_purchase_never_spends_gold_or_changes_hair(self):
        s=self.opened();s._wait_service=lambda *a:(_ for _ in ()).throw(EOError('No ACK'))
        with self.assertRaises(EOError):s.barber_buy(2,3)
        self.assertEqual(s.item_amount(1),5000);self.assertEqual(s.state['self']['hairstyle'],1)
