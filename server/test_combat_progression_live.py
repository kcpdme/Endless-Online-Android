"""Range, cadence, recovery and shields through real native packets in an isolated world."""
from pathlib import Path
from contextlib import closing
import json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time,math
from eo_session import Session,number
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put
from configure_sky_wonder import parse,grid
from balance_model import allocation
from combat_progression import TP_RECOVERY,SHIELDS
ROOT=Path(__file__).resolve().parents[1]

def main():
 out=ROOT/'work/pet-owner-scale';checks=[];sessions=[];observed={}
 def check(ok,why):
  if not ok:raise AssertionError(why)
  checks.append(why)
 with tempfile.TemporaryDirectory(prefix='aster-combat-') as tmp:
  r=Path(tmp)/'runtime';shutil.copytree(out/'runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
  p=r/'config.local.ini';p.write_text(p.read_text()+'\nPort = 18944\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nCriticalFirstHit = no\n')
  p=r/'data/formulas.ini';p.write_text(p.read_text()+'\nhit_rate = 1\n')
  p=r/'data/pub/dtn001.enf';raw=p.read_bytes();rows=records(raw,b'ENF',39)
  for off,val,size in [(11,500000,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[0]['fields'],off,val,size)
  p.write_bytes(encode_pub(raw,rows))
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
   s=LiveSession('127.0.0.1',18944);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot();return s
  def close(s):s.close();sessions.remove(s)
  def stage(f,clas=5,bow=457,offhand=423,x=4,map_id=21,admin=0,tp=0):
   time.sleep(.65);a=allocation(clas if clas!=8 else 2,50);d=[0]*15;d[8]=bow;d[7]=offhand
   with closing(sqlite3.connect(r/'database.sdb')) as db,db:
    db.execute('UPDATE characters SET sitting=0,direction=3,class=?,level=50,map=?,x=?,y=8,hp=30000,tp=?,admin=?,"str"=?,"int"=?,wis=?,agi=?,"con"=?,cha=?,paperdoll=?,inventory=?,spells=? WHERE name=? AND account=?',(clas,map_id,x,tp,admin,*(a[k] for k in ('strength','intelligence','wisdom','agility','constitution','charisma')),','.join(map(str,d)),'1,10000;','13,0;',f['name'],f['username']))
  def fixture():
   f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18944)
   try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
   finally:s.close()
   return f
  try:
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18944),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.6);f=fixture();op=fixture();time.sleep(.7)
   for m in (21,24):
    stage(op,clas=6,bow=491,offhand=0,x=11,map_id=m,admin=4);s=login(op);s.chat_send('local','$snpc 1 1 7');pump(s,.3);check(any(n['id']==1 and n['x']==11 for n in s.state['npcs']),'Static durable native target spawned');close(s)
   for bow,arrow,reach in [(297,423,3),(316,423,5),(457,423,7),(457,424,9),(457,425,9),(496,423,8)]:
    for distance,hit in [(reach+1,False),(reach,True)]:
     stage(f,bow=bow,offhand=arrow,x=11-distance);s=login(f);s.events.clear();s.strike(3);pump(s,.25)
     damage=[e for e in s.events if e.get('kind')=='npc_damage'];check(bool(damage)==hit,f'Native bow {bow}/arrow {arrow} distance {distance}: hit={hit}')
     check(s.snapshot()['player']['combat']['range_tiles']==reach,'Adapter advertises actual equipped range');close(s)
   stage(f,bow=457,offhand=425,x=2,map_id=24);s=login(f);s.events.clear();s.strike(3);pump(s,.3);check(not any(e.get('kind')=='npc_damage' for e in s.events),'Extended arrows still stop at a wall');close(s)
   for bow in (297,316,457):
    stage(f,bow=bow,x=10);s=login(f);s.events.clear();sent=0;start=time.monotonic()
    while time.monotonic()-start<1.55:
     s.timestamp+=50;s.send(11,10,number(3,1)+number(s.timestamp,3));sent+=1;pump(s,.055)
    hits=[e for e in s.events if e.get('kind')=='npc_damage'];observed[str(bow)]=len(hits)
    bound=math.ceil(1.55/({297:.5,316:.5/1.2,457:.25}[bow]))
    check(1<=len(hits)<=bound,'Forged rapid packets cannot bypass server wall-clock cooldown');close(s)
   print('observed cadence',observed,flush=True)
   check(observed['297']<observed['316']<observed['457'],'Native Crossbow/Scav firing rates exceed starter Bow in order')
   # Range-gated bonus and normal-class movement are checked against native time.
   distances={}
   for x in (7,9,10):
    stage(f,bow=457,x=x);s=login(f);s.events.clear();start=time.monotonic();times=[]
    while time.monotonic()-start<2.2:
     s.timestamp+=50;s.send(11,10,number(3,1)+number(s.timestamp,3));pump(s,.04)
     events=[e for e in s.events if e.get('kind')=='npc_damage']
     while len(times)<len(events):times.append(time.monotonic()-start)
    distances[str(11-x)]=dict(hits=len(times),intervals=[round(b-a,3) for a,b in zip(times,times[1:])])
    floor=.32 if x==7 else .23
    check(len(times)>=5 and all(b-a>=floor for a,b in zip(times,times[1:])),'Scav near/far cadence is bounded by actual target distance')
    close(s)
   check(distances['1']['hits']>distances['4']['hits'] and distances['2']['hits']>distances['4']['hits'],'Scav x2 only within two tiles; x1.5 outside')
   walking={}
   for clas in (4,6):
    stage(f,clas=clas,bow=0,offhand=0,x=2);s=login(f)
    check(s.snapshot()['player']['combat']['move_seconds']==(.21 if clas==4 else .42),'Prediction metadata follows current native class')
    start=time.monotonic();times=[];previous=s.metrics['walk_acks']
    for x in (3,4,5,6):
     s.timestamp+=100 # Forged large timestamps cannot speed up native queue.
     s.move(3,x-2,21,x,8)
    while time.monotonic()-start<2.5 and len(times)<4:
     pump(s,.012)
     if s.metrics['walk_acks']>previous:times.append(time.monotonic()-start);previous=s.metrics['walk_acks']
    check(len(times)==4 and s.state['self']['x']==6,'Four queued valid native walks complete without correction')
    intervals=[b-a for a,b in zip(times,times[1:])];floor=.18 if clas==4 else .38
    check(all(i>=floor for i in intervals),'Forged movement timestamps cannot bypass current-class queue cadence')
    walking[str(clas)]=dict(acknowledgements=4,mean_step_seconds=round(sum(intervals)/len(intervals),3));close(s)
   check(1.7<walking['6']['mean_step_seconds']/walking['4']['mean_step_seconds']<2.3,'Rogue really walks twice as fast as Warrior')
   for clas in (3,7,2,8):
    stage(f,clas=clas,bow=0,offhand=0);s=login(f);start=s.stats['tp'];pump(s,2.15);gain=max(1,int(s.stats['max_tp']*TP_RECOVERY[clas]));check(s.stats['tp']-start in (gain,gain*2),f'Class {clas} standing TP pulse: delta={s.stats["tp"]-start}, expected={gain}, maximum={s.stats["max_tp"]}')
    before=s.stats['tp'];s.sit();before=s.stats['tp'];pump(s,2.15);sitting=max(1,int(s.stats['max_tp']*TP_RECOVERY[clas]*2));check(s.stats['tp']-before in (sitting,sitting*2),f'Class {clas} sitting: delta={s.stats["tp"]-before}, expected={sitting}, max={s.stats["max_tp"]}, seat={s.state["self"].get("sitting")}');close(s)
    stage(f,clas=clas,bow=0,offhand=0,map_id=22);s=login(f);start=s.stats['tp'];pump(s,2.15);pk=max(1,int(s.stats['max_tp']*TP_RECOVERY[clas]*.5));check(s.stats['tp']-start in (pk,pk*2),f'Class {clas} PK: delta={s.stats["tp"]-start}, expected={pk}');close(s)
   stage(f,clas=6,bow=0,offhand=0);s=login(f);start=s.stats['tp'];base=s.stats['armor'];pump(s,2.2);check(s.stats['tp']==start,'Class switch to Warrior removes fast TP recovery');close(s)
   profile=json.loads((r/'data/balance-profile.json').read_text())
   for clas in (6,7):
    stage(f,clas=clas,bow=0,offhand=0);s=login(f);base=s.stats['armor'];close(s)
    for shield in (453,416):
     stage(f,clas=clas,bow=0,offhand=shield);s=login(f);item=profile['items'][str(shield)];a=base+item['armor']*(2 if clas==6 else 1)+int(item['constitution']*(.6 if clas==6 else .4))
     # Formula floors can differ by one after adding shield CON.
     check(abs(s.stats['armor']-a)<=1,'Real shield grants double armour only to Warrior');close(s)
   # PK uses the same extended range for a live player victim.
   stage(op,clas=6,bow=0,offhand=0,x=11,map_id=22);target=login(op)
   stage(f,bow=457,offhand=425,x=2,map_id=22);s=login(f);s.events.clear();s.strike(3);pump(s,.3);pump(target,.1)
   check(any(e.get('kind')=='player_damage' for e in s.events+target.events),'Extended bow range reaches a player in PK');close(s);close(target)
   report=dict(result='passed',checks=len(checks),range_boundaries=True,elemental_arrows_and_walls=True,forged_cadence_limited=True,observed_hits_in_1_55_seconds=observed,scav_distance_cadence=distances,native_class_walking=walking,standing_sitting_pk_recovery=True,warrior_shield_double=True,pk_range=True,isolated_database=True,production_database_opened=False)
   (out/'combat-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
  finally:
   for s in sessions:s.close()
   proc.terminate();proc.wait(timeout=15);log.close()
if __name__=='__main__':main()
