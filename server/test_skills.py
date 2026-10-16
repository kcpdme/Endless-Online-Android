#!/usr/bin/env python3
"""Real native skill-master, timed casting and observer integration; fresh dev fixtures only."""
import argparse,json,pathlib,sqlite3,time
from test_online import provision,next_toward
from test_streaming import Client
from bootstrap_ws import load
from run import state_path

def fixtures():
    result={}
    for role in ('actor','observer','master'):
        s,f=provision();s.close();result[role]=f
    time.sleep(.7)
    with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
        for role,f in result.items():
            assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
            mid,x,y=(156,5,7) if role=='master' else (5,40,40 if role=='actor' else 41)
            db.execute('UPDATE characters SET map=?,x=?,y=?,level=50,exp=16637500,"str"=0,"int"=20,wis=100,agi=500,"con"=100,hp=1,tp=32000,spells=?,skillpoints=10,inventory=?,paperdoll=? WHERE account=? AND name=?',(mid,x,y,'4,0;5,0;' if role=='master' else '1,0;4,0;5,0;','1,5000;2,10;3,10;','0,0,0,0,0,0,0,0,0,0,0,0,0,0,0',f['username'],f['character_name']))
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--fixtures-out',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args();load(pathlib.Path(__file__).resolve().parents[1]/'work/server-build/python')
    fs=json.loads(a.fixture_file.read_text()) if a.fixture_file else fixtures()
    if a.fixtures_out:a.fixtures_out.write_text(json.dumps(fs));a.fixtures_out.chmod(0o600)
    actor=Client(a.url,fs['actor']);observer=Client(a.url,fs['observer']);teacher=Client(a.url,fs['master']);clients=[actor,observer,teacher];report={}
    try:
        assert {s['id'] for s in actor.entry['player']['spells']}>={1,4,5}
        world=json.loads((pathlib.Path(__file__).resolve().parents[1]/'client/content/maps/00156.json').read_text())
        world['blocked']=world['server_blocked']
        for step in range(30):
            me=teacher.state['player'];master=next((n for n in teacher.state['npcs'] if n['id']==116),None)
            if master and abs(master['x']-me['x'])+abs(master['y']-me['y'])<=2:break
            targets=({(master['x']+dx,master['y']+dy) for dx in range(-2,3) for dy in range(-2,3) if 0<abs(dx)+abs(dy)<=2} if master else {(5,7)})
            direction=next_toward((me['x'],me['y']),targets,world,{(n['x'],n['y']) for n in teacher.state['npcs']})
            assert direction is not None,'No skill-master path'
            dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][direction]
            teacher.worlds.clear();teacher.call('move',direction=direction,input_seq=step+1,map_id=156,x=me['x']+dx,y=me['y']+dy)
            teacher.until(lambda w:w.get('position_seq')==step+1)
            time.sleep(.43)
        data=teacher.call('skillmaster_open',npc_index=master['index']);offers=data['skillmaster']['offers'];assert [o['id'] for o in offers]==[1,2,7]
        assert next(o['cost'] for o in offers if o['id']==1)==100
        before_gold=next(i['amount'] for i in teacher.entry['player']['inventory'] if i['id']==1)
        data=teacher.call('skill_learn',spell_id=1);assert any(s['id']==1 for s in data['player']['spells']);assert next(i['amount'] for i in data['player']['inventory'] if i['id']==1)==before_gold-100
        data=teacher.call('skill_level',spell_id=1);assert next(s['level'] for s in data['player']['spells'] if s['id']==1)==1
        data=teacher.call('skill_forget',spell_id=1);assert not any(s['id']==1 for s in data['player']['spells'])
        report['native_skillmaster_original_prices_learn_train_forget']=True
        hp,tp=actor.entry['player']['hp'],actor.entry['player']['tp'];actor.worlds.clear();observer.worlds.clear()
        before=time.monotonic();receipt=actor.call('spell_cast',spell_id=1,target_kind='self');elapsed=time.monotonic()-before
        assert receipt['seconds']==.48
        # Wire RTT is not chant blocking; the state regression separately measures
        # cast_spell returning immediately without native socket waits or sleeps.
        report['cast_receipt_roundtrip_ms']=round(elapsed*1000)
        actor.until(lambda w:any(e.get('kind')=='spell_heal' for e in w.get('events',[])))
        assert actor.state['player']['hp']>hp and actor.state['player']['tp']==tp-1
        observer.until(lambda w:any(e.get('kind')=='spell_chant' and e.get('spell_id')==1 for e in w.get('events',[])))
        observer.until(lambda w:any(e.get('kind')=='spell_heal' for e in w.get('events',[])))
        report['self_heal_hp_tp_and_observer_native_chant_effect']=True
        time.sleep(.7);actor.worlds.clear()
        actor.call('spell_cast',spell_id=4,target_kind='npc',target_id=next(n['index'] for n in actor.state['npcs'] if n['id']==2))
        tp=actor.state['player']['tp'];actor.call('spell_cancel');actor.until(lambda w:any(e.get('kind')=='spell_cancelled' for e in w.get('events',[])))
        time.sleep(1.1);assert actor.state['player']['tp']==tp
        report['cancel_chant_without_spending_tp']=True
        damage=[]
        for i in range(15):
            actor.worlds.clear();observer.worlds.clear()
            target=next((n for n in actor.state['npcs'] if n['id']==2),None)
            if not target:break
            actor.call('spell_cast',spell_id=4,target_kind='npc',target_id=target['index'])
            world=actor.until(lambda w:any(e.get('kind') in ('npc_damage','npc_killed') and e.get('spell_id')==4 for e in w.get('events',[])),8)
            event=next(e for e in world['events'] if e.get('kind') in ('npc_damage','npc_killed') and e.get('spell_id')==4);damage.append(event)
            observer.until(lambda w:any(e.get('spell_id')==4 and e.get('kind') in ('npc_damage','npc_killed') for e in w.get('events',[])),8)
            if event['kind']=='npc_killed':break
            time.sleep(.75)
        assert any(e.get('damage',0)>0 for e in damage),damage
        assert any(e['kind']=='npc_killed' for e in damage),damage
        assert actor.state['player']['tp']<=tp-len(damage)
        assert actor.state['player']['stats']['experience']>16637500
        report['native_spell_damage_kill_exp_and_peer_effect']=True
        report['cast_count_until_kill']=len(damage)
        report['no_per_cast_world_refresh']=actor.call('diagnostics')['refreshes']==0
        assert report['no_per_cast_world_refresh']
        report['result']='passed';report['transport']='WebSocket -> live adapter -> pinned native etheos';report['operator_accounts_used']=False
    finally:
        for c in clients:c.close()
    a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
