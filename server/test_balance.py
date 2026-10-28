"""Balance content, meaningful progression, rebuild guards and ownership migration."""
from pathlib import Path
import json,shutil,sqlite3,tempfile,unittest
from configure_balance import configure,records,decode_item,migrate_equipment,STAT_FIELDS,num
from balance_profile import NEW_ITEMS,CLASSES,SPELLS,VERSION
from class_signatures import EGGS
from balance_model import benchmarks,evaluate

BASE=Path(__file__).resolve().parents[1]/'work/server-build/runtime'

@unittest.skipUnless((BASE/'data/pub/dat001.eif').exists(),'native resources unavailable')
class BalanceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.runtime=Path(self.temp.name)/'runtime';shutil.copytree(BASE/'data',self.runtime/'data');(self.runtime/'config.local.ini').write_text('PasswordSalt = do-not-change\nExpRate = 500%\n');(self.runtime/'etheos').write_bytes(b'isolated fixture BalanceRevamp ClassIdentityRules ClassSignatureRules MortalSpiritBonds')
        from configure_feature_content import configure as features
        features(self.runtime)

    def install(self):
        report=configure(self.runtime);return report,json.loads((self.runtime/'data/balance-profile.json').read_text())

    def test_repeated_install_is_identical_and_preserves_private_config_and_operator_item(self):
        original=(self.runtime/'data/pub/dat001.eif').read_bytes();a,p=self.install();first={str(f.relative_to(self.runtime)):f.read_bytes() for f in self.runtime.rglob('*') if f.is_file()};b,_=self.install();self.assertEqual(a,b);self.assertEqual(first,{str(f.relative_to(self.runtime)):f.read_bytes() for f in self.runtime.rglob('*') if f.is_file()});self.assertIn('PasswordSalt = do-not-change\nExpRate = 500%',(self.runtime/'config.local.ini').read_text());new=(self.runtime/'data/pub/dat001.eif').read_bytes();self.assertEqual(records(original,b'EIF',58)[490],records(new,b'EIF',58)[490]);self.assertEqual(len(p['items']),611)
        from admin_weapon import patch_weapon
        self.assertEqual(patch_weapon(new),(new,False));self.assertEqual(p['items']['21']['level_requirement'],0)

    def test_gender_equivalents_and_new_class_endgame_rewards(self):
        _,p=self.install();items=p['items']
        for male,female in [(460,465),(430,431),(458,459),(387,388)]+[(i,i+1) for i in range(499,511,2)]:
            self.assertEqual({k:items[str(male)][k] for k in STAT_FIELDS},{k:items[str(female)][k] for k in STAT_FIELDS})
        for clas in (2,3,4,5,6,7):
            end=[i for i in items.values() if i.get('class_requirement')==clas and i['level_requirement']==45]
            self.assertTrue(any(i['type']==10 for i in end));self.assertTrue(any(i['type']==12 for i in end))
        for key in STAT_FIELDS:self.assertGreaterEqual(items['430'][key],items['460'][key])
        self.assertGreater(items['430']['armor'],items['460']['armor'])
        for ident,attribute in [(499,'wisdom'),(501,'intelligence'),(503,'charisma'),(505,'agility'),(507,'agility'),(509,'strength')]:
            self.assertGreater(items[str(ident)][attribute],items['430'][attribute])
        self.assertGreater(items['509']['armor'],items['430']['armor']);self.assertGreater(items['505']['evade'],items['430']['evade'])

    def test_class_ownership_and_real_companion_definitions(self):
        _,p=self.install();items=p['items'];spells=p['spells']
        for spell in spells.values():
            if spell['type']==0:self.assertIn(spell['allowed_classes'],([2],[-1]))
        for ident in (297,316,365,457,496,511,512,543,423,424,425):self.assertEqual(items[str(ident)]['allowed_classes'],[5])
        self.assertEqual(items['533']['allowed_classes'],[4])
        self.assertFalse(items['460']['allowed_classes'])
        for ident,npc in [(28,306),(33,307),(34,308)]:
            self.assertEqual(spells[str(ident)]['allowed_classes'],[7]);self.assertEqual(spells[str(ident)]['effect_kind'],'companion')
            self.assertEqual(spells[str(ident)]['companion']['npc_id'],npc)
            self.assertEqual(p['npcs'][str(npc)]['type'],0)
        self.assertEqual(len(p['npcs']),3)

    def test_crafting_edge_and_archetypes_are_bounded_and_obtainable(self):
        _,p=self.install();items=p['items']
        for ident,base in [(543,511),(533,38)]:
            craft,normal=items[str(ident)],items[str(base)]
            self.assertTrue(craft['crafted']);self.assertTrue(craft['acquisition']['craft']);self.assertFalse(craft['acquisition']['buy'])
            self.assertGreater(craft['max_damage'],normal['max_damage'])
        self.assertGreater(items['533']['tp'],items['327']['tp']);self.assertGreater(items['533']['evade'],items['327']['evade']);self.assertLess(items['533']['max_damage'],items['327']['max_damage'])
        for male,female in [(535,536),(537,538),(539,540),(541,542)]:
            self.assertEqual({k:items[str(male)][k] for k in STAT_FIELDS},{k:items[str(female)][k] for k in STAT_FIELDS})
        self.assertTrue(any(i.get('archetype')=='heavy' for i in items.values()))
        self.assertTrue(any(i.get('archetype')=='precision' for i in items.values()))
        self.assertTrue(any(i.get('archetype')=='focus' for i in items.values()))

    def test_all_classes_have_obtainable_full_kits_and_progression(self):
        _,p=self.install()
        from balance_audit import audit
        report=audit(p);self.assertEqual(report['issues'],[]);self.assertEqual(len(report['coverage']),36)
        for clas in range(2,8):
            self.assertTrue(p['classes'][str(clas)]['signature']['description'])
            learned=[s for s in p['spells'].values() if s['allowed_classes']==[clas]]
            self.assertGreaterEqual(len(learned),6)
            self.assertTrue(any(s['level_requirement']==1 and s['type']==1 for s in learned))
        for row in report['coverage']:
            if row['level']>=15:
                for slot in ('head','boots','gloves','ring'):self.assertGreater(row['slots'][slot]['exclusive'],0)

    def test_bound_egg_drops_preserve_original_tables_and_have_no_crafting_bypass(self):
        import re
        old=(self.runtime/'data/aster-vale-drops.ini').read_text();_,p=self.install();new=(self.runtime/'data/aster-vale-drops.ini').read_text()
        def entries(text):return {key:raw.strip() for key,raw in re.findall(r'^(\d+)[ \t]*=[ \t]*(.*)$',text,re.M)}
        before,after=entries(old),entries(new)
        for key,value in before.items():
            if int(key) not in (74,82,225):self.assertEqual(after[key],value)
            else:self.assertTrue(after[key].startswith(value))
        from class_signatures import EGGS
        for ident,egg in EGGS.items():
            item=p['items'][str(ident)];self.assertEqual(item['hatch_spell'],egg['spell_id']);self.assertEqual(item['type'],23)
            self.assertIn(f"BalanceEgg.{ident}.spell = {egg['spell_id']}",(self.runtime/'config.local.ini').read_text())
            self.assertFalse(item['acquisition'].get('craft'));self.assertEqual(item['acquisition']['drop'],[egg['npc_id']]);self.assertEqual(item['special'],4);self.assertTrue(item['bound'])
            self.assertTrue((Path(__file__).resolve().parents[1]/'client'/egg['icon'].removeprefix('res://')).exists())
        offers=(self.runtime/'data/aster-vale-skills.ini').read_text()
        from class_identity import recipe_sources
        self.assertTrue(p['items']['436']['acquisition']['craft'])
        for spell in (28,33,34):self.assertTrue(p['spells'][str(spell)]['learn_source'])
        self.assertEqual(p['spells']['28']['duration'],0)

    def test_no_service_npcs_graphics_or_map_routes_change(self):
        before=records((self.runtime/'data/pub/dtn001.enf').read_bytes(),b'ENF',39);maps={p.name:p.read_bytes() for p in (self.runtime/'data/maps').glob('*.emf')};self.install();after=records((self.runtime/'data/pub/dtn001.enf').read_bytes(),b'ENF',39)
        for a,b in zip(before[:-1],after):
            self.assertEqual(a['names'],b['names']);self.assertEqual(a['fields'][:11],b['fields'][:11])
            if num(a['fields'],7,2) not in (1,2):self.assertEqual(a,b)
        self.assertEqual(maps,{p.name:p.read_bytes() for p in (self.runtime/'data/maps').glob('*.emf')})

    @unittest.skipUnless((BASE.parents[1]/'balance-v1/runtime/data/balance-profile.json').exists(),'profile 1 fixture unavailable')
    def test_actual_profile_one_content_upgrades_from_its_original_baseline(self):
        source=BASE.parents[1]/'balance-v1/runtime/data'
        self.assertEqual(json.loads((source/'balance-profile.json').read_text())['version'],1)
        shutil.rmtree(self.runtime/'data');shutil.copytree(source,self.runtime/'data')
        _,profile=self.install();self.assertEqual(profile['version'],VERSION)
        self.assertEqual(profile['spells']['1']['allowed_classes'],[2])
        self.assertEqual(profile['items']['496']['allowed_classes'],[5])
        self.assertEqual(profile['items']['533']['name'],'Hidden Blade')

    def test_changed_inputs_are_refused_without_partial_writes(self):
        self.install();path=self.runtime/'data/aster-vale-shops.ini';path.write_text(path.read_text()+'\n# operator edit\n');before=(self.runtime/'data/pub/dat001.eif').read_bytes()
        with self.assertRaisesRegex(ValueError,'changed since'):self.install()
        self.assertEqual(before,(self.runtime/'data/pub/dat001.eif').read_bytes())

    def test_every_class_has_legal_gear_and_useful_combat_at_every_milestone(self):
        _,p=self.install();rows=benchmarks(p);self.assertEqual(len(rows),36)
        for row in rows:
            self.assertGreater(row['burst_dps'],1);self.assertGreater(row['max_hp'],30)
            if row['level']>=8:self.assertGreaterEqual(row['spell_casts_from_full'],3)
        for level in (15,25,35,45):
            cohort=[r for r in rows if r['level']==level];best=max(r['burst_dps'] for r in cohort)
            for row in cohort:self.assertGreater(row['burst_dps']/best,.65,(level,row['role'],cohort))
        self.assertAlmostEqual(evaluate('100 target_armor 2 * + 100 / damage * 1 max 1 1.5 critical ? * modifier *',dict(target_armor=25,damage=90,critical=0,modifier=1)),60)

    def test_ownership_migration_is_conservative_and_retry_safe(self):
        _,p=self.install();dbpath=self.runtime/'database.sdb'
        with sqlite3.connect(dbpath) as db:
            db.execute('CREATE TABLE characters(name TEXT PRIMARY KEY,level INT,class INT,gender INT,admin INT,inventory TEXT,paperdoll TEXT,exp INT,spells TEXT)');doll=','.join(map(str,[0,0,0,0,0,460]+[0]*9));db.execute('INSERT INTO characters VALUES (?,?,?,?,?,?,?,?,?)',('devone',10,6,1,0,'460,1;1,77;',doll,777,'1,8;'))
        with sqlite3.connect(dbpath) as db:db.execute('CREATE TABLE aster_balance_migrations(version INTEGER PRIMARY KEY,moved_items INTEGER NOT NULL)');db.execute('INSERT INTO aster_balance_migrations VALUES (1,1)');db.execute('INSERT INTO aster_balance_migrations VALUES (2,7)')
        r=migrate_equipment(dbpath,p);self.assertEqual(r['moved_items'],1)
        with sqlite3.connect(dbpath) as db:row=db.execute('SELECT * FROM characters').fetchone()
        with sqlite3.connect(dbpath) as db:self.assertEqual(db.execute('SELECT * FROM aster_balance_migrations ORDER BY version').fetchall(),[(1,1),(2,7),(VERSION,1)])
        self.assertIn('460,2;',row[5]);self.assertEqual(row[7:],(777,'1,8;'));self.assertEqual(migrate_equipment(dbpath,p),dict(already_applied=True,moved_items=0))

    def test_migration_rolls_back_all_rows_on_malformed_inventory(self):
        _,p=self.install();dbpath=self.runtime/'database.sdb'
        with sqlite3.connect(dbpath) as db:
            db.execute('CREATE TABLE characters(name TEXT PRIMARY KEY,level INT,class INT,gender INT,admin INT,inventory TEXT,paperdoll TEXT)');doll=','.join(map(str,[460]+[0]*14));db.executemany('INSERT INTO characters VALUES (?,?,?,?,?,?,?)',[('devone',1,6,1,0,'1,5;',doll),('devtwo',1,6,1,0,'malformed',doll)]);before=db.execute('SELECT * FROM characters').fetchall()
        with self.assertRaises(ValueError):migrate_equipment(dbpath,p)
        with sqlite3.connect(dbpath) as db:self.assertEqual(before,db.execute('SELECT * FROM characters').fetchall())

if __name__=='__main__':unittest.main()
