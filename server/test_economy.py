#!/usr/bin/env python3
"""Real native shop buy/sell/craft and ground-item stream regression, using fresh dev fixtures."""
import argparse,json,pathlib,select,sqlite3,time
from eo_session import EOError
from live_session import LiveSession
from test_online import provision, next_toward
from run import state_path
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
    database=state_path(a.state_dir)/'runtime/database.sdb';sessions=[];fixtures=[]
    def new():
        s,f=provision();s.close();time.sleep(.4);fixtures.append(f);return f
    def stage(f,map_id,x,y,inventory):
        assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
        with sqlite3.connect(database) as db:
            result=db.execute('UPDATE characters SET map=?,x=?,y=?,inventory=?,hp=100 WHERE name=? AND account=?',(map_id,x,y,inventory,f['character_name'],f['username']))
            assert result.rowcount==1
    def login(f):
        s=LiveSession();characters=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in characters if c['name']==f['character_name']));s.snapshot();sessions.append(s);return s
    def pump(s,seconds=.4):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            if select.select([s.sock],[],[],max(0,end-time.monotonic()))[0]:s.pump()
    def approach(s, target):
        world=json.loads((ROOT/'client/content/maps'/('%05d.json' % s.state['map_id'])).read_text())
        end=time.monotonic()+30;seq=0
        while time.monotonic()<end:
            pump(s,.02);me=s.state['self'];x,y=target()
            if abs(me['x']-x)+abs(me['y']-y)<=2 and not s.pending_moves:return
            if s.pending_moves or time.monotonic()-s.last_walk<.43:continue
            occupied={(n['x'],n['y']) for n in s.state['npcs']}|{(n['x'],n['y']) for n in s.state['characters'] if n['player_id']!=s.player_id}
            goals=[(x+dx,y+dy) for dx in range(-2,3) for dy in range(-2,3) if 0<abs(dx)+abs(dy)<=2]
            direction=next_toward((me['x'],me['y']),goals,world,occupied)
            assert direction is not None, 'No path to native shop/drop'
            dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][direction];seq+=1
            s.move(direction,seq,me['map_id'],me['x']+dx,me['y']+dy)
        raise AssertionError('Interaction approach timed out')
    report={'database_reset':False,'runtime':'Native pinned etheos EO v28; supplied original economy'}
    try:
        f=new();g=new();stage(f,24,5,7,'1,1000;3,1;80,3;');stage(g,24,5,8,'1,0;')
        s=login(f);observer=login(g)
        if not any(n['id']==22 for n in s.state['npcs']):approach(s,lambda:(5,2))
        npc=next(n for n in s.state['npcs'] if n['id']==22)
        approach(s,lambda:(npc['x'],npc['y']))
        data=s.shop_open(npc['index']);assert data['shop']['name']=='Aeven Grocery'
        dagger=next(i for i in data['shop']['trade'] if i['id']==3);assert dagger['buy']==40 and dagger['sell']==5
        s.shop_trade('buy',3,2);assert s.item_amount(1)==920 and s.item_amount(3)==3
        s.shop_trade('sell',3,2);assert s.item_amount(1)==930 and s.item_amount(3)==1
        try:s.shop_trade('buy',3,99);raise AssertionError('Oversized purchase accepted')
        except EOError:pass
        report['original_shop_prices_buy_sell_and_quantity_guard']=True
        # The observer receives native Item_Add: item2, uid2, amount3, x1, y1.
        approach(observer,lambda:(s.state['self']['x'],s.state['self']['y']))
        uid=s.drop(80,2);pump(observer)
        ground=next(i for i in observer.state['items'] if i['uid']==uid)
        assert (ground['id'],ground['amount'],ground['x'],ground['y'])==(80,2,s.state['self']['x'],s.state['self']['y']),ground
        try:observer.pickup(uid);raise AssertionError('Protected player drop was stolen')
        except EOError:pass
        assert observer.item_amount(80)==0
        before=s.item_amount(80);data=s.pickup(uid)
        assert s.item_amount(80)==before+2 and not any(i['uid']==uid for i in s.state['items'])
        assert any(e.get('kind')=='pickup' for e in data['events'])
        assert data['player']['stats']['weight']==s.weight
        pump(observer);assert not any(i['uid']==uid for i in observer.state['items'])
        report['ground_item_add_exact_fields_owner_pickup_stack_weight_and_observer_remove']=True
        report['native_drop_protection_enforced']=True
        s.close();sessions.remove(s);observer.close();sessions.remove(observer);time.sleep(.5)
        s=login(f);assert s.item_amount(1)==930 and s.item_amount(3)==1 and s.item_amount(80)==3
        report['shop_and_pickup_persist_after_relogin']=True
        s.close();sessions.remove(s);time.sleep(.5)
        stage(f,193,6,3,'1,1000;258,2;');s=login(f)
        npc=next(n for n in s.state['npcs'] if n['id']==100)
        approach(s,lambda:(npc['x'],npc['y']))
        data=s.shop_open(npc['index']);assert any(i['id']==21 for i in data['shop']['craft'])
        s.shop_trade('craft',21);assert s.item_amount(258)==0 and s.item_amount(21)==1 and s.item_amount(1)==1000
        try:s.shop_trade('craft',21);raise AssertionError('Craft without ingredients accepted')
        except EOError:pass
        report['original_cyndi_crafting_consumes_ingredients_and_requires_them']=True
        report['result']='passed'
    finally:
        for s in sessions:s.close()
    if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
