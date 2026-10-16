#!/usr/bin/env python3
"""Exercise live movement acknowledgements, peer/NPC pushes, corrections and warps.
Creates fresh dev accounts only. No production character or database resets.
"""
import argparse,json,pathlib,sqlite3,time
from copy import deepcopy
from bootstrap_ws import load,DEFAULT_TARGET
from test_online import provision
from run import state_path

class Client:
    def __init__(self,url,fixture):
        from websockets.sync.client import connect
        self.context=connect(url,proxy=None,max_size=4*1024*1024,compression=None);self.ws=self.context.__enter__();self.serial=0;self.worlds=[]
        self.call('connect');data=self.call('login',username=fixture['username'],password=fixture['password'])
        char=next(c for c in data['characters'] if c['name']==fixture['character_name'])
        self.entry=self.call('enter',character_id=char['id']);self.state=deepcopy(self.entry);self.call('stream',enabled=True)
    def receive(self,timeout=15):
        r=json.loads(self.ws.recv(timeout=timeout));assert r['ok'],r.get('error')
        if r.get('event')=='world':
            data=r['data'];self.state.update({k:v for k,v in data.items() if not k.endswith(('_upsert','_remove'))})
            for collection,key in [('players','player_id'),('npcs','index'),('items','uid')]:
                rows={row[key]:row for row in self.state[collection]}
                for id in data.get(collection+'_remove',[]):rows.pop(id,None)
                rows.update({row[key]:row for row in data.get(collection+'_upsert',[])})
                self.state[collection]=list(rows.values())
            self.worlds.append(deepcopy(self.state))
        return r
    def call(self,op,**fields):
        self.serial+=1;serial=self.serial;self.ws.send(json.dumps(dict(id=serial,op=op,**fields)))
        while True:
            r=self.receive()
            if r.get('id')==serial:return r['data']
    def until(self,predicate,timeout=15):
        end=time.monotonic()+timeout
        while True:
            for world in self.worlds:
                if predicate(world):return world
            left=end-time.monotonic()
            if left<=0:raise AssertionError('Timed out waiting for authoritative streamed state')
            self.receive(left)
    def close(self):self.context.__exit__(None,None,None)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--deps-dir',type=pathlib.Path,default=DEFAULT_TARGET)
    p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);a=p.parse_args();load(a.deps_dir)
    fixtures=[]
    for _ in range(4):
        s,f=provision();s.close();fixtures.append(f)
    time.sleep(.6)
    dbpath=state_path(a.state_dir)/'runtime/database.sdb'
    # Stage only our three newly created, disconnected dev fixtures.
    with sqlite3.connect(dbpath) as db:
        for f,(x,y) in zip(fixtures,[(40,40),(40,41),(33,1),(0,0)]):
            assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
            assert db.execute('SELECT account FROM characters WHERE name=?',(f['character_name'],)).fetchone()[0]==f['username']
            db.execute('UPDATE characters SET map=5,x=?,y=? WHERE name=? AND account=?',(x,y,f['character_name'],f['username']))
    first=Client(a.url,fixtures[0]);observer=Client(a.url,fixtures[1]);report={};clients=[first,observer]
    try:
        pid=first.entry['player']['player_id'];first.worlds.clear();observer.worlds.clear()
        receipt=first.call('move',direction=3,input_seq=1,map_id=5,x=41,y=40)
        assert receipt=={'sent':True,'input_seq':1}
        world=first.until(lambda w:w['position_seq']==1 and w['position_update'])
        assert (world['player']['x'],world['player']['y'])==(41,40) and not world['correction']
        peer=observer.until(lambda w:any(c['player_id']==pid and (c['x'],c['y'])==(41,40) for c in w['players']))
        report['native_walk_ack_and_peer_push_without_refresh']=True
        initial={n['index']:(n['x'],n['y']) for n in observer.entry['npcs']}
        observer.until(lambda w:any(n['index'] in initial and (n['x'],n['y'])!=initial[n['index']] for n in w['npcs']),20)
        report['npc_movement_push_without_refresh']=True
        # Deliberately wrong client coordinates: native server moves east to 42,40,
        # then corrects the bad prediction. It must not consume the next input twice.
        first.worlds.clear()
        first.call('move',direction=3,input_seq=2,map_id=5,x=99,y=99)
        world=first.until(lambda w:w['position_seq']==2 and w['correction'])
        assert (world['player']['x'],world['player']['y'])==(42,40)
        report['authoritative_mismatch_correction']=True
        first.worlds.clear()
        # Burst simulates jitter delivering two correctly timed client inputs together.
        first.call('move',direction=1,input_seq=3,map_id=5,x=41,y=40)
        first.call('move',direction=1,input_seq=4,map_id=5,x=40,y=40)
        world=first.until(lambda w:w['position_seq']==4)
        assert (world['player']['x'],world['player']['y'])==(40,40)
        report['bounded_jitter_burst_acknowledged']=True
        warp=Client(a.url,fixtures[2]);clients.append(warp)
        warp.call('move',direction=2,input_seq=1,map_id=5,x=33,y=0)
        world=warp.until(lambda w:w['map_id']==4)
        assert (world['player']['x'],world['player']['y'])==(19,47) and world['position_seq']==1
        assert any(e.get('kind')=='map_transition' and e['map_content']['sha256'] for e in world['events'])
        warp.worlds.clear();warp.call('move',direction=0,input_seq=2,map_id=4,x=19,y=48)
        world=warp.until(lambda w:w['map_id']==5)
        assert (world['player']['x'],world['player']['y'])==(33,1) and world['position_seq']==2
        report['streamed_map_roundtrip_and_content_negotiation']=True
        blocked=Client(a.url,fixtures[3]);clients.append(blocked)
        blocked.call('move',direction=1,input_seq=1,map_id=5,x=0,y=0)
        world=blocked.until(lambda w:w['position_seq']==1 and w['correction'])
        assert (world['player']['x'],world['player']['y'])==(0,0)
        report['native_rejected_step_corrected']=True
        report['result']='passed';report['transport']='Real WebSocket -> live adapter -> native EO -> etheos';report['database_reset']=False
    finally:
        for c in clients:c.close()
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
