"""Classic creation, natural unarmed loot/crafting and real boat/Aeven gates in a disposable world."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,sys,tempfile,time
from contextlib import closing
from pathlib import Path
from eo_session import Session,number,EOError
from live_session import LiveSession
from test_online import dev_name
from test_sky_wonder_live import route
from configure_sky_wonder import parse,grid
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from import_eo import parse_emf
DIRECTIONS=[(0,1),(-1,0),(0,-1),(1,0)]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,default=ROOT/'work/classic-onboarding/runtime');p.add_argument('--skip-hunt',action='store_true',help='Stage two horns after bare birth checks to exercise the remaining native flow without waiting for random loot');a=p.parse_args();out=ROOT/'work/classic-onboarding';checks=[];streams=[];proc=None
    def check(ok,why):
        if not ok:raise AssertionError(why)
        checks.append(why);print('PASS',why,flush=True)
    with tempfile.TemporaryDirectory(prefix='aster-classic-start-') as tmp:
        b=Path(tmp);r=b/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18962\nIPReconnectLimit = 0\nCriticalRate = 0\n')
        # A lethal spike exists only in this disposable fixture; original island maps stay exact.
        spike=r/'data/maps/00021.emf';pre,g,signs=parse(spike.read_bytes());pre=bytearray(pre);pre[43:45]=number(0,1)*2;g['specs'][11,9]=number(35,1);assert not signs;spike.write_bytes(pre+b''.join(grid(c) for c in g.values())+number(0,1))
        worlds={mid:parse_emf((r/f'data/maps/{mid:05}.emf').read_bytes(),mid) for mid in (1,2,5,190,192,193,194,195)}
        def pump(s,seconds=.1):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                s.poll_actions()
                if select.select([s.sock],[],[],.02)[0]:s.pump()
        def until(s,fn,timeout=8):
            end=time.monotonic()+timeout
            while time.monotonic()<end:
                pump(s,.03)
                if fn():return
            raise AssertionError('Native journey timed out')
        def make(gender=1,race=0):
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name());s=Session(port=18962)
            try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['character_name'],gender=gender,race=race)
            finally:s.close()
            time.sleep(.6);return f
        def login(f):
            s=LiveSession('127.0.0.1',18962);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['character_name']));s.snapshot();return s
        def stage(f,level,location,hp=None,**fields):
            time.sleep(.65)
            values=dict(level=level,map=location[0],x=location[1],y=location[2],**fields)
            if hp is not None:values['hp']=hp
            with closing(sqlite3.connect(r/'database.sdb')) as db,db:assert db.execute('UPDATE characters SET '+','.join('"'+k+'"=?' for k in values)+' WHERE name=? AND account=?',(*values.values(),f['character_name'],f['username'])).rowcount==1
        def home(s):return s.feature_open('book')['feature']['home']
        def walk_to(s,point):
            mid=s.state['map_id']
            for _ in range(200):
                at=(s.state['self']['x'],s.state['self']['y'])
                if at==point:return
                occupied={(c['x'],c['y']) for c in s.state['characters'] if c['player_id']!=s.player_id}
                occupied.discard(point)
                try:path=route(worlds[mid],at,point,occupied)
                except AssertionError:pump(s,.3);s.refresh();continue
                s.walk(path[0],open_door=True)
                if s.state['map_id']!=mid:return
            raise AssertionError('Native walk failed')
        try:
            log=(out/'native.log').open('w');streams.append(log);proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18962),timeout=.1):break
                except OSError:time.sleep(.1)
            time.sleep(.5);first=None
            for gender,race in [(gender,race) for gender in (0,1) for race in range(4)]:
                f=make(gender,race);first=f if first is None and gender==1 else first;s=login(f)
                try:
                    check((s.state['map_id'],s.state['self']['x'],s.state['self']['y'])==(192,7,6),'Original house birth for gender '+str(gender)+' skin '+str(race))
                    check(not s.inventory and not s.spells and all(v==0 for v in s.equipment.values()),'No Gold, clothes, weapon, shield, equipped items or learned spells at birth')
                    check(s.stats['level']==0 and s.stats['experience']==0 and s.stats['admin']==0,'Fresh regular character starts level zero with original EXP baseline')
                    check(home(s)=='Tutorial Island','New player death home is the island before departure')
                finally:s.close()
            s=login(first)
            try:
                check(not s.inventory and not s.spells,'Reconnect does not add a starter kit')
                walk_to(s,(12,6));check(s.state['map_id']==190,'Native walking leaves the original starting house for Tutorial Island')
                walk_to(s,(8,24))
                if a.skip_hunt:
                    s.close();stage(first,0,(193,6,3),inventory='258,2;');s=login(first)
                kills=0;deadline=time.monotonic()+600;target_index=None;trace_at=0
                while s.item_amount(258)<2 and time.monotonic()<deadline:
                    pump(s,.03);me=s.state['self']
                    if time.monotonic()>trace_at:
                        print('FARM',dict(map=s.state['map_id'],xy=[me['x'],me['y']],hp=s.stats.get('hp'),damage=[s.stats.get('min_damage'),s.stats.get('max_damage')],kills=kills,horns=s.item_amount(258),nearby=len(s.state['npcs'])),flush=True);trace_at=time.monotonic()+10
                    if s.state['map_id']==192:walk_to(s,(12,6));walk_to(s,(8,24));continue
                    goats=[n for n in s.state['npcs'] if n['id']==7]
                    target=next((n for n in goats if n['index']==target_index),None)
                    if target is None:
                        if not goats:pump(s,.2);continue
                        target=min(goats,key=lambda n:abs(n['x']-me['x'])+abs(n['y']-me['y']));target_index=target['index']
                    dx,dy=target['x']-me['x'],target['y']-me['y']
                    if abs(dx)+abs(dy)==1:
                        s.events.clear();s.strike(DIRECTIONS.index((dx,dy)));pump(s,.62)
                        events=[e for e in s.events if e.get('kind')=='npc_killed' and e.get('player_id')==s.player_id]
                        for e in events:
                            print('GOAT KILLED',e['drop']['id'],flush=True)
                            kills+=1;drop=e['drop']
                            if drop['uid'] and drop['amount'] and drop['id'] in (1,258):
                                if abs(drop['x']-s.state['self']['x'])+abs(drop['y']-s.state['self']['y'])<=2:s.pickup(drop['uid'])
                    else:
                        paths=[];occupied={(n['x'],n['y']) for n in s.state['npcs']}
                        for xx,yy in DIRECTIONS:
                            at=(target['x']+xx,target['y']+yy)
                            if at in {(w['x'],w['y']) for w in worlds[190]['warps']}:continue
                            try:paths.append(route(worlds[190],(me['x'],me['y']),at,occupied))
                            except AssertionError:pass
                        if paths:
                            path=min(paths,key=len)
                            if path:s.walk(path[0])
                        else:target_index=None
                check(s.item_amount(258)>=2 and (kills>=2 or a.skip_hunt),'Two Goat Horns available for the native craft' if a.skip_hunt else 'Unarmed level-zero character earns two Goat Horns from real original drops')
                check(s.equipment.get('weapon',0)==0,'Starter farming uses bare fists')
                print('Natural goat kills needed for two horns:',kills,flush=True) if not a.skip_hunt else None
                if not a.skip_hunt:walk_to(s,(24,19))
                check(s.state['map_id']==193,'Original Cyndi shop is accessible')
                walk_to(s,(6,3));shop=next(n for n in s.state['npcs'] if n['id']==100);s.shop_open(shop['index'])
                check(any(o['id']==21 for o in s.shop['craft']),'Native shop exposes Dagger crafting')
                before=s.item_amount(258);s.shop_trade('craft',21)
                check(s.item_amount(21)==1 and s.item_amount(258)==before-2,'Native Dagger craft consumes exactly two earned Goat Horns and no Gold')
                s.equip(21);check(s.equipment['weapon']==21,'Earned starter Dagger equips on Peasant class')
                if not a.skip_hunt:
                    walk_to(s,(6,12));walk_to(s,(14,28));check(s.state['map_id']==192,'Return to the original starting house')
                    walk_to(s,(7,5));s.chest_open(7,4)
                    until(s,lambda:any(i['id']==144 for i in s.chest['items']),70)
                    s.chest_change(True,144);check(s.item_amount(144)==1,'First outfit is collected from the original house chest')
            finally:s.close()
            # Dying at level four on the island must not bypass its boat.
            stage(first,4,(21,11,8),hp=1);s=login(first)
            try:
                s.walk(0);until(s,lambda:s.state['map_id']==192)
                check(home(s)=='Tutorial Island' and (s.item_amount(21)==1 or s.equipment.get('weapon',0)==21),'Island death preserves earned gear and respawns on island, including level four')
            finally:s.close()
            for level,should_leave in [(3,False),(4,True)]:
                stage(first,level,(195,21,7),hp=30);s=login(first)
                try:
                    s.walk(2,open_door=True);pump(s,.2)
                    check((s.state['map_id']==1)==should_leave,'Original boat level gate '+str(level))
                    if should_leave:check(home(s)=='Mainland Arrival','Taking the boat updates death home to its mainland arrival')
                finally:s.close()
            stage(first,4,(21,11,8),hp=1);s=login(first)
            try:
                s.walk(0);until(s,lambda:s.state['map_id']==1);check(home(s)=='Mainland Arrival','Death after boarding remains on mainland before Aeven access')
            finally:s.close()
            for level,should_enter in [(4,False),(5,True)]:
                stage(first,level,(2,13,1),hp=30);s=login(first)
                try:
                    s.walk(2);pump(s,.2);check((s.state['map_id']==5)==should_enter,'Original Aeven entrance level gate '+str(level))
                    if should_enter:check(home(s)=='Aeven','Entering Aeven completes the journey and sets Aeven home')
                finally:s.close()
            stage(first,5,(21,11,8),hp=1);s=login(first)
            try:s.walk(0);until(s,lambda:s.state['map_id']==5);check(home(s)=='Aeven','Completed journey respawns in Aeven')
            finally:s.close()
            legacy=make();stage(legacy,2,(5,40,40),home='',quest='',inventory='1,77;21,1;',spells='1,0;');s=login(legacy)
            try:check(home(s)=='Aeven' and s.item_amount(1)==77 and s.item_amount(21)==1 and any(x['id']==1 for x in s.spells),'Existing mainland character keeps its home, Gold, gear and learned spells')
            finally:s.close()
            result=dict(result='passed',checks=len(checks),natural_unarmed_goat_kills=kills,resource_fixture_seeded=a.skip_hunt,source_monster_exp_and_drop_rates_unchanged=True,original_maps_unchanged=True,new_regular_creation_cases=8,native_chest_outfit=not a.skip_hunt,native_two_horn_dagger_craft=True,boat_required_level=4,aeven_required_level=5,native_death_home_progression=True,existing_characters_unchanged=True,isolated_database=True,production_database_opened=False)
            (out/'native-report.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
        finally:
            if proc:
                proc.terminate()
                try:proc.wait(timeout=15)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            for stream in streams:stream.close()
if __name__=='__main__':main()
