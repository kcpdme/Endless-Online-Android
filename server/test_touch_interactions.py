#!/usr/bin/env python3
"""Native Marble counter shop and real engine touch targeting inside the joystick zone."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]

def fixtures():
    fs={}
    for role in ('shop','combat'):
        s,f=provision();s.close();fs[role]=f
    time.sleep(.7)
    with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
        for role,f in fs.items():
            assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
            mid,x,y=(125,6,4) if role=='shop' else (5,40,40)
            db.execute('UPDATE characters SET map=?,x=?,y=?,level=50,exp=16637500,"str"=0,"int"=20,wis=100,agi=500,"con"=100,hp=32000,tp=32000,spells=?,inventory=? WHERE account=? AND name=?',(mid,x,y,'1,0;4,0;5,0;','1,50000;',f['username'],f['character_name']))
    return fs

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
    fs=json.loads(a.fixture_file.read_text()) if a.fixture_file else fixtures()
    assert all(f['username'].startswith('dev') and f['character_name'].startswith('dev') for f in fs.values())
    with tempfile.TemporaryDirectory(prefix='astervale-touch-ui-') as temp:
        private=pathlib.Path(temp)/'fixtures.json';private.write_text(json.dumps(fs));private.chmod(0o600)
        env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_PEER_FIXTURES=str(private),ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
        display=['--headless']
        if a.screenshots:
            a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
        r=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script','res://tests/touch_interactions_live.gd'],env=env,capture_output=True,text=True,timeout=110)
        print(r.stdout+r.stderr);assert r.returncode==0 and 'TOUCH INTERACTIONS LIVE PASS:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr
if __name__=='__main__':main()
