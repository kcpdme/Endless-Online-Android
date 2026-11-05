"""Check classic Dragon facts and run the actual native selector over all roll intervals."""
import json, shutil, subprocess, tempfile, unittest
from pathlib import Path
from configure_classic_economy import DATA, ini

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'work/server-build/source/src/npc.cpp'
RUNTIME = ROOT/'work/class-run-v15/runtime'


class DragonDropTests(unittest.TestCase):
    def test_classic_dragon_drops_and_warrior_buyback(self):
        facts = json.loads(DATA.read_text())
        dragon = next(n for n in facts['npc_drops'] if n['npc_id']==225)
        chances = {n['id']:n['chance'] for n in dragon['drops']}
        self.assertEqual(chances,{457:.05,456:1,458:1,459:1,1:40,470:10,469:10})
        warrior = next(s for s in facts['shops'] if s['id']==40)
        self.assertEqual(warrior['trade'],[dict(id=469,buy=0,sell=250)])
        self.assertEqual(warrior['craft'],[])

    @unittest.skipUnless(shutil.which('g++') and SOURCE.exists() and RUNTIME.exists(),'native source/compiler/runtime unavailable')
    def test_native_dragon_selector_has_exact_nonzero_rare_drop_intervals(self):
        source = SOURCE.read_text()
        start = source.index('{',source.index('else if (dropratemode == 3)'))
        depth = 1; end = start+1
        while depth:
            depth += (source[end]=='{') - (source[end]=='}'); end += 1
        block = source[start:end]
        # The native code excludes bound pet eggs from the ordinary loot roll.
        raw = ini((RUNTIME/'data/aster-vale-drops.ini').read_text())['225'].split(',')
        rows = [(int(raw[i]),float(raw[i+3])) for i in range(0,len(raw),4) if int(raw[i]) in (1,456,457,458,459,469,470)]
        entries = ''.join('npc.drops.push_back({%d,%.12g,0});\n'%row for row in rows)
        expected = {457:100,456:2000,458:2000,459:2000,1:80000,470:20000,469:20000,0:73900}
        cpp = r'''#include <algorithm>
#include <iostream>
#include <map>
#include <string>
#include <vector>
namespace util { double sample; double rand(double lo,double hi) { return lo+(hi-lo)*sample; } }
#define UTIL_FOREACH_CREF(items,item) for (const auto& item:items)
struct NPC_Drop { int id; double chance,chance_offset; };
struct World { std::map<std::string,double> config; };
struct Map { World* world; };
struct NPC {
 World world; Map m{&world}; Map* map=&m; std::vector<NPC_Drop> drops;
 int roll() { double droprate=1.0; NPC_Drop* drop=nullptr;
 std::vector<NPC_Drop*> eligible_drops; for(auto& d:drops) eligible_drops.push_back(&d);
''' + block + r'''
 return drop ? drop->id : 0; }
};
int main() { NPC npc; npc.world.config["GoldDropRate"]=1.0;
''' + entries + r'''
 std::map<int,int> counts;
 for(int i=0;i<200000;++i) { util::sample=(i+.5)/200000.; ++counts[npc.roll()]; }
 for(auto entry:counts) std::cout<<entry.first<<" "<<entry.second<<"\n";
}
'''
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); (root/'drops.cpp').write_text(cpp)
            subprocess.run(['g++','-std=c++11','-O2',str(root/'drops.cpp'),'-o',str(root/'drops')],check=True,capture_output=True)
            output=subprocess.check_output([str(root/'drops')],text=True)
        observed = {int(k):int(v) for k,v in (line.split() for line in output.splitlines())}
        self.assertEqual(observed,expected)


if __name__ == '__main__': unittest.main()
