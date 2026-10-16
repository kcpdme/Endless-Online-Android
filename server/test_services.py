#!/usr/bin/env python3
"""Real two-client storage/trade/chat round trips through WS -> EO -> etheos.
Only fresh dev fixtures are staged; operator characters are never modified.
"""
import argparse,json,pathlib,sqlite3,time
from bootstrap_ws import load
from run import state_path
from test_online import provision,next_toward
from test_streaming import Client
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--deps-dir',type=pathlib.Path,default=ROOT/'work/server-build/python');p.add_argument('--report',type=pathlib.Path,required=True);p.add_argument('--fixture-file',type=pathlib.Path);a=p.parse_args();load(a.deps_dir)
    if a.fixture_file:fixtures=json.loads(a.fixture_file.read_text())
    else:
        fixtures=[]
        for _ in range(2):
            s,f=provision();s.close();fixtures.append(f)
        time.sleep(.6)
        with sqlite3.connect(state_path()/'runtime/database.sdb') as db:
            for i,f in enumerate(fixtures):
                assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
                db.execute('UPDATE characters SET map=90,x=2,y=?,inventory=?,goldbank=0,bank="",bankmax=0 WHERE account=? AND name=?',(2+i,'1,50000;21,5;281,2;',f['username'],f['character_name']))
    clients=[];report={'database_reset':False,'transport':'WebSocket -> gateway -> original native EO handlers'}
    def approach(client,target,distance):
        world=json.loads((ROOT/'client/content/maps/00090.json').read_text())
        deadline=time.monotonic()+35
        while time.monotonic()<deadline:
            me=client.state['player'];x,y=target()
            if abs(me['x']-x)+abs(me['y']-y)<=distance:return
            occupied={(n['x'],n['y']) for n in client.state['npcs']}|{(c['x'],c['y']) for c in client.state['players'] if c['player_id']!=me['player_id']}
            goals=[(x+dx,y+dy) for dx in range(-distance,distance+1) for dy in range(-distance,distance+1) if 0<abs(dx)+abs(dy)<=distance]
            direction=next_toward((me['x'],me['y']),goals,world,occupied)
            assert direction is not None,'No route to banker/locker'
            dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][direction]
            client.service_seq=getattr(client,'service_seq',0)+1
            seq=client.service_seq
            client.call('move',direction=direction,input_seq=seq,map_id=90,x=me['x']+dx,y=me['y']+dy)
            client.until(lambda w:w['position_seq']==seq and w['position_update'],8)
            time.sleep(.43)
        raise AssertionError('Banker/locker approach timed out')

    def held(snapshot,item):return sum(i['amount'] for i in snapshot['player']['inventory'] if i['id']==item)
    def event(client,kind,**values):
        return client.until(lambda w:any(e.get('kind')==kind and all(e.get(k)==v for k,v in values.items()) for e in w['events']),6)
    try:
        first=Client(a.url,fixtures[0]);clients.append(first);other=Client(a.url,fixtures[1]);clients.append(other)
        # Refresh is only explicit test setup for a peer that entered after us.
        first.state=first.call('refresh');pid=first.entry['player']['player_id'];oid=other.entry['player']['player_id']
        inspected=first.call('inspect_player',player_id=oid);assert inspected['player_id']==oid and len(inspected['equipment'])==15
        assert inspected['name']==other.entry['player']['name']
        report['native_other_player_paperdoll_15_slots']=True
        bank=next(n for n in first.state['npcs'] if n['id']==16)
        approach(first,lambda:next((n['x'],n['y']) for n in first.state['npcs'] if n['index']==bank['index']),2)
        data=first.call('bank_open',npc_index=bank['index']);assert data['bank']['gold']==0 and data['bank']['capacity']==25
        data=first.call('bank_deposit',amount=2000);assert held(data,1)==48000 and data['bank']['gold']==2000
        data=first.call('bank_withdraw',amount=500);assert held(data,1)==48500 and data['bank']['gold']==1500
        data=first.call('bank_upgrade');assert data['bank']['capacity']==30 and held(data,1)==47500
        report['gold_bank_native_deposit_withdraw_locker_upgrade']=True
        approach(first,lambda:(2,1),1)
        data=first.call('locker_open',x=2,y=1);assert data['locker']['items']==[]
        data=first.call('locker_deposit',item_id=21,amount=2);assert held(data,21)==3 and data['locker']['items']==[{'id':21,'amount':2}]
        data=first.call('locker_withdraw',item_id=21);assert held(data,21)==5 and data['locker']['items']==[]
        # Leave one stack stored to verify persistence in the next session.
        data=first.call('locker_deposit',item_id=281,amount=1);assert held(data,281)==1
        report['native_locker_deposit_stack_withdraw_inventory_and_weight']=True
        for channel in ('local','global','private'):
            first.worlds.clear();other.worlds.clear()
            text='EO native '+channel+' test'
            sent=first.call('chat_send',channel=channel,message=text,target=fixtures[1]['character_name'] if channel=='private' else '')
            assert any(e.get('kind')=='chat' and e.get('outgoing') and e.get('message')==text for e in sent['events'])
            event(other,'chat',channel=channel,message=text)
            time.sleep(.75)
        report['native_local_global_private_chat_two_clients']=True
        other.worlds.clear();first.call('trade_request',player_id=oid)
        other.until(lambda w:bool(w.get('trade_request')) and w['trade_request']['player_id']==pid,6)
        other.call('trade_accept',player_id=pid);first.until(lambda w:bool(w.get('trade')),6)
        before_gold=held(data,1)
        first.call('trade_add',item_id=21,amount=2);other.call('trade_add',item_id=1,amount=100)
        first.worlds.clear();other.worlds.clear()
        first.call('trade_agree',agree=True)
        other.until(lambda w:bool(w.get('trade')) and w['trade']['peer_agreed'],6)
        # Changing an offer must invalidate both agreements.
        data_other=other.call('trade_add',item_id=1,amount=120);assert not data_other['trade']['agreed'] and not data_other['trade']['peer_agreed']
        reset=first.until(lambda w:bool(w.get('trade')) and not w['trade']['agreed'] and any(i['amount']==120 for i in w['trade']['offers'].get(str(oid),[])),6)
        first.call('trade_agree',agree=True);result=other.call('trade_agree',agree=True)
        result_first=event(first,'trade_complete')
        assert held(result_first,21)==3 and held(result_first,1)==before_gold+120
        assert held(result,21)==7 and held(result,1)==49880
        report['two_sided_native_trade_offer_change_resets_approvals_and_atomic_exchange']=True
        first.worlds.clear();other.worlds.clear()
        first.call('trade_request',player_id=oid);other.until(lambda w:bool(w.get('trade_request')),6)
        other.call('trade_accept',player_id=pid);first.until(lambda w:bool(w.get('trade')),6)
        first.call('trade_add',item_id=281,amount=1);first.call('trade_cancel')
        cancelled=event(other,'trade_cancelled');assert held(cancelled,281)==2
        report['cancel_does_not_transfer_items']=True
        first.close();clients.remove(first);other.close();clients.remove(other);time.sleep(.7)
        first=Client(a.url,fixtures[0]);clients.append(first)
        assert held(first.entry,21)==3 and held(first.entry,1)==47620
        bank=next(n for n in first.entry['npcs'] if n['id']==16)
        approach(first,lambda:next((n['x'],n['y']) for n in first.state['npcs'] if n['index']==bank['index']),2)
        data=first.call('bank_open',npc_index=bank['index']);assert data['bank']['gold']==1500 and data['bank']['capacity']==30
        approach(first,lambda:(2,1),1)
        data=first.call('locker_open',x=2,y=1);assert data['locker']['items']==[{'id':281,'amount':1}]
        report['bank_locker_trade_persist_after_relogin']=True;report['result']='passed'
    finally:
        for c in clients:c.close()
    a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
