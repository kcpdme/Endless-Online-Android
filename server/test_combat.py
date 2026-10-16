#!/usr/bin/env python3
"""Real native combat, stats allocation, equipment bonuses and death/respawn regression.
Only a fresh dev fixture is staged; no world damage/stat formulas are changed.
"""
import argparse,json,pathlib,select,sqlite3,time
from live_session import LiveSession
from test_online import provision,next_toward
from run import state_path

ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);p.add_argument('--content-dir',type=pathlib.Path,default=ROOT/'client/content');a=p.parse_args()
    base,f=provision();base.close();time.sleep(.6);database=state_path(a.state_dir)/'runtime/database.sdb'
    def stage(**fields):
        assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
        assert set(fields)<={'str','int','wis','agi','con','cha','statpoints','hp'}
        with sqlite3.connect(database) as db:
            assert db.execute('SELECT account FROM characters WHERE name=?',(f['character_name'],)).fetchone()[0]==f['username']
            db.execute('UPDATE characters SET '+','.join('"'+k+'"=?' for k in fields)+' WHERE name=? AND account=?',(*fields.values(),f['character_name'],f['username']))
    stage(str=2,int=3,wis=7,agi=5,con=6,cha=9,statpoints=2,hp=30)
    def login():
        s=LiveSession();chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['character_name']));s.snapshot();return s
    s=login();report={'runtime':'Real native EO v28 / pinned etheos','database_reset':False}
    try:
        assert all(s.stats[k]==v for k,v in zip(('strength','intelligence','wisdom','agility','constitution','charisma'),(2,3,7,5,6,9))),s.stats
        s.spend_stat(2);assert s.stats['intelligence']==4 and s.stats['wisdom']==7 and s.stats['stat_points']==1
        report['welcome_attribute_order_and_native_point_allocation']=True
        items=json.loads((a.content_dir/'catalog.json').read_text())['items'];before=dict(s.stats)
        s.equip(21);assert s.stats['min_damage']==before['min_damage']+items['21']['min_damage'] and s.stats['max_damage']==before['max_damage']+items['21']['max_damage']
        s.equip(143);assert s.stats['armor']==before['armor']+items['143']['armor']
        s.equip(143,remove=True);assert s.stats['armor']==before['armor']
        s.equip(21,remove=True);report['equipment_damage_armor_totals_and_unequip']=True
        s.close();time.sleep(.6);s=login();assert s.stats['intelligence']==4 and s.stats['stat_points']==1;report['allocated_point_persisted']=True
        world=json.loads((a.content_dir/'world.json').read_text());catalog=json.loads((a.content_dir/'catalog.json').read_text())
        events=[];sent=[];seq=0;last_attack=0;target_index=None
        def pump(seconds):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                if select.select([s.sock],[],[],max(0,end-time.monotonic()))[0]:s.pump()
            events.extend(s.events);s.events=[]
        def engage(timeout,stop):
            nonlocal seq,last_attack,target_index
            end=time.monotonic()+timeout
            while time.monotonic()<end:
                pump(.02)
                if stop():return True
                if s.warp or s.stats.get('dead'):
                    pump(.05);continue
                me=s.state['self'];targets=[n for n in s.state['npcs'] if catalog['npcs'].get(str(n['id']),{}).get('type') in (1,2,3)]
                target=next((n for n in targets if n['index']==target_index),None)
                if not target and targets:target=min(targets,key=lambda n:abs(n['x']-me['x'])+abs(n['y']-me['y']));target_index=target['index']
                if not target:continue
                delta=(target['x']-me['x'],target['y']-me['y'])
                if abs(delta[0])+abs(delta[1])==1 and not s.pending_moves:
                    if time.monotonic()-last_attack>=.52:
                        direction={(0,1):0,(-1,0):1,(0,-1):2,(1,0):3}[delta]
                        # Check authoritative NPC blocking without sending a native walk.
                        seq+=1;receipt=s.move(direction,seq,me['map_id'],target['x'],target['y']);assert receipt.get('blocked')=='npc' and not s.pending_moves
                        t=time.monotonic();s.strike(direction);sent.append(time.monotonic());assert time.monotonic()-t<.05,'Attack path blocked instead of returning immediately';last_attack=sent[-1]
                elif not s.pending_moves and time.monotonic()-s.last_walk>=.42:
                    occupied={(n['x'],n['y']) for n in s.state['npcs']}|{(c['x'],c['y']) for c in s.state['characters'] if c['player_id']!=s.player_id}
                    goals=[(target['x']+dx,target['y']+dy) for dx,dy in [(0,1),(-1,0),(0,-1),(1,0)]]
                    direction=next_toward((me['x'],me['y']),goals,world,occupied)
                    if direction is not None:
                        dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][direction];seq+=1;s.move(direction,seq,me['map_id'],me['x']+dx,me['y']+dy)
            return False
        ok=engage(75,lambda:len(sent)>=5 and any(e.get('kind')=='npc_damage' and e.get('damage',0)>0 for e in events) and any(e.get('kind')=='player_damage' and e.get('damage',0)>0 for e in events))
        assert ok,{'strikes':len(sent),'hits':[(e.get('kind'),e.get('damage')) for e in events if e.get('kind') in ('npc_damage','player_damage')]}
        gaps=[round(b-a,3) for a,b in zip(sent,sent[1:]) if b-a<.8];assert gaps and min(gaps)>=.50
        report.update(authoritative_npc_collision=True,nonblocking_half_second_attacks=True,observed_adjacent_strike_intervals_seconds=gaps,npc_damage_to_player=True,player_damage_to_npc=True)
        s.close();time.sleep(.6);stage(hp=1);s=login();events.clear();seq=0;target_index=None
        assert engage(75,lambda:any(e.get('kind')=='player_damage' and e.get('dead') for e in events)), 'Expected real NPC retaliation/death'
        assert s.stats['dead'] and s.state['self']['hp']==0
        assert not s.strike(0)['sent'];report['dead_input_blocked_and_hp_zero']=True
        death_time=time.monotonic()
        assert engage(12,lambda:any(e.get('kind')=='map_transition' and e.get('reason')=='death_respawn' for e in events)), 'Expected server death-respawn warp'
        assert not s.stats['dead'] and s.state['self']['hp']>0, 'Respawn must restore positive native HP'
        assert s.state['self']['hp']==int(s.state['self']['maxhp']*.5), 'Expected 50 percent native death recovery'
        report.update(respawn_hp=s.state['self']['hp'],respawn_max_hp=s.state['self']['maxhp'],death_respawn_verified=True,observed_respawn_delay_seconds=round(time.monotonic()-death_time,3),respawn_map=s.state['map_id'],respawn_position=[s.state['self']['x'],s.state['self']['y']],result='passed')
    finally:s.close()
    if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
