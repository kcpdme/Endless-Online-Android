#!/usr/bin/env python3
"""Real Godot/native recovery through world restart, silent WS stall and full outage.

Uses an isolated temporary runtime and fresh dev accounts. Requires free local
ports 18878-18880; never stops production or uses operator credentials.
"""
import sys,os,subprocess,shutil,time,socket,signal,re,tempfile,json,argparse
from pathlib import Path

def main():
    root=Path(__file__).resolve().parents[1]
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--state-dir');a=p.parse_args()
    from run import state_path
    state=state_path(a.state_dir); temp=tempfile.TemporaryDirectory(prefix='aster-recovery-native-');base=Path(temp.name)
    runtime=base/'runtime';control=base/'control';control.mkdir()
    shutil.copytree(state/'runtime',runtime,ignore=shutil.ignore_patterns('database.sdb*','*.log','world.bak*','etheos-v*'))
    shutil.copy2(state/'build/etheos',runtime/'etheos')
    p=runtime/'config.local.ini';s=p.read_text();s=re.sub(r'^Port\s*=.*$','Port = 18878',s,flags=re.M);p.write_text(s)
    children={};logs=[]
    def start(name,cmd,port,cwd=None):
     log=(base/f'{name}.log').open('a');logs.append(log)
     env=dict(os.environ,ASTER_VALE_RUNTIME=str(runtime),ASTER_VALE_SHORTCUT_DB=str(control/'shortcuts.sqlite3'))
     children[name]=subprocess.Popen([str(x) for x in cmd],cwd=cwd or root,env=env,stdout=log,stderr=subprocess.STDOUT)
     for _ in range(100):
      if children[name].poll() is not None:raise RuntimeError(name+' failed to start')
      try:
       with socket.create_connection(('127.0.0.1',port),timeout=.1):break
      except OSError:time.sleep(.1)
     time.sleep(.6)
    def stop(name):
     p=children.get(name)
     if p and p.poll() is None:p.send_signal(signal.SIGINT);p.wait(timeout=25)
    def wait_marker(name,timeout=50):
     end=time.monotonic()+timeout
     while not (control/name).exists():
      if children['godot'].poll() is not None:raise RuntimeError('Godot ended before '+name)
      if time.monotonic()>end:raise TimeoutError(name)
      time.sleep(.05)
    try:
     start('native',[runtime/'etheos'],18878,runtime)
     start('gateway',[sys.executable,root/'server/gateway.py','--port','18879','--eo-port','18878'],18879)
     start('websocket',[sys.executable,root/'server/ws_gateway.py','--port','18880','--tcp-port','18879','--deps-dir',state/'python'],18880)
     log=(base/'godot.log').open('w');logs.append(log)
     with tempfile.TemporaryDirectory(prefix='aster-recovery-') as private:
      env=dict(os.environ,XDG_DATA_HOME=private,XDG_CONFIG_HOME=private,ASTER_VALE_RECOVERY_CONTROL=str(control),ASTER_VALE_TEST_HOST='ws://127.0.0.1:18880/ws',ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
      children['godot']=subprocess.Popen([str(a.godot.resolve()),'--headless','--path',str(root/'client'),'--script','res://tests/connection_recovery_live.gd'],env=env,stdout=log,stderr=subprocess.STDOUT)
      wait_marker('restart-ready');stop('native');time.sleep(.8);start('native',[runtime/'etheos'],18878,runtime)
      wait_marker('blackhole-ready');children['websocket'].send_signal(signal.SIGSTOP)
      wait_marker('blackhole-detected',35);children['websocket'].send_signal(signal.SIGCONT)
      wait_marker('offline-ready');stop('websocket');stop('gateway');stop('native')
      assert children['godot'].wait(timeout=45)==0
      text=(base/'godot.log').read_text();assert 'CONNECTION RECOVERY LIVE:' in text and 'SCRIPT ERROR:' not in text and '\nERROR:' not in text,text[-4000:]
      print(a.report.read_text())
    finally:
     for name in ['websocket','gateway','native','godot']:
      p=children.get(name)
      if p and p.poll() is None:
       p.send_signal(signal.SIGCONT)
       try:stop(name)
       except subprocess.TimeoutExpired:p.kill();p.wait()
     for log in logs:log.close()
     temp.cleanup()

if __name__ == "__main__":main()
