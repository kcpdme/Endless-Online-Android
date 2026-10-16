#!/usr/bin/env python3
"""Run the actual Godot bag, EXP HUD and Nearby chat against native EO."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
 if a.fixture_file:f=json.loads(a.fixture_file.read_text())
 else:
  s,f=provision();s.close();time.sleep(.6)
  assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
  with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
   db.execute('UPDATE characters SET map=5,x=59,y=13,level=2,exp=2000,"con"=10,"wis"=10,hp=1,tp=0,inventory=? WHERE account=? AND name=?',('2,10;3,10;375,2;62,2;65,2;',f['username'],f['character_name']))
 assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
 with tempfile.TemporaryDirectory(prefix='astervale-consumables-') as temp:
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_USERNAME=f['username'],ASTER_VALE_TEST_PASSWORD=f['password'],ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
  display=['--headless']
  if a.screenshots:
   a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
  r=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script','res://tests/consumables_live.gd'],env=env,capture_output=True,text=True,timeout=125)
  print(r.stdout+r.stderr);assert r.returncode==0 and 'CONSUMABLES LIVE PASS:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr
if __name__=='__main__':main()
