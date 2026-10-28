from contextlib import closing
from pathlib import Path
import sqlite3,tempfile,unittest
from promote_test_summoner import promote
ROOT=Path(__file__).resolve().parents[1]
class PromotionTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.path=Path(self.tmp.name)/'database.sdb'
  with closing(sqlite3.connect(self.path)) as db,db:
   db.executescript((ROOT/'work/pet-owner-scale/runtime/install.sql').read_text())
   for username in ('owner','outsider'):db.execute('INSERT INTO accounts(username,password,fullname,location,email,computer,hdid,regip,created) VALUES (?,?,?,?,?,?,?,?,?)',(username,'unit-fixture','','','','',0,'127.0.0.1',1))
   for name,account,admin in [('skylar','owner',4),('summontest','owner',0),('outside','outsider',0)]:db.execute('INSERT INTO characters(name,account,class,level,admin,inventory,bank) VALUES (?,?,?,?,?,?,?)',(name,account,7,50,admin,'1,1000000;','624,5;'))
 def test_only_admin_changes_and_retry_is_safe(self):
  a=promote(self.path);self.assertEqual(a['admin'],4);self.assertTrue(a['all_other_database_values_preserved'])
  self.assertEqual(promote(self.path)['previous_admin'],4)
  with closing(sqlite3.connect(self.path)) as db:
   self.assertEqual(db.execute("SELECT level,class,inventory,bank FROM characters WHERE name='summontest'").fetchone(),(50,7,'1,1000000;','624,5;'))
 def test_unrelated_account_is_refused(self):
  with self.assertRaisesRegex(ValueError,'reference character account'):promote(self.path,name='outside')
  with closing(sqlite3.connect(self.path)) as db:self.assertEqual(db.execute("SELECT admin FROM characters WHERE name='outside'").fetchone()[0],0)
if __name__=='__main__':unittest.main()
