#!/usr/bin/env python3
"""Private dev characters exercise native purchases, robe appearance and bag dragging."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_shop_ui import fixture as shop_fixture
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]
def fixture():
    f=shop_fixture()
    s,other=provision();s.close();time.sleep(.7)
    with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
        db.execute("UPDATE characters SET hp=1,tp=1,statpoints=12,inventory='1,50000;407,1;80,1;281,1;426,1;56,1;4,7;5,7;318,8;320,8;322,10;'  WHERE account=? AND name=?",(f['username'],f['character_name']))
        db.execute('UPDATE characters SET map=125,x=7,y=4 WHERE account=? AND name=?',(other['username'],other['character_name']))
    f['observer']=other
    return f

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
    f=json.loads(a.fixture_file.read_text()) if a.fixture_file else fixture()
    assert all(v['username'].startswith('dev') for v in (f,f['observer']))
    with tempfile.TemporaryDirectory(prefix='astervale-inventory-ui-') as temp:
        private=pathlib.Path(temp)/'fixture.json';private.write_text(json.dumps(f));private.chmod(0o600)
        env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_SHOP_FIXTURE=str(private),ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
        display=['--headless']
        if a.screenshots:
            a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
        r=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script','res://tests/inventory_live.gd'],env=env,capture_output=True,text=True,timeout=100)
        print(r.stdout+r.stderr);assert r.returncode==0 and 'INVENTORY LIVE PASS:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr
if __name__=='__main__':main()
