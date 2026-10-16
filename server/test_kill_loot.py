#!/usr/bin/env python3
"""Kill a native NPC and pick up its actual random drop. Only a fresh dev character is staged."""
import argparse,json,pathlib,select,sqlite3,time
from live_session import LiveSession
from test_online import provision,next_toward
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
 base,f=provision();base.close();time.sleep(.6)
 with sqlite3.connect(state_path(a.state_dir)/'runtime/database.sdb') as db:
  assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
  db.execute('UPDATE characters SET map=5,x=40,y=40,"str"=1000,"con"=200,hp=1000,inventory=? WHERE name=? AND account=?',('21,1;',f['character_name'],f['username']))
 s=LiveSession();characters=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in characters if c['name']==f['character_name']));s.equip(21);s.snapshot()
 world=json.loads((ROOT/'client/content/maps/00005.json').read_text());catalog=json.loads((ROOT/'client/content/catalog.json').read_text());seq=0;last_attack=0;end=time.monotonic()+160;kills=0;pickup=None
 try:
  while time.monotonic()<end:
   if select.select([s.sock],[],[],.02)[0]:s.pump()
   for event in s.events:
    if event.get('kind')=='npc_killed':
     kills+=1
     if event['player_id']==s.player_id and event['drop']['uid'] and event['drop']['amount']:pickup=dict(event['drop'])
   s.events=[]
   if pickup:
    if s.pending_moves:continue
    before=s.item_amount(pickup['id']);data=s.pickup(pickup['uid'])
    assert s.item_amount(pickup['id'])==before+pickup['amount']
    assert not any(i['uid']==pickup['uid'] for i in s.state['items'])
    assert any(e.get('kind')=='pickup' and e['uid']==pickup['uid'] for e in data['events'])
    report={'result':'passed','actual_native_kill_drop_picked_up':True,'inventory_increased_by_server_drop_amount':True,'item_id':pickup['id'],'amount':pickup['amount'],'kills_until_random_drop':kills,'original_drop_rates_unchanged':True,'fixture_only_attributes_staged':True,'database_reset':False}
    if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return
   if s.pending_moves or s.warp or s.stats.get('dead'):continue
   me=s.state['self'];targets=[n for n in s.state['npcs'] if catalog['npcs'].get(str(n['id']),{}).get('type') in (1,2,3)]
   if not targets:continue
   target=min(targets,key=lambda n:abs(n['x']-me['x'])+abs(n['y']-me['y']));delta=(target['x']-me['x'],target['y']-me['y'])
   if abs(delta[0])+abs(delta[1])==1:
    if time.monotonic()-last_attack>=.53:
     s.strike({(0,1):0,(-1,0):1,(0,-1):2,(1,0):3}[delta]);last_attack=time.monotonic()
   elif time.monotonic()-s.last_walk>=.43:
    occupied={(n['x'],n['y']) for n in s.state['npcs']}|{(c['x'],c['y']) for c in s.state['characters'] if c['player_id']!=s.player_id}
    goals=[(target['x']+dx,target['y']+dy) for dx,dy in [(0,1),(-1,0),(0,-1),(1,0)]]
    direction=next_toward((me['x'],me['y']),goals,world,occupied)
    if direction is not None:
     dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][direction];seq+=1;s.move(direction,seq,me['map_id'],me['x']+dx,me['y']+dy)
  raise AssertionError('No owned random NPC drop collected within 160 seconds (%d kills)' % kills)
 finally:s.close()
if __name__=='__main__':main()
