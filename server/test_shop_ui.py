#!/usr/bin/env python3
"""Native Marble shop: full recipe visibility, persistent browsing and actual transactions."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]

def fixture():
    s,f=provision();s.close();time.sleep(.7)
    assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
    inv='1,50000;318,8;320,8;322,10;319,4;321,2;323,2;309,1;301,2;302,3;303,2;304,6;305,4;306,2;307,6;471,1;476,1;'
    with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
        db.execute('UPDATE characters SET map=125,x=6,y=4,level=50,exp=16637500,"str"=1000,"con"=100,hp=32000,tp=32000,inventory=? WHERE account=? AND name=?',(inv,f['username'],f['character_name']))
    return f

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
    f=json.loads(a.fixture_file.read_text()) if a.fixture_file else fixture()
    assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
    with tempfile.TemporaryDirectory(prefix='astervale-shop-ui-') as temp:
        private=pathlib.Path(temp)/'fixture.json';private.write_text(json.dumps(f));private.chmod(0o600)
        env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_SHOP_FIXTURE=str(private),ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
        display=['--headless']
        if a.screenshots:
            a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
        r=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script','res://tests/shop_details_live.gd'],env=env,capture_output=True,text=True,timeout=110)
        print(r.stdout+r.stderr);assert r.returncode==0 and 'SHOP DETAILS LIVE PASS:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr
if __name__=='__main__':main()
