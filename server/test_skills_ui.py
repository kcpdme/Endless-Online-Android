#!/usr/bin/env python3
"""Actual Godot skill buttons and native master UI; isolated dev accounts only."""
import argparse,json,os,pathlib,subprocess,tempfile
from test_skills import fixtures
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--screenshots',type=pathlib.Path);a=p.parse_args()
    fs=json.loads(a.fixture_file.read_text()) if a.fixture_file else fixtures()
    assert all(f['username'].startswith('dev') and f['character_name'].startswith('dev') for f in fs.values())
    with tempfile.TemporaryDirectory(prefix='astervale-skills-ui-') as temp:
        private=pathlib.Path(temp)/'fixtures.json';private.write_text(json.dumps(fs));private.chmod(0o600)
        env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_PEER_FIXTURES=str(private),ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
        display=['--headless']
        if a.screenshots:
            a.screenshots.mkdir(parents=True,exist_ok=True);env['ASTER_VALE_SCREENSHOTS']=str(a.screenshots.resolve());display=['--rendering-method','gl_compatibility']
        r=subprocess.run([str(a.godot.resolve()),*display,'--path',str(ROOT/'client'),'--script','res://tests/skills_live.gd'],env=env,capture_output=True,text=True,timeout=120)
        print(r.stdout+r.stderr);assert r.returncode==0 and 'SKILLS UI LIVE PASS:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr
if __name__=='__main__':main()
