"""Render and exercise the town board using a disposable native world and regular player."""
import json,os,secrets,shutil,socket,sqlite3,subprocess,sys,tempfile,time
from pathlib import Path
from eo_session import Session
from test_online import dev_name
ROOT=Path(__file__).resolve().parents[1]
def main():
 out=ROOT/'work/classic-rates-board';processes=[];streams=[]
 with tempfile.TemporaryDirectory(prefix='aster-townboard-') as tmp:
  b=Path(tmp);r=b/'runtime';shutil.copytree(out/'runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log'));os.environ['ASTER_VALE_RUNTIME']=str(r)
  cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18965\nIPReconnectLimit = 0\n')
  def start(name,cmd,port,cwd=ROOT):
   log=(out/(name+'.log')).open('w');streams.append(log);proc=subprocess.Popen(list(map(str,cmd)),cwd=cwd,env=dict(os.environ,ASTER_VALE_SHORTCUT_DB=str(b/'shortcuts.sqlite3')),stdout=log,stderr=subprocess.STDOUT);processes.append(proc)
   for _ in range(100):
    if proc.poll() is not None:raise RuntimeError(name+' failed')
    try:
     with socket.create_connection(('127.0.0.1',port),timeout=.1):break
    except OSError:time.sleep(.1)
   time.sleep(.5)
  try:
   start('board-native',[r/'etheos'],18965,r)
   f=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name());s=Session(port=18965)
   try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['character_name'])
   finally:s.close()
   time.sleep(.7)
   with sqlite3.connect(r/'database.sdb') as db:assert db.execute('UPDATE characters SET map=5,x=46,y=2,level=5,exp=16638 WHERE name=? AND account=?',(f['character_name'],f['username'])).rowcount==1
   fp=b/'fixture.json';fp.write_text(json.dumps(f));fp.chmod(0o600)
   start('board-gateway',[sys.executable,ROOT/'server/gateway.py','--port',18966,'--eo-port',18965],18966)
   start('board-websocket',[sys.executable,ROOT/'server/ws_gateway.py','--port',18967,'--tcp-port',18966,'--deps-dir',ROOT/'work/server-build/python'],18967)
   shots=out/'screenshots';shots.mkdir(exist_ok=True)
   env=dict(os.environ,DISPLAY=':0',ASTER_VALE_BOARD_FIXTURE=str(fp),ASTER_VALE_TEST_HOST='ws://127.0.0.1:18967/ws',ASTER_VALE_SCREENSHOTS=str(shots),ASTER_VALE_TEST_REPORT=str(ROOT/'docs/classic-town-board-client-report.json'),XDG_DATA_HOME=str(b/'godot-data'),XDG_CONFIG_HOME=str(b/'godot-config'))
   result=subprocess.run([str(ROOT/'work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64'),'--path',str(ROOT/'client'),'--script','res://tests/town_board_live.gd'],env=env,capture_output=True,text=True,timeout=120)
   (out/'board-client.log').write_text(result.stdout+result.stderr);assert result.returncode==0 and 'SCRIPT ERROR' not in result.stderr,'Native board UI failed; see board-client.log'
   print((ROOT/'docs/classic-town-board-client-report.json').read_text())
  finally:
   for proc in reversed(processes):
    proc.terminate()
    try:proc.wait(timeout=15)
    except subprocess.TimeoutExpired:proc.kill();proc.wait()
   for stream in streams:stream.close()
if __name__=='__main__':main()
