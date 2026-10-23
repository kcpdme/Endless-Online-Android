#!/usr/bin/env python3
"""Real soda bag use, emotes and matching native nearby speech in two Godot clients."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]
def fixtures():
 fs={}
 for role in ('actor','observer'):
  s,f=provision();s.close();fs[role]=f
 time.sleep(.7)
 with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
  for index,f in enumerate(fs.values()):
   assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
   doll=[0]*15
   if index==0:doll[8]=349
   changed=db.execute('UPDATE characters SET map=90,x=?,y=3,hp=30000,tp=30000,spells=?,inventory=?,paperdoll=? WHERE account=? AND name=?',(2+index,'1,0;17,0;','1,1000;210,3;211,1;',','.join(map(str,doll)),f['username'],f['character_name']))
   assert changed.rowcount==1
 return fs

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--host',default='127.0.0.1');p.add_argument('--fixture',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
 fs=json.loads(a.fixture.read_text()) if a.fixture else fixtures();assert all(f['username'].startswith('dev') for f in fs.values())
 with tempfile.TemporaryDirectory(prefix='aster-fairy-soda-') as temp:
  private=pathlib.Path(temp)/'fixtures.json';private.write_text(json.dumps(fs));private.chmod(0o600)
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_SODA_FIXTURE=str(private),ASTER_VALE_TEST_HOST=a.host,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
  display=['--headless']
  if a.screenshots:
   a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
  r=subprocess.run([a.godot,*display,'--path',str(ROOT/'client'),'--script','res://tests/fairy_soda_live.gd'],env=env,capture_output=True,text=True,timeout=120)
  print(r.stdout+r.stderr);assert r.returncode==0 and 'FAIRY SODA LIVE:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr and '\nERROR:' not in r.stderr
if __name__=='__main__':main()
