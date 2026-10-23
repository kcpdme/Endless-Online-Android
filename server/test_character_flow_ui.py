#!/usr/bin/env python3
"""Create a fresh dev account and test all three full-screen character slots."""
import argparse,os,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--host',default='127.0.0.1');p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
 with tempfile.TemporaryDirectory(prefix='aster-character-flow-') as temp:
  env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_TEST_HOST=a.host,ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
  r=subprocess.run([a.godot,'--headless','--path',str(ROOT/'client'),'--script','res://tests/character_flow_live.gd'],env=env,capture_output=True,text=True,timeout=200)
  print(r.stdout+r.stderr);assert r.returncode==0 and 'CHARACTER FLOW LIVE:' in r.stdout and 'SCRIPT ERROR:' not in r.stderr and '\nERROR:' not in r.stderr
if __name__=='__main__':main()
