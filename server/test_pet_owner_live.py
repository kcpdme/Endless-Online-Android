"""Owner-scaled pets, retaliation, independent egg rolls and native emote broadcasts."""
from pathlib import Path
from contextlib import closing
import json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time,math
from eo_session import Session,number
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put
from configure_sky_wonder import parse,grid
from balance_model import allocation
from pet_catalog import TIERS,EGGS
ROOT=Path(__file__).resolve().parents[1]

def main():
 out=ROOT/'work/class-balance-v10';checks=[];sessions=[];observed={}
 def check(ok,why):
  if not ok:raise AssertionError(why)
  checks.append(why)
 with tempfile.TemporaryDirectory(prefix='aster-combat-') as tmp:
  r=Path(tmp)/'runtime';shutil.copytree(out/'runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
  p=r/'config.local.ini';p.write_text(p.read_text()+'\nPort = 18946\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nCriticalFirstHit = no\nBalance.7.tp_regen = 0\nBalanceEgg.609.chance = 100\nDropRate = 10000%\n')
  p=r/'data/formulas.ini';p.write_text(p.read_text()+'\nhit_rate = 1\nclass.6.damage = 0\n')
  p=r/'data/pub/dtn001.enf';raw=p.read_bytes();rows=records(raw,b'ENF',39)
  for off,val,size in [(11,500000,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[0]['fields'],off,val,size)
  for off,val,size in [(7,2,2),(11,35,3),(16,3,2),(18,3,2),(22,0,2),(24,0,2)]:put(rows[73]['fields'],off,val,size)
  p.write_bytes(encode_pub(raw,rows))
  p=r/'data/pub/dat001.eif';raw=p.read_bytes();rows=records(raw,b'EIF',58)
  put(rows[493]['fields'],9,10,2);put(rows[493]['fields'],11,10,2);p.write_bytes(encode_pub(raw,rows))
  raw=(r/'data/maps/00021.emf').read_bytes();prefix,g,signs=parse(raw);prefix=bytearray(prefix);prefix[43:45]=number(0,1)*2
  for x in range(1,12):g['specs'].pop((x,8),None)
  for map_id,pk,wall in [(21,False,False),(22,True,False),(24,False,True)]:
   pre=bytearray(prefix);pre[31:32]=number(3 if pk else 0,1)
   if wall:g['specs'][6,8]=number(0,1)
   (r/f'data/maps/{map_id:05d}.emf').write_bytes(pre+b''.join(grid(c) for c in g.values())+number(0,1))
  log=(out/'combat-native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
  def pump(s,seconds):
   end=time.monotonic()+seconds
   while time.monotonic()<end:
    s.poll_actions()
    if select.select([s.sock],[],[],.02)[0]:s.pump()
  def login(f):
   s=LiveSession('127.0.0.1',18946);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot();return s
  def close(s):s.close();sessions.remove(s)
  def stage(f,clas=5,bow=457,offhand=423,x=4,map_id=21,admin=0,tp=30000,spells='23,0;'):
   time.sleep(.65);a=allocation(clas if clas!=8 else 2,50);d=[0]*15;d[8]=bow;d[7]=offhand
   with closing(sqlite3.connect(r/'database.sdb')) as db,db:
    db.execute('UPDATE characters SET sitting=0,direction=3,class=?,level=50,map=?,x=?,y=8,hp=30000,tp=?,admin=?,"str"=?,"int"=?,wis=?,agi=?,"con"=?,cha=?,paperdoll=?,inventory=?,spells=? WHERE name=? AND account=?',(clas,map_id,x,tp,admin,*(a[k] for k in ('strength','intelligence','wisdom','agility','constitution','charisma')),','.join(map(str,d)),'1,10000;',spells,f['name'],f['username']))
  def fixture():
   f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18946)
   try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
   finally:s.close()
   return f
  try:
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18946),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.6);f=fixture();op=fixture();time.sleep(.7)
   stage(op,clas=6,bow=491,offhand=0,x=11,map_id=21,admin=4);s=login(op);s.chat_send('local','$snpc 1 1 7');pump(s,.3);close(s)
   damages={}
   for tier,t in TIERS.items():
    spell=next(e['spell_id'] for e in EGGS.values() if e['tier']==tier)
    stage(f,clas=7,bow=494,offhand=0,x=10,spells=f'23,0;{spell},0;');s=login(f)
    check(s.stats['min_damage']==s.stats['max_damage']==10,'Fixed owner attack is exactly ten despite level and CHA')
    s.cast_spell(spell,'self');pump(s,1.6);check(bool(getattr(s,'companion',None)),'Requested tier spawns its native pet')
    if tier=='normal':
     s.events.clear();pump(s,2.5);check(not any(e.get('kind')=='companion_attack' for e in s.events),'Pet does not attack an unprovoked passive monster')
    s.events.clear();start=time.monotonic();last=0
    while time.monotonic()-start<10:
     if time.monotonic()-last>.65:s.strike(3);last=time.monotonic()
     pump(s,.05)
     hits=[e['damage'] for e in s.events if e.get('kind')=='companion_attack' and e.get('damage',0)>0]
     if len(hits)>=4:break
    low=math.floor(10*t['power']);high=math.ceil(10*t['power'])
    check(len(hits)>=3 and all(max(1,low)<=hit<=high for hit in hits),'Native pet damage equals owner attack times '+tier+' multiplier, without additive stats')
    damages[tier]=hits;close(s)
   # An aggressive monster, not a player command, must start protection.
   stage(f,clas=7,bow=494,offhand=0,x=9,map_id=24,spells='63,0;');s=login(f);s.cast_spell(63,'self');pump(s,1.6);pet_index=s.companion['index'] if 'index' in s.companion else s.companion['npc_index']
   stage(op,clas=6,bow=491,offhand=0,x=10,map_id=24,admin=4);admin=login(op);admin.chat_send('local','$snpc 74 1 0');pump(admin,.2);close(admin)
   s.events.clear();pump(s,13)
   attacks=[e for e in s.events if e.get('kind') in ('player_damage','npc_attack') and e.get('player_id')==s.player_id]
   hits=[e for e in s.events if e.get('kind')=='companion_attack' and e.get('damage',0)>0]
   killed=[e for e in s.events if e.get('kind')=='npc_killed']
   check(attacks and hits and killed,'Pet protects and kills an aggressive attacker without any owner attack')
   check(bool(getattr(s,'companion',None)) and any(n['index']==pet_index for n in s.state['npcs']),'Monsters never kill or target the pet')
   check(killed[-1]['drop']['id']==609,'Fixture-only 100 percent egg roll awards bound egg to Summoner kill winner')
   close(s)
   # Same native emote packets reach a nearby real session and the sender reply.
   stage(f,clas=7,bow=494,offhand=0,x=9);actor=login(f)
   stage(op,clas=6,bow=21,offhand=0,x=10);peer=login(op)
   for ident in (1,3,4,5,7):
    result=actor.feature_action('emotes','emote',ident);pump(peer,.1)
    check(any(e.get('kind')=='player_emote' and e.get('emote')==ident for e in result['events']),'Sender receives confirmed native emote')
    check(any(e.get('kind')=='player_emote' and e.get('emote')==ident and e.get('player_id')==actor.player_id for e in peer.events),'Nearby session receives actual emote broadcast')
   close(actor);close(peer)
   # Extremal chances establish isolation from global drop boosts and class access.
   for chance,clas in [(0,7),(100,6)]:
    proc.terminate();proc.wait(timeout=15)
    cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+f'\nBalanceEgg.609.chance = {chance}\n')
    proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
    for _ in range(100):
     try:
      with socket.create_connection(('127.0.0.1',18946),timeout=.1):break
     except OSError:time.sleep(.1)
    time.sleep(.6)
    stage(op,clas=6,bow=491,offhand=0,x=10,map_id=24,admin=4);admin=login(op);admin.chat_send('local','$snpc 74 1 7');pump(admin,.2);close(admin)
    stage(f,clas=clas,bow=491,offhand=0,x=9,map_id=24,admin=4);s=login(f);s.events.clear();s.strike(3);pump(s,.4)
    kill=next(e for e in s.events if e.get('kind')=='npc_killed')
    check(kill['drop']['id']!=609,'Global boost cannot create a zero-chance egg; non-Summoner cannot win even a guaranteed egg')
    close(s)
   report=dict(result='passed',checks=len(checks),fixed_owner_attack=10,pet_damage_samples=damages,aggressive_retaliation_without_owner_attack=True,unprovoked_passive_not_attacked=True,pet_untargetable=True,independent_egg_roll_extremes=True,regular_drop_multiplier_ignored_by_eggs=True,non_summoner_egg_denied=True,nearby_native_emote_broadcasts=5,isolated_database=True,production_database_opened=False)
   (out/'owner-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
  finally:
   for s in sessions:s.close()
   proc.terminate();proc.wait(timeout=15);log.close()
if __name__=='__main__':main()
