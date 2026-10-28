"""Classic price preservation, reserved IDs and compiled native Gold selection."""
import hashlib,json,shutil,subprocess,tempfile,unittest
from pathlib import Path
from configure_classic_economy import configure,ini,DATA
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'work/feature-content-runtime'

class ClassicFactsTests(unittest.TestCase):
    def test_source_coverage_and_high_impact_prices(self):
        facts=json.loads(DATA.read_text());self.assertEqual(len(facts['shops']),42);self.assertEqual(len(facts['gold']),50)
        self.assertEqual(len(facts['npc_drops']),159);self.assertEqual(sum(len(n['drops']) for n in facts['npc_drops']),262)
        gold={r['npc_id']:{k:v for k,v in r.items() if k!='npc_id'} for r in facts['gold']}
        all_gold={n['npc_id']:{k:v for k,v in r.items() if k!='id'} for n in facts['npc_drops'] for r in n['drops'] if r['id']==1}
        self.assertEqual(gold,all_gold)
        for npc in facts['npc_drops']:
            for row in npc['drops']:
                self.assertTrue(0<=row['minimum']<=row['maximum']);self.assertTrue(0<=row['chance']<=100)
        rat=next(r for r in facts['gold'] if r['npc_id']==2);self.assertEqual((rat['minimum'],rat['maximum'],rat['chance']),(0,3,10))
        grocery=next(r for r in facts['shops'] if r['id']==3)
        self.assertIn(dict(id=5,buy=120,sell=10),grocery['trade'])
        desert=next(r for r in facts['shops'] if r['id']==15)
        self.assertIn(dict(id=375,buy=120,sell=10),desert['trade'])

    @unittest.skipUnless(shutil.which('git') and (ROOT/'work/etheos/.git').exists(),'pinned native checkout unavailable')
    def test_drop_patch_upgrade_and_repeated_setup(self):
        import importlib.util
        spec=importlib.util.spec_from_file_location('classic_server_setup',ROOT/'server/setup.py')
        setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(setup)
        with tempfile.TemporaryDirectory() as td:
            source=Path(td);(source/'src').mkdir()
            for name in ['npc.cpp','eoserv_config.cpp']:
                (source/'src'/name).write_bytes(subprocess.check_output(['git','-C',str(ROOT/'work/etheos'),'show','HEAD:src/'+name]))
            subprocess.run(['git','init','--quiet',str(source)],check=True)
            subprocess.run(['git','-C',str(source),'add','src'],check=True)
            subprocess.run(['git','-C',str(source),'-c','user.name=Native fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','Pinned fixture source'],check=True)
            patches=[ROOT/'server/patches'/name for name in ['etheos-drop-rate.patch','etheos-classic-gold.patch']]
            # Fresh install, then a repeat run on the already upgraded source.
            setup.apply_patches(source,patches)
            first=[p.read_bytes() for p in sorted((source/'src').iterdir())]
            setup.apply_patches(source,patches)
            self.assertEqual(first,[p.read_bytes() for p in sorted((source/'src').iterdir())])

    @unittest.skipUnless(BASE.exists(),'private native resources unavailable')
    def test_stopped_world_restoration_is_idempotent_and_preserves_characters_pub_and_items(self):
        with tempfile.TemporaryDirectory() as td:
            target=Path(td);shutil.copytree(BASE,target,dirs_exist_ok=True)
            (target/'database.sdb').write_bytes(b'Account data must never be opened')
            before={str(p.relative_to(target)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [target/'database.sdb',*target.glob('data/pub/*'),*target.glob('data/maps/*')] if p.is_file()}
            cfg=ini((target/'config.local.ini').read_text());configure(target)
            after_cfg=ini((target/'config.local.ini').read_text())
            self.assertEqual(cfg.get('ExpRate'),after_cfg.get('ExpRate'));self.assertEqual(after_cfg.get('DropRate'),'100%')
            self.assertEqual(after_cfg['GoldDropRate'],'100%');self.assertEqual(after_cfg['InnSleepCostBase'],'0')
            self.assertEqual(after_cfg['InnSleepCostPerHP'],'1');self.assertEqual(after_cfg['InnSleepCostPerTP'],'1')
            drops=ini((target/'data/aster-vale-drops.ini').read_text())
            self.assertIn('1,0,3,10',drops['2']);self.assertEqual(drops['3'],'99,1,1,1, 100,1,1,1, 250,1,1,10')
            self.assertIn('457,1,1,1',drops['255']);self.assertEqual(drops['129'],'')
            self.assertFalse(any(row.strip().startswith('1,') for row in drops['255'].split(', ')))
            shops=ini((target/'data/aster-vale-shops.ini').read_text())
            self.assertEqual(shops['304.craft'],'430,460,1,492,40,0,0,0,0,431,465,1,492,40,0,0,0,0')
            self.assertIn('5,120,10',shops['22.trade']);self.assertEqual(shops['22.trade'].count('6,120,'),1)
            for name,expected in before.items():self.assertEqual(hashlib.sha256((target/name).read_bytes()).hexdigest(),expected)
            files=[target/'config.local.ini',target/'data/aster-vale-drops.ini',target/'data/aster-vale-shops.ini'];first=[p.read_bytes() for p in files]
            self.assertEqual(configure(target)['changed_shop_fields'],[]);self.assertEqual(first,[p.read_bytes() for p in files])
            from configure_feature_content import configure as features
            features(target);self.assertEqual(first,[p.read_bytes() for p in files])

    @unittest.skipUnless(shutil.which('g++') and (ROOT/'work/classic-native-after/npc.cpp').exists(),'native build source unavailable')
    def test_compiled_actual_native_gold_probability_item_boost_caps_and_legacy(self):
        source=(ROOT/'work/classic-native-after/npc.cpp').read_text()
        block=source.split('else if (dropratemode == 3)',1)[1].split('\n\tif (sharemode == 1)',1)[0]
        cpp=r'''#include <algorithm>
#include <map>
#include <string>
#include <memory>
#include <vector>
#include <cassert>
namespace util{double sample;double rand(double lo,double hi){return lo+(hi-lo)*sample;}}
#define UTIL_FOREACH_CREF(items,item) for(const auto &item:items)
struct NPC_Drop{int id;double chance,chance_offset;};
struct Table{std::vector<std::unique_ptr<NPC_Drop>> drops;};
struct World{std::map<std::string,double> config;};struct Map{World*world;};
struct NPC{World world;Map m;Map*map;Table data;NPC():m{&world},map(&m){}
Table&Data(){return data;}int roll(double droprate){NPC_Drop*drop=nullptr;
'''+block+r'''
return drop?drop->id:0;}};
void check(double gold,double item,double boost,double goldrate,int wantgold,int wantitem){
NPC npc;npc.world.config["GoldDropRate"]=goldrate;
npc.data.drops.emplace_back(new NPC_Drop{2,item,0});npc.data.drops.emplace_back(new NPC_Drop{1,gold,item});
int counts[3]={};for(int i=0;i<100000;i++){util::sample=(i+.5)/100000.;counts[npc.roll(boost)]++;}
assert(counts[1]==wantgold);assert(counts[2]==wantitem);}
int main(){check(10,20,2,1,10000,40000);check(90,20,2,1,90000,10000);
check(98.04,10,2,1,98040,1960);check(10,20,0,1,10000,0);
check(10,20,2,0,0,40000);check(0,20,2,1,0,40000);check(10,20,2,-1,20000,40000);
check(10,20,1,1,10000,20000);check(100,20,2,1,100000,0);}
'''
        with tempfile.TemporaryDirectory() as td:
            path=Path(td);(path/'test.cpp').write_text(cpp)
            subprocess.run(['g++','-std=c++11','-O2',str(path/'test.cpp'),'-o',str(path/'test')],check=True,capture_output=True)
            subprocess.run([str(path/'test')],check=True,capture_output=True)

if __name__=='__main__':unittest.main()
