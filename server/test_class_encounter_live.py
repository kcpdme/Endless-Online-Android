"""Measure real native combat against the installed King Wurm-stat fixture.

Four scenarios: front, positioned rear/close range, retaliation, and potion support.
Regular level45 full kits; no forced hit-rate or damage overrides.
The passive arena copy retaliates once attacked; natural respawns are disabled.
"""
from pathlib import Path
from contextlib import closing
import argparse,json,os,sys,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time
from eo_session import Session,number,EOError
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put
from configure_sky_wonder import parse,grid
from balance_model import allocation
from combat_progression import TP_RECOVERY
ROOT=Path(__file__).resolve().parents[1]
SLOTS={'boots':0,'accessory':1,'gloves':2,'belt':3,'armor':4,'necklace':5,'head':6,'offhand':7,'weapon':8,'ring1':9,'ring2':10,'armlet1':11,'armlet2':12,'bracer1':13,'bracer2':14}

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--work-dir',type=Path,default=ROOT/'work/class-balance-v10');parser.add_argument('--extra',action='store_true');parser.add_argument('--modes',nargs='+',choices=('stationary','retaliating','positioned','supplied'));args=parser.parse_args()
 out=args.work_dir.resolve();profile=json.loads((out/'runtime/data/balance-profile.json').read_text());audit=json.loads((out/'full-equipment-audit.json').read_text());results=[];sessions=[];extra=args.extra
 enemy=profile['npcs'].get('174',dict(hp=5200,min_damage=43,max_damage=62,accuracy=72,evade=32,armor=22))
 modes=args.modes or (('positioned','supplied') if extra else ('stationary','retaliating','positioned','supplied'))
 if extra:
  previous=json.loads((out/'encounter-report.json').read_text());assert previous['profile']==profile['version'] and previous['encounter']['hp']==enemy['hp']
  results=[row for row in previous['results'] if row['mode'] not in modes]
 with tempfile.TemporaryDirectory(prefix='aster-encounter-') as tmp:
  r=Path(tmp)/'runtime';shutil.copytree(out/'runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
  p=r/'config.local.ini';p.write_text(p.read_text()+'\nPort = 18950\nIPReconnectLimit = 0\nNPCRecoverSpeed = 1h\n')
  p=r/'data/pub/dtn001.enf';raw=p.read_bytes();rows=records(raw,b'ENF',39);rows[0]['fields']=bytearray(rows[173]['fields']);put(rows[0]['fields'],7,1,2);put(rows[0]['fields'],36,0,3);p.write_bytes(encode_pub(raw,rows))
  raw=(r/'data/maps/00021.emf').read_bytes();prefix,g,signs=parse(raw);prefix=bytearray(prefix);prefix[43:45]=number(0,1)*2
  # Remove natural spawn/item/chest declarations from arena header, keeping art.
  prefix=prefix[:46]+number(0,1)*3
  for x in range(1,14):
   for y in range(1,13):g['specs'].pop((x,y),None);g['warps'].pop((x,y),None)
  for mid in range(21,45):(r/f'data/maps/{mid:05d}.emf').write_bytes(prefix+b''.join(grid(c) for c in g.values())+number(0,1))
  log=(out/'encounter-native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
  def pump(s,seconds=.02):
   end=time.monotonic()+seconds
   while time.monotonic()<end:
    s.poll_actions()
    if select.select([s.sock],[],[],.005)[0]:s.pump()
  def fixture():
   f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18950)
   try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
   finally:s.close()
   return f
  def stage(f,clas,mid,admin=0,x=10):
   time.sleep(.65);a=allocation(clas,45);row=next(v for v in audit['builds'] if v['level']==45 and v['class_id']==clas and v['build']=='damage');d=[0]*15
   for key,ident in row['equipment'].items():d[SLOTS[key]]=ident
   spells=''.join(f'{sp["id"]},0;' for sp in profile['spells'].values() if clas in sp.get('allowed_classes',[]) and sp['level_requirement']<=45)
   with closing(sqlite3.connect(r/'database.sdb')) as db,db:
    db.execute('UPDATE characters SET class=?,level=45,exp=12128625,gender=1,map=?,x=?,y=8,hp=30000,tp=30000,admin=?,"str"=?,"int"=?,wis=?,agi=?,"con"=?,cha=?,paperdoll=?,inventory="1,10000;375,5;",spells=? WHERE name=?',(clas,mid,x,admin,*(a[k] for k in ('strength','intelligence','wisdom','agility','constitution','charisma')),','.join(map(str,d)),spells,f['name']))
   return row
  def login(f):
   s=LiveSession('127.0.0.1',18950);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot();return s
  def close(s):s.close();sessions.remove(s)
  try:
   for _ in range(100):
    try:
     with socket.create_connection(('127.0.0.1',18950),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.7);op=fixture()
   for mode in modes:
    # A previous fight may legitimately exhaust TP and start persistent pet
    # recovery. Use fresh characters so each scenario starts equally ready.
    fixtures={c:fixture() for c in range(2,8)};time.sleep(.7)
    actors=[]
    for clas,f in fixtures.items():
     mid=21+clas-2+{'stationary':0,'retaliating':6,'positioned':12,'supplied':18}[mode]
     stage(op,6,mid,4,11);admin=login(op);admin.chat_send('local',f"$snpc 1 1 {('7 3' if mode=='positioned' else '7 0') if mode in ('stationary','positioned') else 0}");pump(admin,.35);close(admin)
     kit=stage(f,clas,mid,x=9 if mode=='positioned' and clas==5 else 10 if clas not in (3,5) else 7);s=login(f)
     assert s.stats['admin']==0 and all(abs(s.stats[key]-kit[key]) <= (1 if key=='accuracy' else 0) for key in ('max_hp','max_tp','min_damage','max_damage','accuracy','evade','armor')),(clas,s.stats,kit)
     if clas==7:
      eligible=[(int(i),v) for i,v in profile['companions'].items() if profile['spells'][i]['level_requirement']<=45];ident=max(eligible,key=lambda a:a[1]['power'])[0];s.cast_spell(ident,'self');pump(s,1.6);assert s.companion
     pet_tp=max(0,s.stats['max_tp']*profile['companions'][str(ident)]['upkeep_rate']/2-max(1,int(s.stats['max_tp']*TP_RECOVERY[7]))/2) if clas==7 else 0
     s.events.clear();actors.append(dict(s=s,clas=clas,kit=kit,start=None,next=0,events=[],moves=0,casts=0,done=False,min_hp=s.stats['hp'],initial_tp=s.stats['tp'],initial_hp=s.stats['hp'],sequence=0,potions=0,potion_at=0,pet_tp_per_second=pet_tp,native_stats={key:s.stats[key] for key in ('min_damage','max_damage','accuracy','evade','armor','max_hp','max_tp')}))
    started=time.monotonic()
    while not all(a['done'] for a in actors) and time.monotonic()-started<100:
     for a in actors:
      if a['done']:continue
      s=a['s'];now=time.monotonic();pump(s,.004);a['events'].extend(s.events);s.events.clear();a['min_hp']=min(a['min_hp'],s.stats['hp'])
      killed=any(e.get('kind')=='npc_killed' and e.get('npc_index')==a.get('target') for e in a['events'])
      if killed or s.stats.get('dead') or s.stats['hp']<=0:
       a.update(done=True,killed=killed,elapsed=round(now-(a['start'] or started),3));continue
      target=next((n for n in s.state['npcs'] if n['id']==1),None)
      if not target:continue
      a['target']=target['index']
      if a['start'] is None:a['start']=now
      if mode=='supplied' and a['potions']<5 and s.stats['hp']<s.stats['max_hp']*.55 and now-a['potion_at']>3:
       s.use_item(375,asynchronous=True);a['potions']+=1;a['potion_at']=now
      if s.casting or now<a['next']:continue
      me=s.state['self'];dx=target['x']-me['x'];dy=target['y']-me['y'];dist=abs(dx)+abs(dy);direction=3 if dx>0 else 1 if dx<0 else 0 if dy>0 else 2
      clas=a['clas'];spell=profile['spells'][str(a['kit']['spell_id'])] if a['kit']['spell_id'] else None
      # Priest heals consume the same real chant/recovery time as offense.
      if clas==2 and s.stats['hp']<s.stats['max_hp']*.6:
       heals=[h for h in profile['spells'].values() if h['type']==0 and clas in h.get('allowed_classes',[]) and h['level_requirement']<=45 and h['target']==1 and h['tp']<=s.stats['tp']]
       if heals:
        heal=max(heals,key=lambda h:h['hp']);s.cast_spell(heal['id'],'self');a['casts']+=1;a['next']=now+heal['cast_time']*.48+.55;continue
      # The prepared/supplied scenario budgets pet upkeep for a 60-second fight.
      # Without this, a naive attack-spell loop dismisses its own damage source.
      reserve=max(0,60-(now-a['start']))*a['pet_tp_per_second'] if mode=='supplied' and getattr(s,'companion',None) else 0
      if spell and a['kit']['spell_dps']>a['kit']['basic_dps']*(2/1.5 if clas==5 and dist<=2 else 1) and s.stats['tp']>=spell['tp']+reserve and dist<=spell.get('range',11) and (not spell.get('weapon_range') or dist<= (1 if clas in (4,6) else 9)):
       try:s.cast_spell(spell['id'],'npc',target['index']);a['casts']+=1;a['next']=now+spell['cast_time']*.48+.55;continue
       except EOError:pass
      reach=9 if clas==5 else 1
      if dist<=reach and (not dx or not dy):
       s.strike(direction);a['next']=now+(.52/(2 if dist<=2 else 1.5) if clas==5 else .52)
      elif not s.pending_moves:
       sx=1 if dx>0 else -1 if dx<0 else 0;sy=0 if sx else 1 if dy>0 else -1
       direction=3 if sx>0 else 1 if sx<0 else 0 if sy>0 else 2;a['sequence']+=1
       try:s.move(direction,a['sequence'],s.state['map_id'],me['x']+sx,me['y']+sy);a['moves']+=1
       except EOError:pass
       a['next']=now+(.22 if clas==4 else .43)
    for a in actors:
     s=a.pop('s');events=a.pop('events');kit=a.pop('kit');a.pop('next');a.pop('start');pet=sum(e.get('damage',0) for e in events if e.get('kind')=='companion_attack');total=sum(e.get('damage',0) for e in events if e.get('kind') in ('npc_damage','npc_killed') and e.get('npc_index')==a.get('target'));incoming=sum(e.get('damage',0) for e in events if e.get('kind') in ('npc_attack','player_damage') and e.get('player_id')==s.player_id)
     a.update(mode=mode,role=kit['role'],level=45,equipment=kit['equipment'],hp=s.stats['hp'],max_hp=s.stats['max_hp'],tp=s.stats['tp'],max_tp=s.stats['max_tp'],pet_damage=pet,owner_damage=total-pet,total_damage=total,incoming_damage=incoming,incoming_hits=sum(e.get('kind') in ('npc_attack','player_damage') and e.get('player_id')==s.player_id for e in events),armor=kit['armor'],spell_healing=sum(e.get('hp_gain',0) for e in events if e.get('kind')=='spell_heal'),hits=sum(e.get('kind') in ('npc_damage','npc_killed') for e in events),observed_dps=round(total/a.get('elapsed',100),2),killed=a.get('killed',False),elapsed=a.get('elapsed',100),spell_id=kit['spell_id']);assert not a['killed'] or total==enemy['hp'],(a['role'],mode,total)
     assert (incoming>0)==(mode in ('retaliating','supplied')),(a['role'],mode,incoming)
     results.append(a);close(s)
    print(json.dumps([dict(role=a['role'],mode=mode,killed=a['killed'],seconds=a['elapsed'],dps=a['observed_dps'],hp=a['hp'],pet=a['pet_damage']) for a in results if a['mode']==mode]),flush=True)
   report=dict(result='measured',profile=profile['version'],encounter={k:enemy[k] for k in ('hp','min_damage','max_damage','accuracy','evade','armor')},results=results,scope='Real native packet combat, regular level45 damage-optimized legal full kits, untrained spells, full starting HP/TP, default crit/hit formulas. No stat cheats. Supplied scenario gives each player the same five Big Health Potions; potion usage is recorded. Only the supplied Summoner reserves net pet upkeep for a 60-second fight; other scenarios spend TP on offense until exhausted. Stationary NPC cannot attack; retaliating copy uses normal .9s NPC actions and no natural respawn. Each scenario uses a fresh separate arena. Automatic controller does not kite or circle behind a live opponent; Rogue rear ceiling and movement are separately verified, not assumed always available. Priest heals share action time with damage. Pet call precedes fight; starting TP records its cost; normal upkeep is active. This is a small randomized sample, not proof of equal skill or class win rate.',isolated_database=True,production_database_opened=False)
   (out/'encounter-report.json').write_text(json.dumps(report,indent=2)+'\n')
  finally:
   for s in sessions:s.close()
   proc.terminate();proc.wait(timeout=15);log.close()
if __name__=='__main__':main()
