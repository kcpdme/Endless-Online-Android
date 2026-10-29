"""Classic newborn equivalence and both combat-formula branches, in isolation.

Uses the actual pinned C++ RPN evaluator, not a Python imitation, and native
character creation/login packets. Never opens the production account database.
"""
import argparse,json,math,os,random,secrets,shutil,socket,sqlite3,subprocess,tempfile,time
from pathlib import Path
from configure_classic_economy import ini
from eo_session import Session
from live_session import LiveSession
from test_online import dev_name

ROOT=Path(__file__).resolve().parents[1]
KEYS=('class_id','level','hp','max_hp','tp','max_tp','min_damage','max_damage',
      'accuracy','evade','armor','strength','intelligence','wisdom','agility','constitution','charisma',
      'max_sp','stat_points','skill_points','karma','weight','max_weight','experience','admin')
CPP='''#include "util/rpn.hpp"
#include <iostream>
#include <iomanip>
#include <sstream>
int main() {
 std::cout << std::setprecision(17);
 std::string line;
 while(std::getline(std::cin,line)) {
  std::istringstream in(line); std::string expr,pair;
  std::getline(in,expr,'\\t'); std::unordered_map<std::string,double> vars;
  while(in>>pair) { auto at=pair.find('='); vars[pair.substr(0,at)]=std::stod(pair.substr(at+1)); }
  std::cout << util::rpn_eval(util::rpn_parse(expr),vars) << '\\n';
 }
}'''

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--runtime',type=Path,default=ROOT/'work/peasant-v14/runtime')
 p.add_argument('--report',type=Path,default=ROOT/'docs/peasant-v14-native-report.json')
 args=p.parse_args();out=ROOT/'work/peasant-v14';out.mkdir(exist_ok=True)
 checks=0;results={};source=args.runtime.resolve()
 def check(ok,why):
  nonlocal checks
  if not ok:raise AssertionError(why)
  checks+=1
 with tempfile.TemporaryDirectory(prefix='aster-peasant-') as tmp:
  base=Path(tmp);src=ROOT/'work/server-build/source/src';cpp=base/'rpn.cpp';cpp.write_text(CPP)
  subprocess.run(['g++','-std=c++17','-I',str(src),str(cpp),str(src/'util/rpn.cpp'),str(src/'util/variant.cpp'),str(src/'util.cpp'),'-o',str(base/'rpn')],check=True,capture_output=True)
  current=ini((source/'data/formulas.ini').read_text())
  classic=ini((source/'data/balance-v1-baseline/data/formulas.ini').read_text())
  modern=ini((ROOT/'work/classic-rates-board/runtime/data/formulas.ini').read_text())
  # Include zero-stat/zero-armour cases, every class, NPC attacks and PK pairs.
  rng=random.Random(1400);lines=[];labels=[]
  for attacker in (*range(9),None):
   for target in (*range(9),None):
    for _ in range(40):
     values=dict(accuracy=rng.choice([0,1,2,10,30,100]),target_evade=rng.choice([0,1,5,40]),
                 target_armor=rng.choice([0,1,10,50]),damage=rng.choice([0,1,2,3,40,100]),
                 critical=rng.randrange(2),target_sitting=rng.randrange(2),modifier=1)
     values.update({'npc':1} if attacker is None else {'class':attacker})
     values.update({'target_npc':1} if target is None else {'target_class':target})
     reference=classic if attacker in (0,1) or target in (0,1) else modern
     for key in ('hit_rate','damage'):
      values_text=' '.join(f'{k}={v}' for k,v in values.items())
      lines.extend(expr+'\t'+values_text for expr in (current[key],reference[key]))
      labels.append((attacker,target,key,values))
  run=subprocess.run([str(base/'rpn')],input='\n'.join(lines)+'\n',capture_output=True,text=True,check=True)
  values=list(map(float,run.stdout.splitlines()));check(len(values)==len(lines),'C++ evaluator consumed every case')
  for i,label in enumerate(labels):
   check(math.isfinite(values[i*2]) and math.isclose(values[i*2],values[i*2+1],rel_tol=1e-12,abs_tol=1e-12),f'Wrong formula branch: {label}: {values[i*2:i*2+2]}')
  formula_cases=len(labels)
  for variant in ('current','classic_reference'):
   r=base/variant;shutil.copytree(source,r,ignore=shutil.ignore_patterns('database.sdb*','*.log'))
   os.environ['ASTER_VALE_RUNTIME']=str(r)
   cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18972\nIPReconnectLimit = 0\n')
   if variant=='classic_reference':
    for rel in ('data/pub/dat001.ecf','data/pub/dat001.eif','data/pub/dtn001.enf','data/formulas.ini'):
     shutil.copy2(r/'data/balance-v1-baseline'/rel,r/rel)
    cfg.write_text(cfg.read_text()+'\nBalanceRevamp = no\nClassIdentityRules = no\nClassSignatureRules = no\nCombatProgression = no\nClassMobility = no\nCarryCapacityRules = no\nUseClassFormulas = no\nPermanentPetCollection = no\nOwnerScaledPets = no\n')
   with (out/(variant+'-native.log')).open('w') as log:
    proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
    try:
     for _ in range(100):
      if proc.poll() is not None:raise RuntimeError('Native world failed')
      try:
       with socket.create_connection(('127.0.0.1',18972),timeout=.1):break
      except OSError:time.sleep(.1)
     time.sleep(.5);results[variant]=[]
     for gender in (0,1):
      f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18972)
      try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'],gender=gender)
      finally:s.close()
      def sample(label):
       s=LiveSession('127.0.0.1',18972)
       try:
        cs=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in cs if c['name']==f['name']));s.snapshot()
        results[variant].append(dict(label=label,gender=gender,stats={k:s.stats[k] for k in KEYS}))
        if label=='birth':check(not s.inventory and not s.spells and all(v==0 for v in s.equipment.values()),'Birth has no items, spells or equipment')
       finally:s.close()
      def stage(**values):
       time.sleep(.65)
       with sqlite3.connect(r/'database.sdb') as db:
        db.execute('UPDATE characters SET '+','.join('"'+k+'"=?' for k in values)+' WHERE name=? AND account=?',(*values.values(),f['name'],f['username']))
      time.sleep(.65);sample('birth')
      for clas in (0,1):
       for level in (0,4,10):
        for weapon in (0,21):
         doll=[0]*15;doll[4]=144 if gender else 151;doll[8]=weapon
         stage(**{'class':clas,'level':level,'hp':1,'tp':1,'str':level,'agi':level,'con':level,'paperdoll':','.join(map(str,doll))})
         sample(f'class{clas}/level{level}/weapon{weapon}')
    finally:proc.terminate();proc.wait(timeout=15)
  check(results['current']==results['classic_reference'],'Both genders: newborn and level 0/4/10 Peasants match classic native stats with clothes, Dagger and earned attributes')
  newborn=results['current'][0]['stats']
  check(all(newborn[k]==v for k,v in dict(hp=10,max_hp=10,tp=10,max_tp=10,min_damage=0,max_damage=1,accuracy=0,evade=0,armor=0,max_sp=20,stat_points=0,skill_points=0,karma=1000,weight=0,max_weight=70,experience=0,admin=0).items()),'Exact bare classic newborn baseline')
  report=dict(result='passed',profile=14,checks=checks,cpp_combat_formula_cases=formula_cases,
              native_stat_configurations=len(results['current']),birth=newborn,native_samples=results['current'],
              peasant_incoming_outgoing_and_pk_use_classic_formulas=True,
              professional_classes_keep_modern_formulas=True,isolated_database=True,production_database_opened=False)
  args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps({k:v for k,v in report.items() if k!='native_samples'},indent=2))

if __name__=='__main__':main()
