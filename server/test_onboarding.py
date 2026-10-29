"""Classic birth settings and guarded preservation of the original island content."""
from pathlib import Path
import shutil,tempfile,unittest
from configure_onboarding import configure,QUEST
from configure_sky_wonder import parse
from eo_session import number
BASE=Path(__file__).resolve().parents[1]/'work/pet-collection-v12/runtime'

@unittest.skipUnless((BASE/'data/maps/00192.emf').exists(),'native resources unavailable')
class OnboardingTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.r=Path(self.tmp.name)
        (self.r/'data/maps').mkdir(parents=True);(self.r/'data/quests').mkdir()
        for mid in (1,2,190,192,193,194,195):shutil.copy2(BASE/f'data/maps/{mid:05}.emf',self.r/f'data/maps/{mid:05}.emf')
        for n in ['aster-vale-home.ini','aster-vale-shops.ini']:shutil.copy2(BASE/'data'/n,self.r/'data'/n)
        (self.r/'config.local.ini').write_text('HomeFile = ./data/aster-vale-home.ini\nPasswordSalt = preserve\nExpRate = 100%\nStartItems = 21,1\n')
    def files(self):return {str(p.relative_to(self.r)):p.read_bytes() for p in self.r.rglob('*') if p.is_file()}
    def test_exact_classic_start_and_idempotent_map_economy_preservation(self):
        before=self.files();result=configure(self.r);first=self.files();self.assertEqual(result,configure(self.r));self.assertEqual(first,self.files())
        for n,data in before.items():
            if n not in ('config.local.ini','data/aster-vale-home.ini'):self.assertEqual(first[n],data)
        cfg=first['config.local.ini'].decode();self.assertIn('PasswordSalt = preserve\nExpRate = 100%',cfg)
        self.assertEqual(result['start'],[192,7,6]);self.assertEqual(result['boat']['required_level'],4);self.assertEqual(result['aeven_required_level'],5)
        self.assertFalse((self.r/'database.sdb').exists());self.assertEqual(first['data/quests/00000.eqf'],QUEST.encode())
        for action in ('GiveItem(','GiveExp(','SetClass(','SetLevel('):self.assertNotIn(action,QUEST)
        self.assertIn('rule EnterMap(192) goto Island',QUEST);self.assertIn('rule Always() goto Existing',QUEST)
    def test_existing_default_home_and_citizenship_stay_unchanged(self):
        old=(self.r/'data/aster-vale-home.ini').read_text();configure(self.r);new=(self.r/'data/aster-vale-home.ini').read_text()
        self.assertTrue(new.startswith(old.rstrip()+'\n'));self.assertIn('level.0 = aeven',new)
        self.assertNotIn('level.0 = tutorialisland',new);self.assertIn('action SetHome("tutorialisland")',QUEST)
    def test_unknown_default_quest_refused_before_any_write(self):
        (self.r/'data/quests/00000.eqf').write_text('existing authored quest');before=self.files()
        with self.assertRaisesRegex(ValueError,'Quest 0'):configure(self.r)
        self.assertEqual(before,self.files())
    def test_changed_boat_or_recipe_refused_without_partial_configuration(self):
        p=self.r/'data/aster-vale-shops.ini';p.write_text(p.read_text().replace('21,258,2,0,0,0,0,0,0','21,258,3,0,0,0,0,0,0'));before=self.files()
        with self.assertRaisesRegex(ValueError,'dagger recipe'):configure(self.r)
        self.assertEqual(before,self.files())

if __name__=='__main__':unittest.main()
