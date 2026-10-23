#!/usr/bin/env python3
"""Native hair purchase, observer, relogin persistence and real Aeven sign touch."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]
def fixtures():
 fs={}
 for role in ('actor','observer','sign'):
  s,f=provision();s.close();fs[role]=f
 time.sleep(.7)
 with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
  for i,(role,f) in enumerate(fs.items()):
   assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
   mid,x,y=(5,64,23) if role=='sign' else (51,4+i,9)
   c=db.execute('UPDATE characters SET map=?,x=?,y=?,level=5,exp=64000,hp=30000,tp=30000,hairstyle=1,haircolor=0,inventory=? WHERE account=? AND name=?',(mid,x,y,'1,10000;',f['username'],f['character_name']));assert c.rowcount==1
 return fs

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--host',default='127.0.0.1');p.add_argument('--fixture',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args();fs=json.loads(a.fixture.read_text()) if a.fixture else fixtures()
 assert all(f['username'].startswith('dev') for f in fs.values())
 with tempfile.TemporaryDirectory(prefix='aster-barber-native-') as temp:
  private=pathlib.Path(temp)/'fixture.json';private.write_text(json.dumps(fs));private.chmod(0o600)
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_BARBER_FIXTURE=str(private),ASTER_VALE_TEST_HOST=a.host,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
  r=subprocess.run([a.godot,'--headless','--path',str(ROOT/'client'),'--script','res://tests/barber_live.gd'],env=env,capture_output=True,text=True,timeout=150)
  print(r.stdout+r.stderr);assert r.returncode==0 and 'BARBER LIVE:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr and '\nERROR:' not in r.stderr
if __name__=='__main__':main()
