#!/usr/bin/env python3
"""Actual native parties, healing and bard broadcasts with isolated dev characters."""
import argparse,json,pathlib,sqlite3,time
from test_online import provision
from test_streaming import Client
from run import state_path
from bootstrap_ws import load

def fixtures():
 result={}
 for role in ('leader','member','third','outsider'):
  s,f=provision();s.close();result[role]=f
 time.sleep(.7)
 with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
  for i,f in enumerate(result.values()):
   assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
   doll=[0]*15
   if i==0:doll[8]=349
   db.execute('UPDATE characters SET map=90,x=?,y=3,level=50,exp=16637500,"int"=100,wis=1000,"con"=100,hp=1,tp=30000,spells=?,inventory=?,paperdoll=? WHERE account=? AND name=?',(2+i,';'.join(str(j)+',3' for j in range(1,32))+';','1,1000;350,1;',','.join(map(str,doll)),f['username'],f['character_name']))
 return result

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture',type=pathlib.Path);p.add_argument('--fixtures-out',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args();load(pathlib.Path('work/server-build/python'))
 fs=json.loads(a.fixture.read_text()) if a.fixture else fixtures()
 if a.fixtures_out:a.fixtures_out.write_text(json.dumps(fs));a.fixtures_out.chmod(0o600)
 clients={k:Client(a.url,f) for k,f in fs.items()};leader,member,third,outsider=[clients[k] for k in ('leader','member','third','outsider')]
 pid=lambda c:c.entry['player']['player_id']
 report={}
 def wait(c,predicate):return c.until(predicate,12)
 def state(c):
  data=c.call('refresh');c.state.update(data);return data
 def clear():
  for c in clients.values():c.worlds.clear()
 def rejected(c,op,**fields):
  c.serial+=1;sid=c.serial;c.ws.send(json.dumps(dict(id=sid,op=op,**fields)))
  while True:
   r=json.loads(c.ws.recv(timeout=20))
   if r.get('id')==sid:assert not r['ok'];return
 def cast(ident,target='group',target_id=0):
  clear();before=state(leader)['player'];leader.call('spell_cast',spell_id=ident,target_kind=target,target_id=target_id)
  world=wait(leader,lambda w:any(e.get('spell_id')==ident and e.get('kind') in ('spell_heal','spell_group') for e in w.get('events',[])))
  return before,world
 try:
  assert not leader.entry['party']
  leader.call('party_invite',player_id=pid(member));wait(member,lambda w:bool(w.get('party_invitation')));member.call('party_accept')
  for c in (leader,member):wait(c,lambda w:len(w.get('party',[]))==2)
  report['native_invite_accept_two_member_party']=True
  third.call('party_join',player_id=pid(leader));wait(leader,lambda w:bool(w.get('party_invitation')));leader.call('party_accept')
  for c in (leader,member,third):wait(c,lambda w:len(w.get('party',[]))==3)
  report['native_ask_join_accept_three_members']=True
  rejected(member,'party_kick',player_id=pid(leader));rejected(leader,'party_kick',player_id=pid(outsider));report['nonleader_and_outsider_removal_rejected']=True
  clear();member.call('chat_send',channel='party',message='Party hello')
  for c in (leader,third):wait(c,lambda w:any(e.get('channel')=='party' and e.get('message')=='Party hello' for e in w.get('events',[])))
  report['native_party_chat']=True
  for ident,cost in [(3,20),(18,4)]:
   initial={k:state(c)['player']['hp'] for k,c in clients.items()}
   before,w=cast(ident);assert w['player']['tp']==before['tp']-cost
   event=next(e for e in w['events'] if e.get('kind')=='spell_group' and e.get('spell_id')==ident)
   assert {r['player_id'] for r in event['targets']}=={pid(c) for c in (leader,member,third)}
   for c in (member,third):wait(c,lambda w:any(e.get('kind')=='spell_group' and e.get('spell_id')==ident for e in w.get('events',[])))
   assert all(state(clients[k])['player']['hp']>initial[k] for k in ('leader','member','third'))
   assert state(outsider)['player']['hp']==initial['outsider']
  report['group_heal_and_aura_native_hp_tp_all_members_not_outsider']=True
  heals=[]
  for ident,cost,target in [(2,3,leader),(6,2,member),(7,7,leader),(8,24,leader),(11,1,leader),(13,1,leader),(20,10,leader),(22,0,leader),(28,0,leader),(30,0,leader)]:
   before,w=cast(ident,'player',pid(target));event=next(e for e in w['events'] if e.get('kind')=='spell_heal' and e.get('spell_id')==ident)
   assert event['target_id']==pid(target)
   # Native Recover_Player follows the heal effect and owns the actual caster TP.
   wait(leader,lambda w:w.get('player',{}).get('tp')==before['tp']-cost)
   if target is member:wait(member,lambda w:any(e.get('kind')=='spell_heal' and e.get('spell_id')==ident for e in w.get('events',[])))
   heals.append(ident);time.sleep(.55)
  report['native_targeted_heals_self_and_other_ids']=heals
  for instrument,weapon in [(49,349),(50,350)]:
   if weapon==350:
    leader.call('unequip',item_id=349);leader.call('equip',item_id=350)
   for note in (0,12,35):
    clear();data=leader.call('bard_note',note=note);assert any(e.get('kind')=='bard_note' and e['note']==note for e in data['events'])
    wait(member,lambda w:any(e.get('kind')=='bard_note' and e.get('instrument')==instrument and e.get('note')==note for e in w.get('events',[])))
    time.sleep(.16)
  report['harp_and_guitar_native_observer_notes_low_mid_high']=True
  clear();leader.call('party_kick',player_id=pid(third));wait(third,lambda w:not w.get('party'));wait(leader,lambda w:len(w.get('party',[]))==2)
  report['leader_remove_third_native']=True
  clear();member.call('party_leave')
  for c in (leader,member):wait(c,lambda w:not w.get('party'))
  rejected(leader,'spell_cast',spell_id=3,target_kind='group');report['two_member_leave_disbands_and_group_cast_rejected']=True
  report.update(result='passed',native_world=True,dev_fixtures_only=True,operator_accounts_modified=False)
 finally:
  for c in clients.values():c.close()
 a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
