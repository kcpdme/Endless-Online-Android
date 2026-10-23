#!/usr/bin/env python3
"""Actual Godot party/heal/Bard UI against native server; isolated dev fixtures."""
import argparse,json,os,pathlib,subprocess,tempfile
from test_party_live import fixtures
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--host',default='ws://127.0.0.1:8184/ws');p.add_argument('--fixture',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
 fs=json.loads(a.fixture.read_text()) if a.fixture else fixtures()
 assert all(f['username'].startswith('dev') for f in fs.values())
 with tempfile.TemporaryDirectory(prefix='aster-social-ui-') as temp:
  private=pathlib.Path(temp)/'fixtures.json';private.write_text(json.dumps(fs));private.chmod(0o600)
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_PARTY_FIXTURE=str(private),ASTER_VALE_TEST_HOST=a.host,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
  r=subprocess.run([a.godot,'--headless','--path',str(ROOT/'client'),'--script','res://tests/party_ui_live.gd'],env=env,capture_output=True,text=True,timeout=150)
  output=r.stdout+r.stderr;print(output);assert r.returncode==0 and 'PARTY UI LIVE PASS:' in output and 'SCRIPT ERROR:' not in output and '\nERROR:' not in output
if __name__=='__main__':main()
