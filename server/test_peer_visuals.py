#!/usr/bin/env python3
"""Real Godot observer sees native equipment changes and both peer swing frames."""
import argparse,json,os,pathlib,sqlite3,subprocess,tempfile,time
from test_online import provision
from run import state_path

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--state-dir');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
    if a.fixture_file:fixtures=json.loads(a.fixture_file.read_text())
    else:
        fixtures={}
        for role in ('actor','observer'):
            s,f=provision();s.close();fixtures[role]=f
        time.sleep(.6)
        with sqlite3.connect(state_path(a.state_dir)/'runtime/database.sdb') as db:
            for role,y in [('actor',13),('observer',14)]:
                f=fixtures[role];assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
                db.execute('UPDATE characters SET map=5,x=59,y=?,inventory=? WHERE account=? AND name=?',(y,'21,1;281,1;',f['username'],f['character_name']))
    assert all(f['username'].startswith('dev') for f in fixtures.values())
    with tempfile.TemporaryDirectory(prefix='astervale-peer-visuals-') as temp:
        private=pathlib.Path(temp)/'fixtures.json';private.write_text(json.dumps(fixtures));private.chmod(0o600)
        env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_PEER_FIXTURES=str(private),ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
        root=pathlib.Path(__file__).resolve().parents[1]
        result=subprocess.run([str(a.godot.resolve()),'--headless','--path',str(root/'client'),'--script','res://tests/peer_visuals_live.gd'],env=env,capture_output=True,text=True,timeout=110)
        print(result.stdout+result.stderr)
        assert result.returncode==0 and 'PEER VISUALS LIVE PASS:' in result.stdout and 'SCRIPT ERROR:' not in result.stderr

if __name__=='__main__':main()
