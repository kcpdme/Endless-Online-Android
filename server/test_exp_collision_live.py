#!/usr/bin/env python3
"""Real native kill rewards, config rehash and explicit player ghosting in isolation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import select
import shutil
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time
from configure_balance import decode_item, records
from configure_rates import configure
from eo_session import Session, number
from live_session import LiveSession
from test_online import dev_name


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--binary',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    checks=0
    def check(ok,why):
        nonlocal checks
        assert ok,why
        checks+=1
    with tempfile.TemporaryDirectory(prefix='aster-exp-collision-') as temp:
        root=Path(temp);r=root/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','etheos-v*'));shutil.copy2(a.binary,r/'etheos')
        os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18974\nExpRate = 100%\nIPReconnectLimit = 0\n')
        # Two stationary, ordinary 5-EXP Crows exist only in this private room.
        mp=r/'data/maps/00021.emf';raw=bytearray(mp.read_bytes());raw[43:45]=number(0,1)*2
        count=raw[46]-1;assert count==0
        spawn=b''.join(number(x,1)+number(y,1)+number(1,2)+number(7,1)+number(180,2)+number(1,1) for x,y in [(10,7),(9,8)])
        mp.write_bytes(raw[:46]+number(2,1)+spawn+raw[47:])
        island=r/'data/maps/00194.emf';island_raw=island.read_bytes();count=island_raw[46]-1
        goat=number(7,1)+number(43,1)+number(7,2)+number(7,1)+number(180,2)+number(1,1)
        island.write_bytes(island_raw[:46]+number(1,1)+goat+island_raw[47+count*8:])
        pub=(r/'data/pub/dat001.eif').read_bytes();dagger=decode_item(records(pub,b'EIF',58)[20]);check((dagger['min_damage'],dagger['max_damage'])==(1,2),'Dagger remains exactly 1-2')
        untouched={f:hashlib.sha256((r/f).read_bytes()).hexdigest() for f in ['data/pub/dat001.eif','data/pub/dtn001.enf','data/aster-vale-drops.ini']}
        log=(root/'native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT);clients=[]
        def pump(s,seconds=.1):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                s.poll_actions()
                if select.select([s.sock],[],[],.02)[0]:s.pump()
        def moved(s,direction,seq,x,y,ghost=False):
            s.move(direction,seq,21,x,y,ghost=ghost)
            until=time.monotonic()+5
            while s.pending_moves and time.monotonic()<until:pump(s)
            check(not s.pending_moves,'Native movement answered')
            return (s.state['self']['x'],s.state['self']['y'])
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18974),timeout=.1):break
                except OSError:time.sleep(.1)
            time.sleep(.8)
            fixtures=[]
            for x,y in [(10,8),(11,8),(9,9),(11,9)]:
                f={'username':dev_name(),'password':secrets.token_urlsafe(18),'name':dev_name(),'x':x,'y':y};s=Session(port=18974)
                try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
                finally:s.close()
                fixtures.append(f)
            time.sleep(.8)
            with sqlite3.connect(r/'database.sdb') as db:
                for f in fixtures:db.execute('UPDATE characters SET map=21,x=?,y=?,class=6,level=10,exp=133100,"str"=40,agi=100,"con"=40,hp=500,tp=100,inventory="",paperdoll="" WHERE name=? AND account=?',(f['x'],f['y'],f['name'],f['username']))
            for f in fixtures:
                s=LiveSession('127.0.0.1',18974);clients.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot()
            first,other,racer,opponent=clients
            check(moved(first,3,1,11,8)==(10,8),'Normal movement cannot enter another player')
            check(moved(first,3,2,11,8,True)==(10,8),'Early ghost is rejected by the native timer')
            time.sleep(5.1)
            check(moved(first,3,3,11,8)==(10,8),'Standing idle never makes a normal walk pass through')
            check(moved(first,3,4,11,8,True)==(11,8),'Explicit ghost succeeds after the timer')
            moved(first,1,5,10,8)
            # Competing moves into the same empty tile are resolved serially by native occupancy.
            racer.move(3,1,21,10,9);opponent.move(1,1,21,10,9)
            for s in (racer,opponent):
                until=time.monotonic()+5
                while s.pending_moves and time.monotonic()<until:pump(s)
            positions=[(s.state['self']['x'],s.state['self']['y']) for s in (racer,opponent)]
            check(len(set(positions))==2 and positions.count((10,9))==1,'Two walkers cannot claim one tile even after standing idle: '+str(positions))
            before=first.stats['experience']
            for _ in range(6):
                first.attack(2);pump(first,.2)
                if first.stats['experience']>before:break
            one=first.stats['experience']-before;check(one==5,'Original Crow grants 5 EXP at x1')
            configure(r);identity=first.player_id;os.kill(proc.pid,signal.SIGHUP);pump(first,.9)
            before=first.stats['experience']
            for _ in range(6):
                first.attack(1);pump(first,.2)
                if first.stats['experience']>before:break
            two=first.stats['experience']-before;check(two==10,'Same original Crow grants 10 EXP at x2 after rehash: '+str(two))
            check(first.player_id==identity and proc.poll() is None,'Rehash preserves the live native connection')
            check(all(hashlib.sha256((r/f).read_bytes()).hexdigest()==sha for f,sha in untouched.items()),'No item, original NPC EXP or drop table changed')
            # Actual newborns, one attacker, one non-attacking member on Newbie Island.
            babies=[]
            for _ in range(2):
                f={'username':dev_name(),'password':secrets.token_urlsafe(18),'name':dev_name()}
                s=Session(port=18974)
                try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
                finally:s.close()
                babies.append(f)
            time.sleep(.8)
            with sqlite3.connect(r/'database.sdb') as db:
                for i,f in enumerate(babies):db.execute('UPDATE characters SET map=194,x=?,y=44,inventory="21,1;" WHERE name=? AND account=?',(7+i,f['name'],f['username']))
            party=[]
            for f in babies:
                s=LiveSession('127.0.0.1',18974);clients.append(s);party.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot()
                check(s.stats['level']==0 and s.stats['class_id']==0,'Fresh newborn remains original level-zero Peasant')
            hunter,member=party
            hunter.refresh();member.refresh();hunter.equip(21)
            hunter.party_action('invite',member.player_id)
            until=time.monotonic()+5
            while not member.party_invitation and time.monotonic()<until:pump(member)
            check(bool(member.party_invitation),'Native Newbie Island party invitation delivered')
            member.party_action('accept')
            for s in party:
                until=time.monotonic()+5
                while len(s.party_members)!=2 and time.monotonic()<until:pump(s)
                check(len(s.party_members)==2,'Both newborns have the native party roster')
            before=[s.stats['experience'] for s in party]
            for _ in range(30):
                hunter.attack(2)
                for s in party:pump(s,.1)
                if all(s.stats['experience']>n for s,n in zip(party,before)):break
            gains=[s.stats['experience']-n for s,n in zip(party,before)]
            check(gains==[8,8],'Goat EXP is shared with the non-attacking level-zero member: '+str(gains))
            for s in party:s.close();clients.remove(s)
            time.sleep(.8)
            with sqlite3.connect(r/'database.sdb') as db:
                saved=[db.execute('SELECT exp FROM characters WHERE name=?',(f['name'],)).fetchone()[0] for f in babies]
            check(saved==[8,8],'Both newborn EXP shares persist in the native database')
            report={'result':'passed','checks':checks,'crow_exp_x1':one,'crow_exp_x2':two,'dagger_damage':[1,2],'normal_idle_collision_blocked':True,'early_ghost_rejected':True,'timed_explicit_ghost_accepted':True,'competing_walks_distinct_tiles':True,'config_rehash_preserves_live_session':True,'isolated_database':True,'newbie_party_levels':[0,0],'newbie_goat_party_exp':gains,'non_attacking_member_rewarded':True,'both_shares_persisted':True}
            a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
        finally:
            for s in clients:s.close()
            if proc.poll() is None:
                proc.send_signal(signal.SIGINT)
                try:proc.wait(timeout=25)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            log.close()


if __name__=='__main__':main()
