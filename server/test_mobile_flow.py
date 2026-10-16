#!/usr/bin/env python3
"""Stage only a fresh dev fixture and test actual touch movement/pickup in Godot."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from live_session import LiveSession
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--chase',action='store_true');p.add_argument('--godot',required=True);p.add_argument('--state-dir');p.add_argument('--url',default='ws://127.0.0.1:8194/ws');p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
 base,f=provision();base.close();time.sleep(.6)
 with sqlite3.connect(state_path(a.state_dir)/'runtime/database.sdb') as db:
  assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
  db.execute('UPDATE characters SET map=5,x=59,y=15,inventory=? WHERE name=? AND account=?',('249,3;',f['character_name'],f['username']))
 if a.chase:
  with sqlite3.connect(state_path(a.state_dir)/'runtime/database.sdb') as db:db.execute('UPDATE characters SET x=40,y=40,"str"=1000,"agi"=1000,"con"=200,hp=1000,inventory=? WHERE name=? AND account=?',('21,1;',f['character_name'],f['username']))
 if not a.chase:
  s=LiveSession();characters=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in characters if c['name']==f['character_name']));s.drop(249,1);s.close();time.sleep(.6)
  with sqlite3.connect(state_path(a.state_dir)/'runtime/database.sdb') as db:
   db.execute('UPDATE characters SET x=59,y=13 WHERE name=? AND account=?',(f['character_name'],f['username']))
  # Native player-drop protection is five seconds; new login has a new player ID.
  time.sleep(5.2)
 with tempfile.TemporaryDirectory(prefix='astervale-mobile-net-') as temp:
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_USERNAME=f['username'],ASTER_VALE_TEST_PASSWORD=f['password'])
  if a.report:env['ASTER_VALE_TEST_REPORT']=str(a.report.resolve())
  r=subprocess.run([str(pathlib.Path(a.godot).resolve()),'--headless','--path',str(ROOT/'client'),'--script','res://tests/chase_live.gd' if a.chase else 'res://tests/mobile_network_live.gd'],env=env,capture_output=True,text=True,timeout=100)
  print(r.stdout+r.stderr);assert r.returncode==0 and ('CHASE LIVE PASS:' if a.chase else 'MOBILE NETWORK LIVE PASS:') in r.stdout
if __name__=='__main__':main()
