import unittest
from unittest.mock import patch
from types import SimpleNamespace
from carry_rules import state,check,trade_fits
from eo_session import EOError
class CarryRulesTests(unittest.TestCase):
 def setUp(self):
  self.flags=patch('carry_rules.enabled',return_value=True);self.flags.start();self.addCleanup(self.flags.stop)
  self.items=patch('carry_rules.item_definitions',return_value={1:dict(weight=0),21:dict(weight=1),22:dict(weight=3)});self.items.start();self.addCleanup(self.items.stop)
 def fixture(self,amount,capacity=70,gear=0):return SimpleNamespace(inventory=[dict(id=21,amount=amount)],equipment={'weapon':gear},stats=dict(max_weight=capacity,admin=4),weight=0,player_id=1,trade=None)
 def test_exact_capacity_and_equipment_and_unsaturated_large_stack(self):
  s=self.fixture(70);self.assertFalse(state(s)['overweight']);check(s)
  s.equipment['weapon']=21;self.assertEqual(state(s)['weight'],71)
  with self.assertRaisesRegex(EOError,'Overweight'):check(s)
  s.inventory=[dict(id=22,amount=1000000000)];self.assertEqual(state(s)['weight'],3000000001)
 def test_trade_checks_net_weight_and_leaves_offers_unchanged(self):
  s=self.fixture(69);s.trade=dict(player_id=2,offers={'1':[dict(id=1,amount=10)],'2':[dict(id=21,amount=2)]})
  with self.assertRaisesRegex(EOError,'capacity'):trade_fits(s)
  self.assertEqual(s.trade['offers']['2'][0]['amount'],2);s.trade['offers']['2'][0]['amount']=1;trade_fits(s)
if __name__=='__main__':unittest.main()
