#!/usr/bin/env python3
"""Native signature, egg loot and hatching acceptance in a disposable database."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time
from pathlib import Path
from contextlib import closing
from eo_session import Session,number,EOError
from test_online import dev_name
from configure_balance import records,encode_pub,put
from balance_model import allocation
ROOT=Path(__file__).resolve().parents[1]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,default=ROOT/'work/balance-v3/runtime');p.add_argument('--report',type=Path,default=ROOT/'work/balance-v3/signature-native-report.json');a=p.parse_args()
 checks=[];sessions=[]
 def check(ok,why):
  if not ok:raise AssertionError(why)
  checks.append(why)
 with tempfile.TemporaryDirectory(prefix='aster-signatures-') as tmp:
  base=Path(tmp);r=base/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'))
  os.environ['ASTER_VALE_RUNTIME']=str(r)
  cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18906\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nCriticalFirstHit = no\nDropRate = 100%\n')
  room=r/'data/maps/00021.emf';data=bytearray(room.read_bytes());data[0x2B:0x2D]=number(0,1)*2;room.write_bytes(data)
  path=r/'data/pub/dtn001.enf';data=path.read_bytes();rows=records(data,b'ENF',39)
  for ident,hp in [(1,50000),(74,1)]:
   for off,value,size in [(11,hp,3),(16,0,2),(18,0,2),(20,0,2),(22,0,2),(24,0,2)]:put(rows[ident-1]['fields'],off,value,size)
  path.write_bytes(encode_pub(data,rows))
  path=r/'data/pub/dat001.eif';data=path.read_bytes();rows=records(data,b'EIF',58)
  # Fixed blade endpoints make both random backstab factors independently visible.
  put(rows[532]['fields'],9,20,2);put(rows[532]['fields'],11,20,2);path.write_bytes(encode_pub(data,rows))
  path=r/'data/formulas.ini';path.write_text(path.read_text()+'\nhit_rate = 1\n')
  # Guaranteed egg is a fixture-only drop table; production keeps ordinary odds.
  path=r/'data/aster-vale-drops.ini';path.write_text(path.read_text()+'\n74 = 609,1,1,100\n')
  log=(base/'native.log').open('w');proc=subprocess.Popen([str((r/'etheos').resolve())],cwd=r,stdout=log,stderr=subprocess.STDOUT)
  try:
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18906),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.6)
   def provision():
    f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18906)
    try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
    finally:s.close()
    return f
   fixtures={c:provision() for c in (2,4,5,6,7)};admin=provision();time.sleep(.7)
   def stage(f,clas,level=25,xy=(9,8),weapon=21,body=144,spells='1,0;12,0;13,0;23,0;30,0;32,0;35,0;',inventory='1,2000;',admin=0):
    time.sleep(.7);attrs=allocation(clas if clas in (2,4,5,6,7) else 6,level);doll=[0]*15;doll[8]=weapon;doll[4]=body
    with closing(sqlite3.connect(r/'database.sdb')) as db,db:
     db.execute('UPDATE characters SET class=?,level=?,gender=1,map=21,x=?,y=?,"str"=?,"int"=?,wis=?,agi=?,"con"=?,cha=?,hp=1,tp=30000,spells=?,paperdoll=?,inventory=?,admin=? WHERE name=? AND account=?',(clas,level,*xy,*(attrs[k] for k in ('strength','intelligence','wisdom','agility','constitution','charisma')),spells,','.join(map(str,doll)),inventory,admin,f['name'],f['username']))
   from live_session import LiveSession
   def login(f):
    s=LiveSession('127.0.0.1',18906);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot();return s
   def close(s):s.close();sessions.remove(s)
   def pump_until(s,predicate,timeout=6):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
     s.poll_actions()
     if predicate():return
     if select.select([s.sock],[],[],.03)[0]:s.pump()
    raise AssertionError('Native signature event did not arrive')
   def strike(s,direction):
    s.events.clear();s.strike(direction);pump_until(s,lambda:any(e.get('kind') in ('npc_damage','npc_killed') for e in s.events));return next(e for e in s.events if e.get('kind') in ('npc_damage','npc_killed'))
   def raw_cast(s,ident,target):
    s.events.clear();s.timestamp+=200;tick=s.timestamp;s.send(12,1,number(ident,2)+number(tick,3));time.sleep(.53)
    s.send(12,31,number(2,1)+number(1,1)+number(1,2)+number(ident,2)+number(target,2)+number(tick+48,3));s.timestamp=tick+48;time.sleep(.3);s.refresh()
   stage(admin,6,45,xy=(9,7),weapon=491,admin=4);op=login(admin);op.chat_send('local','$snpc 1 1 7');pump_until(op,lambda:any(n['id']==1 for n in op.state['npcs']));close(op)
   stage(fixtures[4],4,25,xy=(9,6),weapon=533,body=545);rogue=login(fixtures[4]);rogue.refresh()
   base_damage=rogue.stats['min_damage'];check(base_damage==rogue.stats['max_damage'],'Backstab fixture has fixed native base damage')
   target=next(n for n in rogue.state['npcs'] if n['id']==1);expected={int(base_damage*1.5),int(base_damage*2)};seen=set()
   for _ in range(24):
    damage=strike(rogue,0)['damage'];check(damage in expected,'Rear Rogue blade hit is exactly 1.5x or 2x without stacked criticals');seen.add(damage)
    if seen==expected:break
   check(seen==expected,'Both random Rogue backstab strengths occur in real native attacks')
   for direction in (3,0,0,1):rogue.walk(direction)
   check(strike(rogue,2)['damage']==base_damage,'Front-facing Rogue attack receives no rear bonus')
   rogue.walk(0);tp=rogue.stats['tp'];raw_cast(rogue,30,target['index']);check(rogue.stats['tp']==tp,'Forged Rogue melee spell beyond one tile is denied without TP loss');close(rogue)
   stage(fixtures[6],6,25,xy=(9,9));warrior=login(fixtures[6]);tp=warrior.stats['tp'];raw_cast(warrior,32,target['index']);check(warrior.stats['tp']==tp,'Forged Warrior melee spell beyond one tile is denied without TP loss');close(warrior)
   stage(fixtures[5],5,25,xy=(9,9),weapon=316,inventory='1,2000;423,1;');archer=login(fixtures[5]);tp=archer.stats['tp'];raw_cast(archer,13,target['index']);check(archer.stats['tp']==tp,'Forged Archer shot without arrows is denied without TP loss')
   archer.equip(423);check(strike(archer,2)['damage']>0,'Archer bow and arrows deal real native damage from beyond melee range');close(archer)
   stage(fixtures[2],2,25,xy=(11,8));priest=login(fixtures[2]);hp=priest.stats['hp'];tp=priest.stats['tp'];gain=max(1,int(priest.stats['max_hp']*.02))
   pump_until(priest,lambda:priest.stats['hp']>hp,3);check(priest.stats['hp']-hp==gain and priest.stats['tp']==tp,'Priest automatically regenerates the exact HP amount without spending TP');close(priest)
   stage(fixtures[2],6,25,xy=(11,8));former_priest=login(fixtures[2]);hp=former_priest.stats['hp'];until=time.monotonic()+2.5
   while time.monotonic()<until:
    if select.select([former_priest.sock],[],[],.05)[0]:former_priest.pump()
   check(former_priest.stats['hp']==hp,'Changing away from Priest removes passive renewal');close(former_priest)
   # Spawn one fragile Wolfman; the Summoner earns its egg by a real kill/pickup.
   stage(admin,6,45,xy=(11,7),weapon=491,admin=4);op=login(admin);op.chat_send('local','$snpc 74 1 7');pump_until(op,lambda:any(n['id']==74 for n in op.state['npcs']));close(op)
   stage(fixtures[7],7,8,xy=(11,6),spells='23,0;35,0;');summoner=login(fixtures[7]);kill=strike(summoner,0)
   check(kill['kind']=='npc_killed' and kill['drop']['id']==609,'Real monster kill drops the configured Wolf Spirit Egg')
   summoner.pickup(kill['drop']['uid']);check(summoner.item_amount(609)==1,'Monster egg reaches the owner inventory through native pickup')
   gold=summoner.item_amount(1);summoner.use_item(609)
   check(summoner.item_amount(609)==0 and sum(s['id']==28 for s in summoner.spells)==1 and summoner.item_amount(1)==gold,f'Hatching consumes one egg, permanently grants one summon and preserves Gold: egg={summoner.item_amount(609)}, known={[s["id"] for s in summoner.spells]}, Gold={summoner.item_amount(1)}/{gold}')
   close(summoner);time.sleep(.7);summoner=login(fixtures[7]);check(any(s['id']==28 for s in summoner.spells),'Hatched summon ownership survives logout and reconnect')
   tp=summoner.stats['tp'];summoner.cast_spell(28,'self');pump_until(summoner,lambda:bool(getattr(summoner,'companion',None)))
   check(summoner.companion['npc_id']==306 and summoner.stats['tp']==tp-18,'Hatched summon calls the real pet and still pays the published TP cost')
   check(summoner.companion['remaining']==0,'Hatched companion has no fixed lifetime; TP upkeep is its ongoing limit')
   pump_until(summoner,lambda:summoner.stats['tp']==tp-20,4);check(bool(summoner.companion),'Real upkeep drains TP without imposing a fixed summon expiry');close(summoner)
   stage(fixtures[7],7,8,xy=(11,6),spells='28,0;',inventory='1,2000;609,1;');duplicate=login(fixtures[7]);duplicate.send(14,10,number(609,2));duplicate.wait(14,3)
   check(duplicate.item_amount(609)==1 and sum(s['id']==28 for s in duplicate.spells)==1,'Forged duplicate hatch preserves the spare egg and cannot duplicate a skill');close(duplicate)
   for clas,level in [(6,25),(7,1)]:
    stage(fixtures[7],clas,level,xy=(11,6),spells='',inventory='1,2000;609,1;');denied=login(fixtures[7]);denied.send(14,10,number(609,2));denied.wait(14,3)
    check(denied.item_amount(609)==1 and not any(s['id']==28 for s in denied.spells),'Native wrong-class or under-level hatching cannot consume the egg or grant a summon');close(denied)
   # A second disposable world mode verifies compensation where spirit AI is forbidden.
   proc.terminate();proc.wait(timeout=15)
   data=bytearray(room.read_bytes());data[0x1F:0x20]=number(3,1);room.write_bytes(data)
   proc=subprocess.Popen([str((r/'etheos').resolve())],cwd=r,stdout=log,stderr=subprocess.STDOUT)
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18906),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.6)
   from native_settings import map_flags
   map_flags.cache_clear()
   stage(admin,6,45,xy=(9,7),weapon=491,admin=4);op=login(admin);op.chat_send('local','$snpc 1 1 7');pump_until(op,lambda:any(n['id']==1 for n in op.state['npcs']));close(op)
   stage(fixtures[7],7,45,xy=(9,8),spells='28,0;29,0;');duelist=login(fixtures[7]);target=next(n for n in duelist.state['npcs'] if n['id']==1)
   duelist.events.clear();duelist.cast_spell(29,'npc',target['index']);pump_until(duelist,lambda:any(e.get('kind')=='npc_damage' and e.get('spell_id')==29 for e in duelist.events))
   damage=next(e['damage'] for e in duelist.events if e.get('kind')=='npc_damage' and e.get('spell_id')==29)
   check(int(duelist.stats['min_damage']*1.8)+56<=damage<=int(duelist.stats['max_damage']*1.8)+74,'Summoner receives the stronger native spell multiplier where pets are forbidden')
   tp=duelist.stats['tp'];duelist.events.clear();duelist.cast_spell(28,'self');pump_until(duelist,lambda:any(e.get('kind')=='companion' and e.get('spell_id')==28 for e in duelist.events))
   check(not getattr(duelist,'companion',None) and duelist.stats['tp']==tp,'PK companion refusal preserves TP and cannot stack a pet with PvP compensation');close(duelist)
   report=dict(result='passed',checks=len(checks),acceptance_checks=checks,backstab_damage_values=sorted(seen),base_blade_damage=base_damage,isolated_database=True,production_drop_tables_modified=False)
   a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='acceptance_checks'}))
  finally:
   for s in sessions:
    try:s.close()
    except Exception:pass
   proc.terminate();proc.wait(timeout=15);log.close();shutil.copy2(base/'native.log',ROOT/'work/balance-v3/signatures-world.log')
if __name__=='__main__':main()
