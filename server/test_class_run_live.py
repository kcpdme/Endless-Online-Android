"""Native v15 acceptance in a disposable world: Run costs/cadence and spell scope."""
from pathlib import Path
from contextlib import closing
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time,math
from eo_session import Session,number
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put
from configure_sky_wonder import parse,grid
ROOT=Path(__file__).resolve().parents[1]


def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,default=ROOT/'work/class-run-v15/runtime');p.add_argument('--godot',type=Path);a=p.parse_args()
 checks=[];sessions=[];observed={}
 def check(ok,why):
  if not ok:raise AssertionError(why)
  checks.append(why)
 with tempfile.TemporaryDirectory(prefix='aster-run-v15-') as tmp:
  r=Path(tmp)/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
  p=r/'config.local.ini';p.write_text(p.read_text()+'\nPort = 18975\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nCriticalFirstHit = no\nBalance.2.tp_regen = 0\nBalance.3.tp_regen = 0\nBalance.7.tp_regen = 0\nPriestRegenRate = 0\nPriestSittingRegenRate = 0\n')
  p=r/'data/formulas.ini';p.write_text(p.read_text()+'\nhit_rate = 1\n')
  p=r/'data/pub/dtn001.enf';raw=p.read_bytes();rows=records(raw,b'ENF',39)
  for off,val,size in [(11,500000,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[0]['fields'],off,val,size)
  p.write_bytes(encode_pub(raw,rows))
  p=r/'data/maps/00021.emf';prefix,g,signs=parse(p.read_bytes());prefix=bytearray(prefix);prefix[43:45]=number(0,1)*2
  for x in range(2,14):
   for y in range(3,11):g['specs'].pop((x,y),None)
  p.write_bytes(prefix+b''.join(grid(c) for c in g.values())+number(0,1))
  out=ROOT/'work/class-run-v15';out.mkdir(exist_ok=True);log=(out/'rules-native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
  def pump(s,seconds):
   end=time.monotonic()+seconds
   while time.monotonic()<end:
    s.poll_actions()
    if select.select([s.sock],[],[],.015)[0]:s.pump()
  def until(s,pred,seconds=8):
   end=time.monotonic()+seconds
   while time.monotonic()<end:
    if pred():return
    pump(s,.03)
   raise AssertionError('Native event timed out')
  def fixture():
   f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18975)
   try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
   finally:s.close()
   return f
  def stage(f,clas=6,tp=30000,admin=0,x=4,spells='',shield=0):
   time.sleep(.65);d=[0]*15;d[7]=shield
   with closing(sqlite3.connect(r/'database.sdb')) as db,db:
    db.execute('UPDATE characters SET sitting=0,direction=3,class=?,level=50,map=21,x=?,y=8,hp=30000,tp=?,admin=?,"str"=30,"int"=20,wis=20,agi=30,"con"=100,cha=30,paperdoll=?,inventory="1,1000;",bank="",spells=? WHERE name=? AND account=?',(clas,x,tp,admin,','.join(map(str,d)),spells,f['name'],f['username']))
    db.execute('DELETE FROM aster_pet_state WHERE character_name=?',(f['name'],))
  def login(f):
   s=LiveSession('127.0.0.1',18975);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot();return s
  def close(s):s.close();sessions.remove(s)
  def raw_step(s,delta):
   before=s.metrics['walk_acks'];ts=s.timestamp+delta;x=s.state['self']['x']-1
   s.send(6,8,number(1,1)+number(ts,3)+number(x,1)+number(8,1));pump(s,.52)
   moved=s.metrics['walk_acks']>before
   if moved:s.timestamp=ts
   return moved
  try:
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18975),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.6);f=fixture();peer=fixture()
   for clas,speed,delta in ((6,1.25,28),(4,1.5,24)):
    stage(f,clas=clas,x=8);s=login(f)
    check(s.snapshot()['player']['combat']['move_seconds']==.42,'All classes including Rogue start at normal walking speed')
    check(not raw_step(s,35),'Native rejects sub-normal walk timestamp while Run is disabled')
    check(raw_step(s,36),'Native accepts normal walk timestamp')
    s.set_running(True)
    check(s.running_enabled and s.running_multiplier==speed,'Native Run acknowledges only class-specific x1.25/x1.5')
    check(raw_step(s,delta),'Native accepts accelerated movement only while Run is enabled')
    s.set_running(False);check(not raw_step(s,delta),'Disabling Run immediately restores native normal timestamp enforcement');close(s)
   stage(f);s=login(f);tp=s.stats['tp'];maximum=s.stats['max_tp'];start=time.monotonic();s.set_running(True);pump(s,1.4);s.set_running(True);pump(s,2.0);s.set_running(False);elapsed=time.monotonic()-start;spent=tp-s.stats['tp']
   check(abs(spent-math.floor(maximum*.015*elapsed))<=1,'Idle Run charges elapsed max-TP percentage; repeated enable does not reset its clock')
   before=s.stats['tp'];pump(s,2.2);check(s.stats['tp']==before,'Disabling Run stops its TP drain');observed['idle_run']={'max_tp':maximum,'elapsed':round(elapsed,3),'spent':spent};close(s)
   stage(f,tp=1);s=login(f);s.set_running(True);until(s,lambda:not s.running_enabled,3)
   check(s.stats['tp']==0 and s.snapshot()['player']['combat']['move_seconds']==.42,'TP exhaustion disables Run and removes its movement bonus');close(s)
   # Per-tier percentage upkeep retains fractional TP across two-second ticks.
   from pet_catalog import TIERS,EGGS
   for name,tier in TIERS.items():
    egg=next(e for e in EGGS.values() if e['tier']==name);spell=egg['spell_id']
    stage(f,clas=7,x=8,spells=f'{spell},0;35,0;');s=login(f);s.cast_spell(spell,'self');until(s,lambda:bool(getattr(s,'companion',None)));before=s.stats['tp'];last=before;costs=[];deadline=time.monotonic()+5
    while len(costs)<2 and time.monotonic()<deadline:
     pump(s,.025)
     if s.stats['tp']!=last:costs.append(last-s.stats['tp']);last=s.stats['tp']
    expected=math.floor(s.stats['max_tp']*tier['upkeep_rate']*2+1e-9)
    check(len(costs)==2 and sum(costs)==expected,'Native '+name+' pet charges exact maximum-TP percentage every two seconds with fractional carry')
    observed['pet_'+name]={'max_tp':s.stats['max_tp'],'rate':tier['upkeep_rate'],'two_ticks':costs}
    s.cast_spell(35,'self');until(s,lambda:not getattr(s,'companion',None));close(s)
   stage(f);s=login(f);bare=s.stats['armor'];check(bare==122,'Warrior doubles CON-derived defence: 102 CON gives 122 armour');close(s)
   stage(f,shield=52);s=login(f);profile=json.loads((r/'data/balance-profile.json').read_text());shield=profile['items']['52'];check(s.stats['armor']==int((102+shield['constitution'])*1.2)+2*shield['armor'],'Warrior shield retains exactly its existing doubled flat armour');close(s)
   # Spawn three harmless neighbours; all casts use a regular current-class character.
   stage(f,admin=4,x=10);s=login(f)
   s.chat_send('local','$snpc 1 3 7');pump(s,.8)
   check(len([n for n in s.state['npcs'] if n['id']==1])>=3,'Three durable neighbouring NPCs are available');close(s)
   for clas,ident in ((6,16),(6,46),(7,27),(5,37),(4,39),(3,49)):
    # Archer requires its real bow + arrows even for targeted skills.
    stage(f,clas=clas,x=10,spells=f'{ident},0;')
    if clas==5:
     with closing(sqlite3.connect(r/'database.sdb')) as db,db:
      d=[0]*15;d[7]=423;d[8]=457;db.execute('UPDATE characters SET paperdoll=? WHERE name=?',(','.join(map(str,d)),f['name']))
    s=login(f);target=next(n for n in s.state['npcs'] if n['id']==1);s.events.clear();s.cast_spell(ident,'area' if clas==3 else 'npc',0 if clas==3 else target['index']);until(s,lambda:any(e.get('kind')=='npc_damage' and e.get('spell_id')==ident for e in s.events));pump(s,.25)
    hits={e['npc_index'] for e in s.events if e.get('kind')=='npc_damage' and e.get('spell_id')==ident}
    check(len(hits)>=2 if clas==3 else len(hits)==1,'Magician retains area damage; converted class '+str(clas)+' skill '+str(ident)+' has correct native scope');observed[str(ident)]={'targets':len(hits)};close(s)
   # Former group heals target exactly one selected player.
   stage(peer,clas=6,x=9);patient=login(peer)
   for ident in (3,18):
    stage(f,clas=2,x=10,spells=f'{ident},0;');s=login(f);s.refresh();s.events.clear();s.cast_spell(ident,'player',patient.player_id);until(s,lambda:any(e.get('kind')=='spell_heal' and e.get('spell_id')==ident for e in s.events));check(not any(e.get('kind')=='spell_group' for e in s.events),'Priest former group heal '+str(ident)+' uses native selected-player packets');close(s)
   close(patient)
   if a.godot:
    stage(f,clas=7,x=8);fixture_path=Path(tmp)/'fixture.json';fixture_path.write_text(json.dumps(f));fixture_path.chmod(0o600);children=[]
    try:
     for name,command,port in [('gateway',['python3',str(ROOT/'server/gateway.py'),'--port','18976','--eo-port','18975'],18976),('websocket',['python3',str(ROOT/'server/ws_gateway.py'),'--port','18977','--tcp-port','18976','--deps-dir',str(ROOT/'work/server-build/python')],18977)]:
      stream=(out/(name+'.log')).open('w');child=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,env=dict(os.environ,ASTER_VALE_SHORTCUT_DB=str(Path(tmp)/'shortcuts.sdb')));children.append((child,stream))
      for _ in range(100):
       try:
        with socket.create_connection(('127.0.0.1',port),timeout=.1):break
       except OSError:time.sleep(.1)
     env=dict(os.environ,ASTER_VALE_RUN_FIXTURE=str(fixture_path),XDG_DATA_HOME=str(Path(tmp)/'data'),XDG_CONFIG_HOME=str(Path(tmp)/'config'))
     result=subprocess.run([str(a.godot.resolve()),'--headless','--path',str(ROOT/'client'),'--audio-driver','Dummy','--script','res://tests/class_run_live.gd'],env=env,capture_output=True,text=True,timeout=90)
     (out/'client-live.log').write_text(result.stdout+result.stderr);check(result.returncode==0 and 'failed=false' in result.stdout and 'SCRIPT ERROR' not in result.stderr,'Godot to WebSocket to native Run and idle TP flow passes')
    finally:
     for child,stream in reversed(children):child.terminate();child.wait(timeout=15);stream.close()
   report={'result':'passed','checks':len(checks),'profile':15,'observed':observed,'isolated_database':True,'production_database_opened':False,'assertions':checks};(out/'native-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
  finally:
   for s in sessions:s.close()
   proc.terminate();proc.wait(timeout=15);log.close()
if __name__=='__main__':main()
