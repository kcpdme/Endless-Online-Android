#!/usr/bin/env python3
"""Party EXP and native level/stat-point persistence after an actual monster kill."""
import argparse,json,pathlib,sqlite3,time
from bootstrap_ws import load
from test_streaming import Client
from test_online import provision
from run import state_path

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8184/ws');p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args();load(pathlib.Path('work/server-build/python'))
 fs=[]
 for _ in range(2):s,f=provision();s.close();fs.append(f)
 time.sleep(.7)
 with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
  for i,f in enumerate(fs):
   assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
   db.execute('UPDATE characters SET map=5,x=40,y=?,level=1,exp=1064,"str"=3000,agi=3000,"con"=1000,wis=1000,hp=10000,tp=10000,statpoints=0,skillpoints=0,spells=? WHERE account=? AND name=?',(40+i,'9,3;',f['username'],f['character_name']))
 first,second=[Client(a.url,f) for f in fs]
 try:
  pid=second.entry['player']['player_id'];first.call('party_invite',player_id=pid);second.until(lambda w:w.get('party_invitation'));second.call('party_accept')
  for c in (first,second):c.until(lambda w:len(w.get('party',[]))==2);c.worlds.clear()
  target=next(n for n in first.state['npcs'] if n['id']==2)
  first.call('spell_cast',spell_id=9,target_kind='npc',target_id=target['index'])
  for c in (first,second):c.until(lambda w:any(e.get('kind')=='party_exp' and e.get('exp_gain',0)>0 for e in w.get('events',[])),15)
  # Read the full native Refresh after the level-up notification has been pumped.
  time.sleep(.5)
  records=[c.call('refresh')['player'] for c in (first,second)]
  assert all(r['level']==2 and r['stats']['stat_points']==3 and r['stats']['skill_points']==3 for r in records),[(r['level'],r['stats']['experience'],r['stats']['stat_points'],r['stats']['skill_points']) for r in records]
 finally:first.close();second.close()
 time.sleep(.8)
 with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
  for f,r in zip(fs,records):
   saved=db.execute('SELECT exp,level,statpoints,skillpoints FROM characters WHERE account=? AND name=?',(f['username'],f['character_name'])).fetchone()
   assert saved==(r['stats']['experience'],r['level'],r['stats']['stat_points'],r['stats']['skill_points']),(saved,r['stats'])
 report=dict(result='passed',native_monster_kill=True,both_party_members_gained_exp=True,both_native_level_ups=True,native_stat_and_skill_points_match_saved_database=True,client_exp_totals_match_native_database=True,dev_accounts_only=True)
 a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
