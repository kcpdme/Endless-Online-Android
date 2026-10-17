"""Native reward settings and compiled production mode3 weighted-drop algorithm."""
import shutil,subprocess,tempfile,unittest
from pathlib import Path
from configure_rates import configure
ROOT=Path(__file__).resolve().parents[1]
class RewardRateTests(unittest.TestCase):
    def test_exact_original_multipliers_idempotent_and_other_rules_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'config.local.ini';p.write_text('ExpRate = 500%\nDropRate = 400%\nShareMode = 2\nDropRateMode = 3\nMobRate = 100%\n')
            configure(tmp);first=p.read_bytes();configure(tmp);self.assertEqual(first,p.read_bytes())
            self.assertEqual(p.read_text(),'ExpRate = 1000%\nDropRate = 200%\nShareMode = 2\nDropRateMode = 3\nMobRate = 100%\n')
    @unittest.skipUnless(shutil.which('g++') and (ROOT/'work/etheos/src/npc.cpp').exists(),'native source/compiler unavailable')
    def test_compiled_native_drop_mode3_probability_scaling_and_caps(self):
        # Compile the ACTUAL production block, supplying only Data/rand fixtures.
        src=(ROOT/'work/etheos/src/npc.cpp').read_text();block=src.split('else if (dropratemode == 3)',1)[1].split('\n\tif (sharemode == 1)',1)[0]
        harness=r'''#include <algorithm>
#include <vector>
#include <memory>
#include <cassert>
namespace util { double sample; double rand(double lo,double hi){return lo+(hi-lo)*sample;} }
#define UTIL_FOREACH_CREF(items,item) for(const auto &item:items)
struct NPC_Drop { int id; double chance, chance_offset; };
struct Table { std::vector<std::unique_ptr<NPC_Drop>> drops; };
struct NPC { Table data; Table& Data(){return data;}
int roll(double droprate){NPC_Drop*drop=nullptr;
''' + block + r'''
return drop?drop->id:0; }
};
void verify(double a,double b,double rate,int count1,int count2){
 NPC npc;npc.data.drops.emplace_back(new NPC_Drop{1,a,0});npc.data.drops.emplace_back(new NPC_Drop{2,b,a});
 int counts[3]={};for(int i=0;i<10000;i++){util::sample=(i+.5)/10000.;counts[npc.roll(rate)]++;}
 assert(counts[1]==count1&&counts[2]==count2&&counts[0]==10000-count1-count2);
}
int main(){verify(10,20,1,1000,2000);verify(10,20,2,2000,4000);verify(10,20,.5,500,1000);verify(10,20,0,0,0);verify(40,60,2,4000,6000);verify(0,0,2,0,0);verify(80,120,1,4000,6000);}
'''
        with tempfile.TemporaryDirectory() as td:
            p=Path(td);(p/'test.cpp').write_text(harness)
            subprocess.run(['g++','-std=c++11','-O2',str(p/'test.cpp'),'-o',str(p/'test')],check=True,capture_output=True)
            subprocess.run([str(p/'test')],check=True,capture_output=True)
if __name__=='__main__':unittest.main()
