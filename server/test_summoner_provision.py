"""Requested sibling creation conserves existing accounts and refuses duplicate grants."""
from pathlib import Path
import json,sqlite3,tempfile,unittest
from contextlib import closing
from provision_summoner_test import provision,build_kit
ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless((ROOT/'work/summoner-50/runtime/data/balance-profile.json').exists(),'test profile unavailable')
class ProvisionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.db=Path(self.tmp.name)/'database.sdb'
        self.profile=json.loads((ROOT/'work/summoner-50/runtime/data/balance-profile.json').read_text())
        with closing(sqlite3.connect(self.db)) as db,db:
            db.executescript((ROOT/'work/summoner-50/runtime/install.sql').read_text())
            db.execute('INSERT INTO accounts(username,password,fullname,location,email,computer,hdid,regip,created) VALUES (?,?,?,?,?,?,?,?,?)',('owner','unit-fixture','','','','',0,'127.0.0.1',1))
            db.execute('INSERT INTO characters(name,account,level,admin,inventory,bank,paperdoll,spells) VALUES (?,?,?,?,?,?,?,?)',('skylar','owner',120,4,'1,123;','',','.join(['0']*15),'1,0;'))
    def test_grant_is_regular_level_fifty_with_complete_kit_and_safe_locker_capacity(self):
        report=provision(self.db,self.profile)
        self.assertEqual(report['gold'],1_000_000);self.assertEqual(report['level'],50);self.assertEqual(report['max_tp'],1108)
        self.assertLessEqual(report['weight'],report['max_weight']-10);self.assertLessEqual(report['locker_slots_used'],60)
        with closing(sqlite3.connect(self.db)) as db,db:
            self.assertEqual(db.execute('SELECT account,admin,class,level,exp,skillpoints FROM characters WHERE name=?',('summontest',)).fetchone(),('owner',0,7,50,16_637_500,150))
            self.assertEqual(db.execute('SELECT level,admin,inventory,spells FROM characters WHERE name=?',('skylar',)).fetchone(),(120,4,'1,123;','1,0;'))
        self.assertEqual(len(report['equipped']),15)
    def test_existing_name_or_full_account_is_never_overwritten(self):
        provision(self.db,self.profile)
        with closing(sqlite3.connect(self.db)) as db,db:before=db.execute('SELECT * FROM characters ORDER BY name').fetchall()
        with self.assertRaisesRegex(ValueError,'already exists'):provision(self.db,self.profile)
        with self.assertRaisesRegex(ValueError,'no free'):provision(self.db,self.profile,name='another',max_characters=2)
        with closing(sqlite3.connect(self.db)) as db,db:self.assertEqual(db.execute('SELECT * FROM characters ORDER BY name').fetchall(),before)
    def test_only_legal_gear_and_one_egg_per_species_start_in_the_bag(self):
        fields,report=build_kit(self.profile)
        bag={i['id']:i['amount'] for i in report['bag']}
        for ident in self.profile['eggs']:self.assertEqual(bag[int(ident)],1)
        self.assertNotIn('63,0;',fields['spells'])
        for item in report['bag']+report['locker']+report['equipped']:
            definition=self.profile['items'][str(item['id'])]
            if 10<=definition['type']<=21:
                self.assertTrue(not definition.get('allowed_classes') or 7 in definition['allowed_classes'])
                self.assertNotIn(item['id'],(204,208,384,445,446,491))

if __name__=='__main__':unittest.main()
