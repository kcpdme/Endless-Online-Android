"""Raw native capacity/trade boundaries, spell multipliers and separate HP/TP clocks."""
from pathlib import Path
from contextlib import closing
import json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time,statistics
from eo_session import Session,number,EOError
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put
from configure_sky_wonder import parse,grid
ROOT=Path(__file__).resolve().parents[1]

def main():
 out=ROOT/'work/class-balance-v10';checks=[];sessions=[];observed={}
 def check(ok,why):
  if not ok:raise AssertionError(why)
  checks.append(why)
 with tempfile.TemporaryDirectory(prefix='aster-capacity-') as tmp:
  r=Path(tmp)/'runtime';shutil.copytree(out/'runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
  p=r/'config.local.ini';p.write_text(p.read_text()+'\nPort = 18948\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nCriticalFirstHit = no\n')
  p=r/'data/formulas.ini';p.write_text(p.read_text()+'\nhit_rate = 1\nclass.2.damage = 0\n')
  p=r/'data/pub/dtn001.enf';raw=p.read_bytes();rows=records(raw,b'ENF',39)
  for off,val,size in [(11,500000,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[0]['fields'],off,val,size)
  p.write_bytes(encode_pub(raw,rows))
  p=r/'data/pub/dat001.eif';raw=p.read_bytes();rows=records(raw,b'EIF',58);put(rows[492]['fields'],9,10,2);put(rows[492]['fields'],11,10,2);p.write_bytes(encode_pub(raw,rows))
  p=r/'data/maps/00021.emf';raw=p.read_bytes();prefix,g,signs=parse(raw);prefix=bytearray(prefix);prefix[43:45]=number(0,1)*2
  for x in range(1,12):g['specs'].pop((x,8),None)
  g['specs'][4,7]=number(16,1) # Native BankVault tile beside the overweight fixture.
  for map_id,pk in ((21,False),(22,True)):
   pre=bytearray(prefix);pre[31:32]=number(3 if pk else 0,1);(r/f'data/maps/{map_id:05d}.emf').write_bytes(pre+b''.join(grid(c) for c in g.values())+number(0,1))
  log=(out/'capacity-native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
  def pump(s,seconds):
   end=time.monotonic()+seconds
   while time.monotonic()<end:
    s.poll_actions()
    if select.select([s.sock],[],[],.015)[0]:s.pump()
  def until(s,predicate,seconds=8):
   end=time.monotonic()+seconds
   while time.monotonic()<end:
    if predicate():return
    pump(s,.03)
   raise AssertionError('Timed out waiting for native event')
  def login(f):
   s=LiveSession('127.0.0.1',18948);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot();return s
  def close(s):s.close();sessions.remove(s)
  def stage(f,clas=6,count=0,strength=0,admin=0,x=4,map_id=21,weapon=0,hp=30000,spells=''):
   time.sleep(.65);d=[0]*15;d[8]=weapon
   with closing(sqlite3.connect(r/'database.sdb')) as db,db:
    db.execute('UPDATE characters SET sitting=0,direction=3,class=?,level=45,map=?,x=?,y=8,hp=?,tp=0,admin=?,"str"=?,"int"=0,wis=0,agi=0,"con"=10,cha=0,paperdoll=?,inventory=?,bank="",spells=? WHERE name=? AND account=?',(clas,map_id,x,hp,admin,strength,','.join(map(str,d)),f'1,1000;21,{count};' if count else '1,1000;',spells,f['name'],f['username']))
  def fixture():
   f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18948)
   try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
   finally:s.close()
   return f
  def raw_walk(s):
   s.timestamp+=100;s.send(6,8,number(1,1)+number(s.timestamp,3)+number(s.state['self']['x']-1,1)+number(8,1));pump(s,.6)
  def trade(a,b):
   a.refresh();b.refresh();a.trade_action('request',b.player_id);until(b,lambda:bool(b.trade_request));b.trade_action('accept',a.player_id);until(a,lambda:bool(a.trade))
  try:
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18948),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.6);f=fixture();other=fixture();time.sleep(.7)
   for count,weapon,admin,expected in ((70,0,0,70),(70,21,0,71),(71,0,0,71),(71,0,4,71),(251,0,0,251),(1000000000,0,0,1000000000)):
    capacity=250 if count>=251 else 70;stage(f,count=count,weapon=weapon,admin=admin,strength=180 if capacity==250 else 0);s=login(f)
    snap=s.snapshot()['player']['stats'];check(snap['weight']==expected and snap['max_weight']==capacity,'Exact unsaturated carried weight includes equipped items, large stacks and admins')
    x=s.state['self']['x'];acks=s.metrics['walk_acks'];raw_walk(s)
    if expected>capacity:check(s.metrics['walk_acks']==acks and s.state['self']['x']==x,'Raw native walk refused when actual weight exceeds capacity')
    else:check(s.metrics['walk_acks']==acks+1,'Exactly-at-capacity walking is legal')
    close(s)
   # Overweight players can recover by dropping or using a nearby locker.
   stage(f,count=71);s=login(f)
   try:s.move(1,1,21,3,8)
   except EOError as e:check('Overweight' in str(e),'Adapter refuses overweight movement before prediction')
   else:raise AssertionError('Adapter allowed overweight movement')
   s.drop(21,1);check(s.snapshot()['player']['stats']['weight']==70,'Dropping weight works while overweight');s.move(1,1,21,3,8);until(s,lambda:s.position_seq==1);check(s.state['self']['x']==3,'Walking resumes immediately below or at the limit');close(s)
   stage(f,count=71);s=login(f);s.locker_open(4,7);s.locker_change(False,21,2);check(s.item_amount(21)==69 and s.snapshot()['player']['stats']['weight']==69,'Locker deposit remains available while overweight');close(s)
   for acount,bcount in ((71,1),(1,71)):
    stage(f,count=acount);stage(other,count=bcount,x=5);a=login(f);b=login(other);a.refresh();b.refresh()
    a.send(32,1,number(0,1)+number(b.player_id,2));pump(a,.7);pump(b,.2)
    check(not b.trade_request and not a.trade and not b.trade,'Raw native invite refused if either party is overweight');close(a);close(b)
   # Capacity changes between invitation and acceptance are checked again.
   stage(f,count=1);stage(other,count=70,x=5,admin=4);a=login(f);b=login(other);a.refresh();b.refresh();a.trade_action('request',b.player_id);until(b,lambda:bool(b.trade_request))
   b.chat_send('local','$sitem 21 1');until(b,lambda:b.item_amount(21)==71);b.send(32,2,number(1,1)+number(a.player_id,2));pump(b,.5);pump(a,.2)
   check(not a.trade and not b.trade,'Raw accept rechecks weight after an invitation');close(a);close(b)
   # Final net weight, not just current weight, must fit on both sides.
   stage(f,count=69);stage(other,count=5,x=5);a=login(f);b=login(other);trade(a,b)
   a.trade_action('add',item_id=1,amount=1);b.trade_action('add',item_id=21,amount=2);pump(a,.2)
   a.send(32,5,number(1,1));pump(a,.5);pump(b,.2)
   check(a.item_amount(21)==69 and b.item_amount(21)==5 and not a.trade['agreed'] and not b.trade['agreed'],'Raw confirmation rejects projected overweight atomically and resets both agreements')
   b.trade_action('remove',item_id=21);b.trade_action('add',item_id=21,amount=1);pump(a,.2);a.trade_action('agree');pump(b,.2);b.trade_action('agree');until(a,lambda:not a.trade)
   check(a.item_amount(21)==70 and b.item_amount(21)==4,'An exactly-at-capacity final trade succeeds without deleting or duplicating items');close(a);close(b)
   # One fixed-attack Mage checks final spell power against native HP damage.
   stage(f,admin=4,x=11);s=login(f);s.chat_send('local','$snpc 1 1 7');until(s,lambda:any(n['id']==1 and n['x']==11 for n in s.state['npcs']));close(s)
   stage(f,clas=3,weapon=493,x=10,spells='4,0;14,0;');s=login(f)
   # Give mana using a temporary fixture-only database value before reconnecting.
   close(s);time.sleep(.6)
   with closing(sqlite3.connect(r/'database.sdb')) as db,db:db.execute('UPDATE characters SET tp=5000 WHERE name=?',(f['name'],))
   s=login(f);target=next(n for n in s.state['npcs'] if n['id']==1)
   check(s.stats['min_damage']==10 and s.stats['max_damage']==10,'Native Mage multiplier fixture has exact equipped attack ten')
   for ident,low,high in ((4,48,54),(14,27,33)):
    s.events.clear();s.cast_spell(ident,'area' if ident==14 else 'npc',0 if ident==14 else target['index']);until(s,lambda:any(e.get('kind')=='npc_damage' and e.get('spell_id')==ident for e in s.events))
    hits=[e for e in s.events if e.get('kind')=='npc_damage' and e.get('spell_id')==ident];damage=hits[-1]['damage'];observed[str(ident)]=damage;check(low<=damage<=high,'Native Mage single hit x1.5 / normal area mastery matches published bounds');pump(s,.7)
   close(s)
   clocks={}
   for clas,pk,sitting in ((2,False,False),(2,False,True),(8,True,False),(4,False,False)):
    stage(f,clas=clas,map_id=22 if pk else 21,hp=1);s=login(f)
    if sitting:s.sit()
    before=s.stats['hp'];last_hp=before;last_tp=s.stats['tp'];hp_ticks=[];tp_ticks=[];start=time.monotonic()
    while time.monotonic()-start<4.3:
     pump(s,.015);now=time.monotonic()-start
     if s.stats['hp']>last_hp:hp_ticks.append((now,s.stats['hp']-last_hp));last_hp=s.stats['hp']
     if s.stats['tp']>last_tp:tp_ticks.append((now,s.stats['tp']-last_tp));last_tp=s.stats['tp']
    if clas in (2,8):
     expected=max(1,int(s.stats['max_hp']*.02*(2 if sitting else 1)*(.5 if pk else 1)))
     check(len(hp_ticks)>=4 and all(delta==expected for _,delta in hp_ticks),'Priest/High Priest HP recovery is the exact standing/sitting/PK amount')
     mean=statistics.mean(b[0]-a[0] for a,b in zip(hp_ticks,hp_ticks[1:]));check(.9<mean<1.1,'Priest HP clock really ticks every second')
     check(1<=len(tp_ticks)<=3 and all(b[0]-a[0]>1.8 for a,b in zip(tp_ticks,tp_ticks[1:])),'Fast Priest HP renewal does not double the two-second TP clock')
     clocks[f'{clas}-{pk}-{sitting}']=dict(hp_per_tick=expected,mean_hp_seconds=round(mean,3),hp_ticks=len(hp_ticks),tp_ticks=len(tp_ticks))
    else:check(not hp_ticks,'Rogue cannot inherit Priest automatic HP recovery')
    close(s)
   report=dict(result='passed',checks=len(checks),raw_walk_and_trade_enforced=True,equal_capacity_allowed=True,large_stacks_and_equipment_counted=True,admin_uses_real_capacity=True,drop_and_locker_escape=True,trade_net_capacity_atomic=True,spell_samples=observed,priest_clocks=clocks,isolated_database=True,production_database_opened=False)
   (out/'capacity-native-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
  finally:
   for s in sessions:s.close()
   proc.terminate();proc.wait(timeout=15);log.close()
if __name__=='__main__':main()
