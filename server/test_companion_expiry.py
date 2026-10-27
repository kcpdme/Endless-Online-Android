"""Native companion expiry acceptance in a disposable world; no player database.
Run after installing profile 2 into work/balance-v2/runtime.
"""
import json,os,secrets,shutil,socket,sqlite3,subprocess,sys,tempfile,time,select
from pathlib import Path
from contextlib import closing

def main():
    root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'server'))
    from eo_session import Session
    from test_online import dev_name
    with tempfile.TemporaryDirectory(prefix='aster-pet-expiry-') as tmp:
     r=Path(tmp)/'runtime';shutil.copytree(root/'work/balance-v2/runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'))
     cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18895\nRecoverSpeed = 1h\nIPReconnectLimit = 0\nCompanionLifetimeSeconds = 2\n')
     os.environ['ASTER_VALE_RUNTIME']=str(r)
     log=(Path(tmp)/'native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
     try:
      for _ in range(100):
       try:
        with socket.create_connection(('127.0.0.1',18895),timeout=.1):break
       except OSError:time.sleep(.1)
      time.sleep(.6);user=dev_name();name=dev_name();password=secrets.token_urlsafe(18)
      s=Session(port=18895);s.register(user,password);s.login(user,password);s.create_character(name);s.close();time.sleep(.7)
      with closing(sqlite3.connect(r/'database.sdb')) as db,db:
       db.execute('UPDATE characters SET class=7,level=45,map=5,x=40,y=40,cha=81,"int"=21,"con"=33,hp=1000,tp=1000,spells=? WHERE name=? AND account=?',('28,0;35,0;',name,user))
      from live_session import LiveSession
      s=LiveSession('127.0.0.1',18895)
      try:
       chars=s.login(user,password)['characters'];s.enter(next(c['id'] for c in chars if c['name']==name));s.snapshot();start=time.monotonic();s.cast_spell(28,'self');spawned=False
       while time.monotonic()-start<7:
        s.poll_actions()
        if select.select([s.sock],[],[],.04)[0]:s.pump()
        if getattr(s,'companion',None):spawned=True
        if spawned and not getattr(s,'companion',None):break
       assert spawned and not s.companion and s.stats['tp']>0
       s.refresh() # Drain the NPC removal packet following ownership expiry.
       assert not any(n['id'] in (306,307,308) for n in s.state['npcs'])
       report=dict(result='passed',native_companion_spawned=True,configured_expiry_seconds=2,expired_with_mana_remaining=True,no_orphan_npc=True,isolated_database=True)
       (root/'work/balance-v2/expiry-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
      finally:s.close()
     finally:proc.terminate();proc.wait(timeout=10);log.close()

if __name__=='__main__':main()
