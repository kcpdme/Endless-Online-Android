import json,unittest
from pathlib import Path
from class_balance_audit import metrics
from balance_profile import CLASSES
from class_identity import ACCESSORY_STATS
ROOT=Path(__file__).resolve().parents[1]
class ClassBalanceV10Tests(unittest.TestCase):
 def test_exact_requested_mage_and_priest_metadata(self):
  self.assertEqual(CLASSES[3]['single_target_multiplier'],1.5);self.assertEqual(CLASSES[3]['area_multiplier'],1)
  from class_signatures import SIGNATURES
  self.assertEqual(SIGNATURES[2]['regen_rate'],.02);self.assertEqual(SIGNATURES[2]['regen_seconds'],1)
 def test_common_accessories_have_bounded_distinct_choices(self):
  self.assertEqual(len({tuple(sorted(s.items())) for s in ACCESSORY_STATS.values()}),len(ACCESSORY_STATS))
  for entry in ACCESSORY_STATS.values():
   for k,v in entry.items():self.assertLessEqual(v,10 if k in ('hp','tp') else 2)
 @unittest.skipUnless((ROOT/'work/class-balance-v10/full-equipment-audit.json').exists(),'native profile unavailable')
 def test_full_slot_equipment_audit_and_late_progression(self):
  r=json.loads((ROOT/'work/class-balance-v10/full-equipment-audit.json').read_text());p=json.loads((ROOT/'work/class-balance-v10/runtime/data/balance-profile.json').read_text())
  self.assertEqual(r['issues'],[]);self.assertEqual(len(r['builds']),108)
  for level in (25,35,45):
   rows=[a for a in r['builds'] if a['level']==level and a['build']=='damage'];best=max(a['sustained_60_dps'] for a in rows)
   for a in rows:
    self.assertGreater(a['sustained_60_dps']/best,.60);self.assertLessEqual(a['weight'],a['capacity'])
    if a['class_id'] in (4,5):self.assertEqual(p['items'][str(a['equipment']['armor'])]['allowed_classes'],[a['class_id']])
if __name__=='__main__':unittest.main()
