"""Real regular-player walking and unchanged admin warp in a disposable world."""
import argparse,json,os,secrets,shutil,socket,sqlite3,subprocess,sys,tempfile,time
from collections import deque
from contextlib import closing
from pathlib import Path
from eo_session import Session
from live_session import LiveSession
from test_online import dev_name
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from import_eo import parse_emf
from export_catalog import SERVER_BLOCKING_SPECS
DIRECTIONS=[(0,0,1),(1,-1,0),(2,0,-1),(3,1,0)]

def route(world,start,target,occupied=()):
    blocked={tuple((s['x'],s['y'])) for s in world['tile_specs'] if s['spec'] in SERVER_BLOCKING_SPECS}|set(occupied)
    portals={(w['x'],w['y']) for w in world['warps']}-{target};q=deque([(start,[])]);seen={start}
    while q:
        at,path=q.popleft()
        if at==target:return path
        for d,dx,dy in DIRECTIONS:
            p=at[0]+dx,at[1]+dy
            if 0<=p[0]<world['width'] and 0<=p[1]<world['height'] and p not in blocked|portals|seen:seen.add(p);q.append((p,path+[d]))
    raise AssertionError('No walkable route '+str((world['id'],start,target)))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,default=ROOT/'work/sky-walking/runtime');p.add_argument('--report',type=Path,default=ROOT/'work/sky-walking/native-report.json');p.add_argument('--godot',type=Path);a=p.parse_args()
    checks=[];cases=[];processes=[];streams=[];steps=0
    def check(ok,why):
        if not ok:raise AssertionError(why)
        checks.append(why)
    with tempfile.TemporaryDirectory(prefix='aster-sky-walk-') as temp:
        base=Path(temp);r=base/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'));os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18920\nIPReconnectLimit = 0\nNoInteractDefault = 0\n')
        worlds={int(f.stem):parse_emf(f.read_bytes(),int(f.stem)) for f in (r/'data/maps').glob('*.emf')}
        def start(name,command,port,cwd=ROOT):
            log=(base/(name+'.log')).open('w');streams.append(log);proc=subprocess.Popen(list(map(str,command)),cwd=cwd,stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,ASTER_VALE_SHORTCUT_DB=str(base/'shortcuts.sqlite3')));processes.append(proc)
            for _ in range(100):
                if proc.poll() is not None:raise RuntimeError(name+' failed')
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
                except OSError:time.sleep(.1)
            else:raise RuntimeError(name+' not listening')
            time.sleep(.5)
        def provision():
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name());s=Session(port=18920)
            try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['character_name'])
            finally:s.close()
            time.sleep(.6);return f
        def stage(f,location,admin=0):
            time.sleep(.6)
            with closing(sqlite3.connect(r/'database.sdb')) as db,db:
                db.execute('UPDATE characters SET map=?,x=?,y=?,level=12,class=6,"con"=1000,hp=30000,tp=1000,admin=? WHERE name=? AND account=?',(*location,admin,f['character_name'],f['username']))
        def login(f):
            s=LiveSession('127.0.0.1',18920);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['character_name']));s.snapshot();return s
        def walk_to(s,point):
            nonlocal steps
            mid=s.state['map_id']
            for _ in range(500):
                me=s.state['self'];at=(me['x'],me['y'])
                if at==point:return
                occupied={(n['x'],n['y']) for n in s.state['npcs'] if (n['x'],n['y'])!=point}
                path=route(worlds[mid],at,point,occupied)
                s.walk(path[0]);steps+=1
                check(s.state['map_id']==mid or point in {(w['x'],w['y']) for w in worlds[mid]['warps']},'Walking obeys the expected native map')
                if s.state['map_id']!=mid:return
            raise AssertionError('Walking did not arrive')
        def case(f,name,location,point,expected):
            stage(f,location);s=login(f)
            try:
                check(s.stats['admin']==0,'Walking fixture has no admin powers');walk_to(s,point);me=s.state['self'];actual=[s.state['map_id'],me['x'],me['y']]
                check(actual==list(expected),name);cases.append(dict(name=name,start=list(location),actual=actual,expected=list(expected)))
            finally:s.close()
        try:
            start('native',[r/'etheos'],18920,r);f=provision()
            # Walk every connecting map from Aeven, without admin commands.
            stage(f,(5,1,78));s=login(f)
            try:
                for mid,point,destination in [(5,(0,78),186),(186,(0,15),11),(11,(0,15),120),(120,(0,15),23),(23,(13,2),73),(73,(10,11),71)]:
                    check(s.state['map_id']==mid,'Normal route reaches map '+str(mid));walk_to(s,point);check(s.state['map_id']==destination,'Normal walking crosses '+str(mid)+' to '+str(destination))
                cases.append(dict(name='Complete Aeven to Sky Wonder walking route',actual=[71,s.state['self']['x'],s.state['self']['y']]))
            finally:s.close()
            for values in [
                ('Second entrance lane',(23,14,3),(14,2),(73,19,12)),
                ('Sky return uses the cloud bridge',(71,27,63),(27,64),(73,11,11)),
                ('Bridge returns safely to Avenue',(73,19,11),(20,11),(23,14,5)),
                ('Second bridge return lane',(73,19,12),(20,12),(23,14,5)),
                ('Phoenix Field entrance remains usable',(71,34,12),(34,11),(252,18,41)),
                ('Phoenix Field return remains usable',(252,18,45),(18,46),(71,34,14)),
                ('Halowdale exit is preserved',(23,1,14),(0,14),(151,79,31)),
                ('Beach exit is preserved',(23,14,39),(14,40),(13,33,1)),
            ]:case(f,*values)
            stage(f,(5,40,40),admin=4);s=login(f)
            try:
                preset=next(d for d in s.admin_open()['destinations'] if d['key']=='sky_haven');check(preset==dict(key='sky_haven',name='Sky Haven',map_id=71,x=34,y=14),'Admin preset is unchanged')
                s.admin_teleport('sky_haven');me=s.state['self'];check((s.state['map_id'],me['x'],me['y'])==(71,34,14),'Existing admin teleport still reaches its exact original landing')
            finally:s.close()
            if a.godot:
                stage(f,(23,14,5));fixture=base/'fixture.json';fixture.write_text(json.dumps(f));fixture.chmod(0o600)
                start('gateway',[sys.executable,ROOT/'server/gateway.py','--port',18921,'--eo-port',18920],18921)
                start('websocket',[sys.executable,ROOT/'server/ws_gateway.py','--port',18922,'--tcp-port',18921,'--deps-dir',ROOT/'work/server-build/python'],18922)
                env=dict(os.environ,ASTER_VALE_SKY_FIXTURE=str(fixture),ASTER_VALE_TEST_HOST='ws://127.0.0.1:18922/ws',ASTER_VALE_TEST_REPORT=str(base/'ui-report.json'),XDG_DATA_HOME=str(base/'godot-data'),XDG_CONFIG_HOME=str(base/'godot-config'))
                result=subprocess.run([str(a.godot.resolve()),'--headless','--path',str(ROOT/'client'),'--script','res://tests/sky_wonder_live.gd'],env=env,capture_output=True,text=True,timeout=120)
                (ROOT/'work/sky-walking/ui.log').write_text(result.stdout+result.stderr);check(result.returncode==0 and 'SCRIPT ERROR' not in result.stderr,'Godot client walks the new route through public protocol adapters')
                shutil.copy2(base/'ui-report.json',ROOT/'work/sky-walking/ui-report.json')
            report=dict(result='passed',checks=len(checks),native_walk_steps=steps,cases=cases,admin_preset_and_permissions_unchanged=True,isolated_database=True,production_database_opened=False)
            a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
        finally:
            for p in reversed(processes):
                p.terminate()
                try:p.wait(timeout=10)
                except subprocess.TimeoutExpired:p.kill();p.wait()
            for stream in streams:stream.close()
            for name in ['native','gateway','websocket']:
                if (base/(name+'.log')).exists():shutil.copy2(base/(name+'.log'),ROOT/'work/sky-walking'/(name+'.log'))
if __name__=='__main__':main()
