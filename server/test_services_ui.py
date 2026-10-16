#!/usr/bin/env python3
"""Exercise the actual Godot storage/player/trade/chat dialogs with real native sessions."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
    if a.fixture_file:fixtures=json.loads(a.fixture_file.read_text())
    else:
        fixtures={}
        for role in ('actor','observer'):
            s,f=provision();s.close();fixtures[role]=f
        time.sleep(.6)
        with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
            for role,y in [('actor',3),('observer',2)]:
                f=fixtures[role];assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
                db.execute('UPDATE characters SET map=90,x=2,y=?,inventory=?,goldbank=0,bank="",bankmax=0 WHERE account=? AND name=?',(y,'1,50000;21,5;281,2;',f['username'],f['character_name']))
    assert all(f['username'].startswith('dev') for f in fixtures.values())
    with tempfile.TemporaryDirectory(prefix='astervale-services-ui-') as temp:
        private=pathlib.Path(temp)/'fixtures.json';private.write_text(json.dumps(fixtures));private.chmod(0o600)
        env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_PEER_FIXTURES=str(private),ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
        display=['--headless']
        if a.screenshots:
            a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
        result=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script','res://tests/services_live.gd'],env=env,capture_output=True,text=True,timeout=110)
        print(result.stdout+result.stderr)
        assert result.returncode==0 and 'SERVICES UI LIVE PASS:' in result.stdout and 'SCRIPT ERROR:' not in result.stderr
if __name__=='__main__':main()
