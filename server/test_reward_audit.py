"""Reward audit rejects lower rates/EXP and never opens the private player database."""
from pathlib import Path
import shutil,tempfile,unittest
from audit_classic_rewards import audit
from configure_balance import records,encode_pub,put
BASE=Path(__file__).resolve().parents[1]/'work/classic-rates-board/runtime'

@unittest.skipUnless((BASE/'data/balance-profile.json').exists(),'profile13 runtime unavailable')
class RewardAuditTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.r=Path(self.tmp.name)
  shutil.copytree(BASE/'config',self.r/'config')
  for n in ['config.ini','config.local.ini','data/aster-vale-drops.ini','data/pub/dtn001.enf','data/balance-v1-baseline/data/pub/dtn001.enf']:
   p=self.r/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(BASE/n,p)
  (self.r/'database.sdb').write_bytes(b'private database must not be opened')
 def files(self):return {str(p.relative_to(self.r)):p.read_bytes() for p in self.r.rglob('*') if p.is_file()}
 def test_all_original_rewards_verified_without_any_write(self):
  before=self.files();result=audit(self.r);self.assertEqual(result['issues'],[]);self.assertEqual(result['classic_drop_entries'],262);self.assertEqual(result['original_npc_exp_definitions'],305);self.assertEqual(before,self.files())
 def test_changed_horn_chance_detected(self):
  p=self.r/'data/aster-vale-drops.ini';p.write_text(p.read_text().replace('258,1,1,10','258,1,1,5'))
  self.assertIn('Classic drop table differs: NPC 7',audit(self.r)['issues'])
 def test_changed_exp_detected(self):
  p=self.r/'data/pub/dtn001.enf';raw=p.read_bytes();rows=records(raw,b'ENF',39);put(rows[6]['fields'],36,9,3);p.write_bytes(encode_pub(raw,rows))
  self.assertIn('Original EXP differs: NPC 7',audit(self.r)['issues'])
 def test_global_boost_or_replacing_eggs_detected(self):
  p=self.r/'config.local.ini';p.write_text(p.read_text()+'\nExpRate = 500%\nBonusSpiritEggDrops = no\n')
  result=audit(self.r);self.assertIn('ExpRate is not x1',result['issues']);self.assertIn('Egg rolls can replace classic loot for Summoners',result['issues'])
if __name__=='__main__':unittest.main()
