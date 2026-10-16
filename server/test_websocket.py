#!/usr/bin/env python3
"""Exercise the actual WebSocket -> TCP JSON -> native EO -> etheos path, including map travel."""
import argparse,json,pathlib,socket,sqlite3,time,urllib.request
from bootstrap_ws import load,DEFAULT_TARGET
from eo_session import Session
from run import state_path
from test_online import provision

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8081/ws');p.add_argument('--deps-dir',type=pathlib.Path,default=DEFAULT_TARGET)
    p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);a=p.parse_args();load(a.deps_dir)
    from websockets.sync.client import connect
    s,fixture=provision();name=fixture['character_name'];s.close();time.sleep(.5);dbpath=state_path(a.state_dir)/'runtime/database.sdb'
    with sqlite3.connect(dbpath) as db:
        assert name.startswith('dev') and db.execute('SELECT account FROM characters WHERE name=?',(name,)).fetchone()[0]==fixture['username']
        db.execute('UPDATE characters SET map=5,x=33,y=1 WHERE name=?',(name,))
    def login(ws):
        counter=[0]
        def call(op,**fields):
            counter[0]+=1;ws.send(json.dumps(dict(id=counter[0],op=op,**fields)));r=json.loads(ws.recv(timeout=20));assert r['ok'],r.get('error');return r['data']
        call('connect');reply=call('login',username=fixture['username'],password=fixture['password']);character=next(c for c in reply['characters'] if c['name']==name)
        return call,call('enter',character_id=character['id'])
    with connect(a.url,proxy=None,max_size=4*1024*1024,compression=None) as ws:
        ws.send('[]');assert json.loads(ws.recv(timeout=5))['ok'] is False
        call,entry=login(ws);assert (entry['player']['map_id'],entry['player']['x'],entry['player']['y'])==(5,33,1)
        moved=call('walk',direction=2);assert (moved['player']['map_id'],moved['player']['x'],moved['player']['y'])==(4,19,47),moved
        outward=[e for e in moved['events'] if e.get('kind')=='map_transition'];assert outward and outward[-1]['map_content']['sha256']
        call('disconnect')
    time.sleep(.5)
    with connect(a.url,proxy=None,max_size=4*1024*1024,compression=None) as ws:
        call,entry=login(ws);assert entry['player']['map_id']==4
        moved=call('walk',direction=0);assert (moved['player']['map_id'],moved['player']['x'],moved['player']['y'])==(5,33,1)
        inward=[e for e in moved['events'] if e.get('kind')=='map_transition'];assert inward and inward[-1]['map_content']['sha256']
        call('disconnect')
    report={'result':'passed','transport':'Real WebSocket -> existing JSON TCP gateway -> native EO v28 -> actual etheos',
            'malformed_array_rejected':True,'account_login_character_welcome':True,'outbound':[5,33,1,4,19,47],
            'map_download_verified':outward[-1]['map_content'],'reconnect_resumed_map':4,'return':[4,19,47,5,33,1],
            'return_download_verified':inward[-1]['map_content'],'tls':'Local test used ws; public wss must terminate at a trusted TLS reverse proxy. No TLS verification bypass is configured.'}
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
