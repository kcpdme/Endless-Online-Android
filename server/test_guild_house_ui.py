#!/usr/bin/env python3
"""Touch actual Guild Bob in the guild house using an isolated dev character."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--host',default='127.0.0.1');p.add_argument('--fixture',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
 if a.fixture:fs=json.loads(a.fixture.read_text())
 else:
  s,fs=provision();s.close();time.sleep(.7)
  with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
   assert fs['username'].startswith('dev') and fs['character_name'].startswith('dev')
   changed=db.execute('UPDATE characters SET map=108,x=8,y=4,inventory=? WHERE account=? AND name=?',('1,60000;',fs['username'],fs['character_name']));assert changed.rowcount==1
 assert fs['username'].startswith('dev')
 with tempfile.TemporaryDirectory(prefix='aster-guild-house-') as temp:
  private=pathlib.Path(temp)/'fixture.json';private.write_text(json.dumps(fs));private.chmod(0o600)
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_GUILD_FIXTURE=str(private),ASTER_VALE_TEST_HOST=a.host,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
  display=['--headless']
  if a.screenshots:
   a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
  r=subprocess.run([a.godot,*display,'--path',str(ROOT/'client'),'--script','res://tests/guild_house_live.gd'],env=env,capture_output=True,text=True,timeout=120)
  print(r.stdout+r.stderr);assert r.returncode==0 and 'GUILD HOUSE LIVE:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr and '\nERROR:' not in r.stderr
if __name__=='__main__':main()
