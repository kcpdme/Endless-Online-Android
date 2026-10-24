#!/usr/bin/env python3
"""Isolated real Godot→WS→gateway→etheos gameplay fixtures."""
import argparse,json,os,shutil,subprocess,tempfile,socket,time,re,sqlite3,select,sys
from pathlib import Path
from run import state_path
from configure_inns import configure
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--screenshots',type=Path);p.add_argument('--skip-native-probe',action='store_true');p.add_argument('--scenario',choices=['inn','chest','admin','features','stones'],default='inn');a=p.parse_args()
    base_state=state_path();children=[];streams=[]
    with tempfile.TemporaryDirectory(prefix='aster-inn-citizenship-') as tmp:
        base=Path(tmp);runtime=base/'runtime'
        shutil.copytree(base_state/'runtime',runtime,ignore=shutil.ignore_patterns('database.sdb*','*.log','world.bak*','etheos-v*'))
        shutil.copy2(base_state/'build/etheos',runtime/'etheos')
        config=runtime/'config.local.ini';config.write_text(re.sub(r'^Port\s*=.*$','Port = 18886',config.read_text(),flags=re.M));configure(runtime)
        if a.scenario=='features':
            from configure_feature_content import configure as configure_features
            configure_features(runtime)
            config.write_text(config.read_text()+'\nDrainTime = 1s\nNoInteractDefault = 0\n')
        os.environ['ASTER_VALE_RUNTIME']=str(runtime)
        def start(name,command,port,cwd=ROOT):
            log=(base/(name+'.log')).open('w');streams.append(log)
            proc=subprocess.Popen(list(map(str,command)),cwd=cwd,env=dict(os.environ,ASTER_VALE_SHORTCUT_DB=str(base/'shortcuts.sqlite3')),stdout=log,stderr=subprocess.STDOUT);children.append(proc)
            for _ in range(100):
                if proc.poll() is not None:raise RuntimeError(name+' failed to start')
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
                except OSError:time.sleep(.1)
            else:raise RuntimeError(name+' listener unavailable')
            time.sleep(.5)
        def login(f):
            from live_session import LiveSession
            s=LiveSession("127.0.0.1",18886);rows=s.login(f['username'],f['password'])['characters'];s.enter(next(row['id'] for row in rows if row['name']==f['character_name']));s.snapshot();return s
        try:
            start('native',[runtime/'etheos'],18886,runtime)
            start('gateway',[sys.executable,ROOT/'server/gateway.py','--port',18887,'--eo-port',18886],18887)
            start('websocket',[sys.executable,ROOT/'server/ws_gateway.py','--port',18888,'--tcp-port',18887,'--deps-dir',base_state/'python'],18888)
            from eo_session import Session
            from test_online import dev_name
            import secrets
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name())
            s=Session(port=18886);s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['character_name']);s.close();time.sleep(.6)
            catalog=json.loads((ROOT/'client/content/catalog.json').read_text());rows={}
            for line in (runtime/'data/aster-vale-home.ini').read_text().splitlines():
                k,sep,v=line.partition('=')
                if sep and not k.lstrip().startswith('#'):rows[k.strip()]=v.strip()
            inns=[]
            for ident,home in [(150,'aeven'),(156,'estaq'),(159,'anundo'),(161,'halowdale'),(160,'centaur')]:
                for path in sorted((ROOT/'client/content/maps').glob('*.json')):
                    world=json.loads(path.read_text());npc=next((n for n in world.get('npcs',[]) if n['id']==ident),None)
                    if not npc:continue
                    blocked=set(map(tuple,world['server_blocked']));warps={(w['x'],w['y']) for w in world['warps']}
                    points=[(x,y) for y in range(max(0,npc['y']-4),min(world['height'],npc['y']+5)) for x in range(max(0,npc['x']-4),min(world['width'],npc['x']+5)) if 0<abs(x-npc['x'])+abs(y-npc['y'])<=4 and (x,y) not in blocked|warps]
                    x,y=min(points,key=lambda q:abs(q[0]-npc['x'])+abs(q[1]-npc['y']))
                    inns.append(dict(npc_id=ident,map_id=world['id'],x=x,y=y,home=home,name=rows[home+'.name'],answers=[rows[home+'.answer'+str(i)] for i in range(1,4)]));break
            with sqlite3.connect(runtime/'database.sdb') as db:
                mid,x,y=(7,12,15) if a.scenario=='stones' else (53,6,24) if a.scenario=='chest' else (70,inns[0]['x'],inns[0]['y'])
                db.execute('UPDATE characters SET admin=4,map=?,x=?,y=?,direction=2,hp=1,tp=0,inventory=? WHERE name=? AND account=?',(mid,x,y,'1,50000;',f['character_name'],f['username']))
                if a.scenario=='chest':db.execute('UPDATE characters SET level=120,con=1000,hp=30000 WHERE name=?',(f['character_name'],))
            regular=None
            if a.scenario in ('admin','features','stones'):
                regular=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name())
                s=Session(port=18886);s.register(regular['username'],regular['password']);s.login(regular['username'],regular['password']);s.create_character(regular['character_name']);s.close();time.sleep(.6)
                with sqlite3.connect(runtime/'database.sdb') as db:
                    regular_start=(7,11,15) if a.scenario=='stones' else (5,40,40)
                    db.execute('UPDATE characters SET admin=0,map=?,x=?,y=? WHERE name=? AND account=?',(*regular_start,regular['character_name'],regular['username']))
                    db.execute('UPDATE characters SET level=120,con=1000,hp=30000 WHERE name=?',(f['character_name'],))
            services=[]
            if a.scenario=='features':
                for mid,ident,kind in [(157,115,'law'),(15,114,'priest'),(72,192,'quest'),(281,305,'quest'),(34,303,'quest')]:
                    sys.path.insert(0,str(ROOT/'tools'));from import_eo import parse_emf
                    world=parse_emf((runtime/f'data/maps/{mid:05d}.emf').read_bytes(),mid);npc=next(n for n in world['npcs'] if n['id']==ident);services.append(dict(kind=kind,map_id=mid,npc_id=ident,x=npc['x'],y=npc['y']))
            if a.scenario=='features' and not a.skip_native_probe:
                from feature_native_probe import run as native_probe
                report=native_probe(runtime)
                (ROOT/'work/features-native-report.json').write_text(json.dumps(report,indent=2)+'\n')
            fixture=base/'fixture.json';fixture.write_text(json.dumps(dict(account=f,regular=regular,inns=inns,services=services)));fixture.chmod(0o600)
            env=dict(os.environ,XDG_DATA_HOME=str(base/'godot-data'),XDG_CONFIG_HOME=str(base/'godot-config'),ASTER_VALE_INN_FIXTURE=str(fixture),ASTER_VALE_TEST_HOST='ws://127.0.0.1:18888/ws',ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
            display=['--headless']
            if a.screenshots:
                a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=[]
            script={'inn':'res://tests/inn_citizenship_live.gd','chest':'res://tests/chest_walk_live.gd','admin':'res://tests/admin_live.gd','features':'res://tests/features_live.gd','stones':'res://tests/stepping_stones_live.gd'}[a.scenario]
            marker={'inn':'INN CITIZENSHIP LIVE:','chest':'CHEST WALK LIVE:','admin':'ADMIN LIVE:','features':'FEATURES LIVE:','stones':'STEPPING STONES LIVE:'}[a.scenario]
            result=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script',script],env=env,capture_output=True,text=True,timeout=150)
            (ROOT/'work'/(a.scenario+'-ui-godot.log')).write_text(result.stdout+result.stderr)
            assert result.returncode==0 and marker in result.stdout and 'SCRIPT ERROR:' not in result.stderr and '\nERROR:' not in result.stderr,result.stdout[-3000:]+result.stderr[-3000:]
            if a.scenario in ('chest','admin','features','stones'):print(a.report.read_text());return
            time.sleep(.6)
            with sqlite3.connect(runtime/'database.sdb') as db:
                assert db.execute('SELECT home FROM characters WHERE name=?',(f['character_name'],)).fetchone()[0]=='centaur','Home did not persist after UI logout'
                # A native temporary Hell Guardian kills this disposable actor.
                db.execute('UPDATE characters SET map=5,x=40,y=40,hp=1,str=1,con=1,agi=1,paperdoll=? WHERE name=?',('0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,',f['character_name']))
            s=login(f)
            # Native NPC spawning avoids random monster positions and maze pathfinding.
            # This still exercises the actual NPC attack, death and respawn handlers.
            s.chat_send('local','$snpc 129 1 1')
            death=False;respawn=False;end=time.monotonic()+25
            try:
                while time.monotonic()<end:
                    if select.select([s.sock],[],[],.2)[0]:s.pump()
                    death=death or any(e.get('kind')=='player_damage' and e.get('dead') for e in s.events)
                    respawn=respawn or any(e.get('kind')=='map_transition' and e.get('reason')=='death_respawn' for e in s.events)
                    if respawn:break
                assert death and respawn,dict(reason='Native NPC death/respawn was not observed',dead=death,respawn=respawn,player=s.state['self'],npcs=s.state['npcs'],recent_events=s.events[-8:])
                me=s.state['self'];assert (me['map_id'],me['x'],me['y'])==(29,23,25),me
                report=json.loads(a.report.read_text());report.update(home_saved_after_ui_logout=True,native_death_respawn_at_chosen_home=[29,23,25])
                # Return to the actual home inn and renounce through native packets.
                target=inns[-1];s.chat_send('local',f'$warp {target["map_id"]} {target["x"]} {target["y"]}')
                end=time.monotonic()+8
                while time.monotonic()<end:
                    if select.select([s.sock],[],[],.1)[0]:s.pump()
                    if s.state['map_id']==target['map_id'] and not s.warp:break
                npc=next(n for n in s.state['npcs'] if n['id']==160);s.inn_open(npc['index']);s.inn_remove();assert s.inn['removed'] and s.inn['current_home']['name']=='Aeven'
                report['native_renounce_returns_to_default_home']=True
                s.close();time.sleep(.6)
                with sqlite3.connect(runtime/'database.sdb') as db:assert db.execute('SELECT home FROM characters WHERE name=?',(f['character_name'],)).fetchone()[0]==''
                report['renunciation_persisted']=True;a.report.write_text(json.dumps(report,indent=2)+'\n');print(a.report.read_text())
            finally:s.close()
        except BaseException:
            for name in ('native','gateway','websocket'):
                path=base/(name+'.log')
                if path.exists():shutil.copy2(path,ROOT/'work'/('inn-citizenship-'+name+'.log'))
            raise
        finally:
            for proc in reversed(children):
                if proc.poll() is None:
                    proc.terminate()
                    try:proc.wait(timeout=20)
                    except subprocess.TimeoutExpired:proc.kill();proc.wait()
            for stream in streams:stream.close()
if __name__=='__main__':main()
