#!/usr/bin/env python3
"""Real two-session EO integration: persistent accounts, server snapshots, inventory and combat.
Creates only explicitly prefixed dev accounts/characters; never resets the database.
"""
import argparse, collections, json, os, pathlib, secrets, sqlite3, time
from eo_session import Session,EOError
from run import state_path

def dev_name():return 'dev'+''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(8))
def provision(username=None,password=None):
    username=username or dev_name();password=password or secrets.token_urlsafe(18)
    if not username.startswith('dev'):raise ValueError('Integration fixtures must have a dev-prefixed account name')
    session=Session()
    try:session.register(username,password)
    except EOError:
        if not os.environ.get('EO_TEST_USERNAME'):raise
    result=session.login(username,password)
    if not result['characters']:result=session.create_character(dev_name())
    character=result['characters'][0]
    return session,{'username':username,'password':password,'character_id':character['id'],'character_name':character['name']}

def next_toward(origin,targets,world,occupied):
    blocked={tuple(t) for t in world['blocked']};ground={(e['x'],e['y']):e['id'] for e in world['layers']['ground']};targets=set(targets)
    def valid(p):return 0<=p[0]<world['width'] and 0<=p[1]<world['height'] and p not in blocked and p not in occupied and ground.get(p,world['fill_tile'])>0
    queue=collections.deque([origin]);prev={origin:None};directions=[(0,1),(-1,0),(0,-1),(1,0)]
    found=None
    while queue:
        p=queue.popleft()
        if p in targets:found=p;break
        for d,(dx,dy) in enumerate(directions):
            q=(p[0]+dx,p[1]+dy)
            if q not in prev and valid(q):prev[q]=(p,d);queue.append(q)
    if found is None or found==origin:return None
    while prev[found][0]!=origin:found=prev[found][0]
    return prev[found][1]

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--state-dir');parser.add_argument('--report',type=pathlib.Path);parser.add_argument('--credentials-out',type=pathlib.Path)
    parser.add_argument('--skip-combat',action='store_true');a=parser.parse_args();report={'transport':'Native EO v28 to actual running etheos','database_reset':False};sessions=[]
    root=pathlib.Path(__file__).resolve().parents[1]
    try:
        first,fixture=provision(os.environ.get('EO_TEST_USERNAME'),os.environ.get('EO_TEST_PASSWORD'));sessions.append(first)
        second,other=provision();sessions.append(second)
        first.enter(fixture['character_id']);second.enter(other['character_id']);before=first.refresh()['self'];world=json.loads((root/'client/content/world.json').read_text())
        report['account_creation_login_character_welcome']=True;report['initial_map']=before['map_id'];assert before['map_id']==5
        assert ({row['id'] for row in first.inventory}|set(first.equipment.values()))>={21,80,143},'Real starting inventory missing'
        for item,slot in [(21,'weapon'),(80,'boots'),(143,'armor')]:
            if first.equipment.get(slot)!=item:first.equip(item)
        assert first.equipment['weapon']==21 and first.equipment['boots']==80 and first.equipment['armor']==143
        first.equip(21,remove=True);assert first.equipment['weapon']==0 and any(i['id']==21 for i in first.inventory)
        first.equip(21);report['server_inventory_equip_unequip']=True
        first.equip(80,remove=True);uid=first.drop(80);assert any(i['uid']==uid and i['id']==80 for i in first.state['items'])
        first.pickup(uid);assert any(i['id']==80 and i['amount']==1 for i in first.inventory);first.equip(80)
        report['ground_item_roundtrip']={'verified':True,'item_id':80,'uid':uid,'source':'Owned starter boots dropped, picked up and re-equipped through real EO acknowledgements'}
        for direction in [3,0,1,2]:
            state=first.walk(direction);after=state['self']
            if (after['x'],after['y'])!=(before['x'],before['y']):break
        assert (after['x'],after['y'])!=(before['x'],before['y']),'Server accepted no test movement'
        observer=second.refresh();observed=next(c for c in observer['characters'] if c['player_id']==first.player_id)
        assert (observed['x'],observed['y'])==(after['x'],after['y'])
        report['authoritative_movement']={'before':[before['x'],before['y']],'self_refresh':[after['x'],after['y']],'second_client_observed':[observed['x'],observed['y']]}
        report['combat']={'attempted':not a.skip_combat,'damage_confirmed':False,'kill_confirmed':False,'loot_pickup_confirmed':False}
        if not a.skip_combat:
            catalog=json.loads((root/'client/content/catalog.json').read_text());target_index=None;damage_events=[]
            for step in range(55):
                state=first.refresh();me=state['self'];npcs=[n for n in state['npcs'] if catalog['npcs'].get(str(n['id']),{}).get('type') in (1,2,3)]
                target=next((n for n in npcs if n['index']==target_index),None)
                if target is None and npcs:target=min(npcs,key=lambda n:abs(n['x']-me['x'])+abs(n['y']-me['y']));target_index=target['index']
                if not target:break
                dx,dy=target['x']-me['x'],target['y']-me['y']
                if abs(dx)+abs(dy)==1:
                    direction={(0,1):0,(-1,0):1,(0,-1):2,(1,0):3}[(dx,dy)];first.attack(direction)
                    events=[e for e in first.events if e.get('kind') in ('npc_damage','npc_killed') and e.get('player_id')==first.player_id]
                    damage_events.extend(events);first.events=[]
                    if any(e.get('kind')=='npc_killed' for e in events):break
                else:
                    occupied={(n['x'],n['y']) for n in state['npcs']}|{(c['x'],c['y']) for c in state['characters'] if c['player_id']!=first.player_id}
                    targets=[(target['x']+dx,target['y']+dy) for dx,dy in [(0,1),(-1,0),(0,-1),(1,0)]]
                    direction=next_toward((me['x'],me['y']),targets,world,occupied)
                    if direction is None:break
                    first.walk(direction)
            report['combat']['events']=damage_events;report['combat']['damage_confirmed']=any(e.get('damage',0)>0 for e in damage_events)
            report['combat']['kill_confirmed']=any(e.get('kind')=='npc_killed' for e in damage_events)
            state=first.refresh()
            if report['combat']['kill_confirmed'] and state['items']:
                item=min(state['items'],key=lambda i:abs(i['x']-state['self']['x'])+abs(i['y']-state['self']['y']))
                if abs(item['x']-state['self']['x'])+abs(item['y']-state['self']['y'])<=2:
                    try:first.pickup(item['uid']);report['combat']['loot_pickup_confirmed']=any(e.get('kind')=='pickup' for e in first.events)
                    except EOError:pass
        final=first.refresh()['self'];character_id=fixture['character_id'];first.close();second.close();sessions=[];time.sleep(0.6)
        database=state_path(a.state_dir)/'runtime/database.sdb'
        with sqlite3.connect(f'file:{database}?mode=ro',uri=True) as db:
            row=db.execute('SELECT name,map,x,y,inventory,paperdoll FROM characters WHERE name=?',(fixture['character_name'],)).fetchone()
        assert row and row[1:4]==(final['map_id'],final['x'],final['y'])
        assert row[0].startswith('dev')
        report['sqlite_persistence']={'verified':True,'map_id':row[1],'position':[row[2],row[3]],'equipped_weapon_persisted':row[5].split(',')[8]=='21'}
        report['result']='passed';report['fixtures']={'account_prefix':'dev','character_ids':[fixture['character_id'],other['character_id']]}
        if a.credentials_out:
            a.credentials_out.parent.mkdir(parents=True,exist_ok=True);a.credentials_out.write_text(json.dumps(fixture,indent=2)+'\n');a.credentials_out.chmod(0o600)
    finally:
        for s in sessions:s.close()
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
