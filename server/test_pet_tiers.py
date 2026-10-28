"""Tier equality, progression, purchase restrictions and exact merchant-map edits."""
import json,sys,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from pet_catalog import TIERS,ROSTER,EGGS,COMPANIONS,SUMMON_SPELLS,EGGKEEPER,egg_stock
from balance_rules import check_egg_purchase,check_hatch
from eo_session import EOError
from configure_pet_shop import repair
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from import_eo import parse_emf

class PetTierTests(unittest.TestCase):
    def test_requested_hatch_level_boundaries(self):
        rules=dict(eggs={str(i):e for i,e in EGGS.items()},mortal_spirit_bonds=True)
        s=SimpleNamespace(stats=dict(class_id=7,level=0),spells=[])
        with patch('balance_rules.profile',return_value=rules):
            for tier,t in TIERS.items():
                ident=next(i for i,e in EGGS.items() if e['tier']==tier)
                s.stats['level']=t['level']-1
                with self.assertRaisesRegex(EOError,'Reach level'):check_hatch(s,ident)
                s.stats['level']=t['level'];check_hatch(s,ident)
    def test_requested_roster_and_shop_order_match_exactly(self):
        expected={
            'normal':['Penguin','Fox','Goat'],
            'rare':['Wolf','Butterfly','Skeleton'],
            'epic':['Carnivo','Cursed Mask','Headless Hunter'],
            'legend':['Twin Demon','Dark Magician','Reaper'],
            'mythic':['Banshi','Drake','King Wurm','Wraith'],
        }
        actual={tier:[EGGS[i]['species'] for i in egg_stock() if EGGS[i]['tier']==tier] for tier in TIERS}
        self.assertEqual(actual,expected)
        self.assertEqual([t['level'] for t in TIERS.values()],[5,10,20,30,40])
        sources={'Carnivo':121,'Cursed Mask':134,'Headless Hunter':138,'Twin Demon':140,'Reaper':9,'Banshi':209,'Wraith':113,'Skeleton':17}
        for egg in EGGS.values():
            if egg['species'] in sources:self.assertEqual(egg['npc_id'],sources[egg['species']])
    @unittest.skipUnless((ROOT/'work/pet-tiers/runtime/data/balance-profile.json').exists(),'previous accepted profile unavailable')
    def test_existing_eggs_and_bonds_keep_their_tier_value_and_access(self):
        old=json.loads((ROOT/'work/pet-tiers/runtime/data/balance-profile.json').read_text())
        for ident,before in old['eggs'].items():
            after=EGGS[int(ident)]
            for key in ('tier','price','spell_id'):self.assertEqual(before[key],after[key],(ident,key))
            pet=COMPANIONS[after['spell_id']];before_pet=old['companions'][str(after['spell_id'])]
            for key in ('npc_id','power','accuracy','hit_cap','upkeep'):self.assertEqual(before_pet[key],pet[key],(ident,key))
            before_spell=old['spells'][str(after['spell_id'])];after_spell=SUMMON_SPELLS[after['spell_id']]
            self.assertEqual((before_spell['tp'],before_spell['cast_time']),(after_spell[3],after_spell[4]))
    @unittest.skipUnless((ROOT/'work/class-combat/runtime/data/balance-profile.json').exists(),'rewritten profile unavailable')
    def test_non_pet_native_definitions_and_world_maps_are_preserved(self):
        from configure_balance import records
        before=ROOT/'work/pet-tiers/runtime/data';after=ROOT/'work/class-combat/runtime/data'
        for name in ('pub/dat001.ecf','formulas.ini','aster-vale-skills.ini'):
            self.assertEqual((before/name).read_bytes(),(after/name).read_bytes(),name)
        for name,magic,size,limit in [('dat001.eif',b'EIF',58,608),('dtn001.enf',b'ENF',39,305)]:
            a=records((before/'pub'/name).read_bytes(),magic,size);b=records((after/'pub'/name).read_bytes(),magic,size)
            from combat_progression import SHIELDS
            for old_row,new_row in zip(a[:limit],b[:limit]):
                if name=='dat001.eif' and old_row['id'] in SHIELDS:
                    new_row=dict(new_row,fields=bytearray(new_row['fields']))
                    new_row['fields'][17:19]=old_row['fields'][17:19]
                self.assertEqual(old_row,new_row,name)
        a=records((before/'pub/dtn001.enf').read_bytes(),b'ENF',39);b=records((after/'pub/dtn001.enf').read_bytes(),b'ENF',39)
        self.assertEqual(a[320],b[320],'Shipped merchant ID 321 must remain a shop')
        old=json.loads((before/'balance-profile.json').read_text());pet_spells={e['spell_id'] for e in old['eggs'].values()}
        a=records((before/'pub/dsl001.esf').read_bytes(),b'ESF',51,2);b=records((after/'pub/dsl001.esf').read_bytes(),b'ESF',51,2)
        for row in a[:-1]:
            if row['id'] not in pet_spells:self.assertEqual(row,b[row['id']-1])
        self.assertEqual({p.name:p.read_bytes() for p in (before/'maps').glob('*.emf')},{p.name:p.read_bytes() for p in (after/'maps').glob('*.emf')})
    def test_equal_combat_choices_per_tier_and_ascending_progression(self):
        previous=None
        for tier,t in TIERS.items():
            eggs=[e for e in EGGS.values() if e['tier']==tier];self.assertEqual(len(eggs),4 if tier=='mythic' else 3)
            for egg in eggs:
                pet=COMPANIONS[egg['spell_id']];spell=SUMMON_SPELLS[egg['spell_id']]
                self.assertEqual((egg['level'],egg['price'],spell[3],spell[4]),(t['level'],t['price'],t['tp'],t['chant']))
                self.assertEqual(tuple(pet[k] for k in ('power','accuracy','hit_cap','upkeep')),tuple(t[k] for k in ('power','accuracy','hit_cap','upkeep')))
                self.assertTrue((ROOT/'client'/egg['icon'].removeprefix('res://')).is_file())
            if previous:
                for key in ('level','price','power','accuracy','hit_cap','tp','upkeep'):self.assertGreater(t[key],previous[key],key)
            previous=t
    def test_legacy_bonds_keep_identity_and_new_ids_are_consecutive(self):
        self.assertEqual([(i,EGGS[i]['spell_id'],COMPANIONS[EGGS[i]['spell_id']]['npc_id']) for i in (609,610,611)],[(609,28,306),(610,33,307),(611,34,308)])
        self.assertEqual(sorted(EGGS),list(range(609,625)))
        self.assertEqual(sorted(p['npc_id'] for p in COMPANIONS.values() if p['npc_id']>0),list(range(306,321))+[322])
        self.assertEqual([EGGS[i]['level'] for i in egg_stock()],sorted(e['level'] for e in EGGS.values()))
    def test_every_pet_has_visible_idle_and_walk_art(self):
        manifest_path=ROOT/'client/content/manifest.json'
        if not manifest_path.exists():self.skipTest('client resources unavailable')
        manifest=json.loads(manifest_path.read_text());catalog=json.loads((manifest_path.parent/'catalog.json').read_text())
        for pet in COMPANIONS.values():
            if pet['npc_id']<0:continue
            graphic=catalog['npcs'][str(pet['template_id'])]['graphic'];art=manifest['characters']['npcs'][str(graphic)]
            for state in ('idle','frames'):
                for direction in ('south','east','north','west'):
                    frames=art[state][direction];frames=frames if isinstance(frames,list) else [frames]
                    self.assertTrue(all(frame['visible_bounds'][2]>0 and frame['visible_bounds'][3]>0 for frame in frames),(pet['name'],state,direction))
    def test_only_summoners_can_purchase_even_if_they_have_admin_metadata(self):
        rules=dict(eggs={str(k):v for k,v in EGGS.items()});s=SimpleNamespace(stats=dict(class_id=6,admin=4))
        with patch('balance_rules.profile',return_value=rules):
            with self.assertRaisesRegex(EOError,'Only Summoners'):check_egg_purchase(s,612)
            check_egg_purchase(s,2);s.stats['class_id']=7;check_egg_purchase(s,623)
    @unittest.skipUnless((ROOT/'work/sky-walking/runtime/data/maps/00005.emf').exists(),'reference map unavailable')
    def test_map_only_appends_one_stationary_shop_and_repeat_is_identical(self):
        raw=(ROOT/'work/sky-walking/runtime/data/maps/00005.emf').read_bytes();new=repair(raw)
        self.assertEqual(repair(new),new)
        before,after=parse_emf(raw,5),parse_emf(new,5)
        npc=after['npcs'].pop();self.assertEqual(npc,dict(x=35,y=46,id=EGGKEEPER['id'],spawn_type=7,respawn=180,amount=1));self.assertEqual(before,after)
    @unittest.skipUnless((ROOT/'work/class-combat/runtime/data/balance-profile.json').exists(),'installed profile unavailable')
    def test_all_shop_eggs_have_same_tier_price_no_sell_and_no_skillmaster_bypass(self):
        r=ROOT/'work/class-combat/runtime';p=json.loads((r/'data/balance-profile.json').read_text());self.assertEqual(p['version'],8)
        import re
        text=(r/'data/aster-vale-shops.ini').read_text();trade=next(raw for key,raw in re.findall(r'^(\d+)\.trade\s*=\s*(.*)$',text,re.M) if int(key)==EGGKEEPER['id']);values=list(map(int,trade.split(',')))
        self.assertEqual(values,[n for ident in egg_stock() for n in (ident,EGGS[ident]['price'],0)])
        skilltext=(r/'data/aster-vale-skills.ini').read_text()
        for ident,egg in EGGS.items():
            item=p['items'][str(ident)];self.assertEqual(item['special'],4);self.assertEqual(item['acquisition']['buy'],[EGGKEEPER['id']]);self.assertFalse(item['acquisition'].get('craft'))
            self.assertEqual(p['spells'][str(egg['spell_id'])]['max_level'],0)
            for raw in re.findall(r'^\d+\.learn\s*=\s*(.*)$',skilltext,re.M):self.assertNotIn(egg['spell_id'],list(map(int,raw.split(',')))[::14])
    @unittest.skipUnless((ROOT/'work/class-combat/runtime/data/balance-profile.json').exists(),'installed profile unavailable')
    def test_combined_summoner_budget_stays_within_the_class_cohort(self):
        from balance_model import benchmarks
        p=json.loads((ROOT/'work/class-combat/runtime/data/balance-profile.json').read_text());rows=benchmarks(p)
        for level in (1,8,15,25,35,45):
            cohort=[r for r in rows if r['level']==level];summoner=next(r for r in cohort if r['class_id']==7);others=[r['burst_dps'] for r in cohort if r['class_id']!=7]
            self.assertEqual(summoner['companion_dps']>0,level>=TIERS['normal']['level']);self.assertLessEqual(summoner['burst_dps'],max(others)*1.10)
            if level>=TIERS['rare']['level']:self.assertGreaterEqual(summoner['burst_dps'],max(others)*.70)

if __name__=='__main__':unittest.main()
