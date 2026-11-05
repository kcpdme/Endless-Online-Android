#!/usr/bin/env python3
"""Pet reachability/facing, NPC collision and packet latency on a disposable native world."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time
from pathlib import Path
from eo_session import Session,number
from live_session import LiveSession
from configure_sky_wonder import parse,grid
from configure_balance import records,encode_pub,put
from test_online import dev_name

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=Path,required=True);p.add_argument('--binary',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True);p.add_argument('--baseline',action='store_true');a=p.parse_args()
    checks={};timings={};sessions=[]
    def check(ok,name):
        checks[name]=bool(ok)
        if not ok and not a.baseline:raise AssertionError(name)
    with tempfile.TemporaryDirectory(prefix='aster-pet-response-') as temp:
        r=Path(temp)/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','etheos*'))
        shutil.copy2(a.binary,r/'etheos');os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18979\nIPReconnectLimit = 0\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nCriticalFirstHit = no\nCriticalRate = 0\n')
        pub=r/'data/pub/dtn001.enf';raw=pub.read_bytes();rows=records(raw,b'ENF',39)
        for ident in (1,74,101,119):
            put(rows[ident-1]['fields'],11,500000,3)
        put(rows[73]['fields'],7,2,2) # Stationary aggressive threat, independent of original Wolf role.
        pub.write_bytes(encode_pub(raw,rows))
        # Keep the real map geometry in a private copy; clear a controlled room.
        prefix,g,_=parse((r/'data/maps/00021.emf').read_bytes());prefix=bytearray(prefix[:46]);prefix[31:32]=number(0,1);prefix[43:45]=number(0,1)*2
        for x in range(2,19):
            for y in range(2,13):g['specs'].pop((x,y),None);g['warps'].pop((x,y),None)
        def room(mid,spawns,walls=()):
            import copy
            grids=copy.deepcopy(g)
            for x,y in walls:grids['specs'][x,y]=number(0,1)
            spawn=b''.join(number(x,1)+number(y,1)+number(ident,2)+number(7,1)+number(180,2)+number(1,1) for ident,x,y in spawns)
            data=prefix+number(len(spawns),1)+spawn+number(0,1)*2
            (r/f'data/maps/{mid:05d}.emf').write_bytes(data+b''.join(grid(c) for c in grids.values())+number(0,1))
        for mid,(x,y) in zip((21,22,24,26),((7,8),(6,7),(7,6),(8,7))):room(mid,[(74,x,y)])
        room(27,[(119,11,8),(119,10,8),(119,12,8),(119,11,7),(119,11,9)])
        room(28,[(74,9,7)],[(8,7),(7,6)])
        room(29,[(1,9,8)])
        room(30,[(101,11,8)])
        room(31,[(1,9,8)])
        log=a.report.with_suffix('.log');log.parent.mkdir(parents=True,exist_ok=True)
        stream=log.open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=stream,stderr=subprocess.STDOUT)
        def pump(s,seconds=.04):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                s.poll_actions()
                if select.select([s.sock],[],[],min(.01,max(0,end-time.monotonic())))[0]:s.pump()
        def until(s,pred,timeout=5):
            end=time.monotonic()+timeout
            while time.monotonic()<end:
                if pred():return True
                pump(s)
            return bool(pred())
        def stage(mid,clas=7):
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());s=Session(port=18979)
            s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name']);s.close();time.sleep(.1)
            gear=[0]*15;gear[8]=457 if clas==5 else 494;gear[7]=423 if clas==5 else 0
            with sqlite3.connect(r/'database.sdb') as db:
                db.execute('UPDATE characters SET map=?,x=8,y=8,direction=3,class=?,level=50,hp=30000,tp=30000,"str"=50,"int"=50,wis=50,agi=100,"con"=100,cha=50,paperdoll=?,inventory="249,5;",spells="23,0;61,0;51,0;" WHERE name=?',(mid,clas,','.join(map(str,gear)),f['name']))
            s=LiveSession('127.0.0.1',18979);sessions.append(s);chars=s.login(f['username'],f['password'])['characters'];s.enter(chars[0]['id']);s.snapshot();pump(s,.15);return s
        def close(s):s.close();sessions.remove(s)
        def summon(s,spell=61):
            s.cast_spell(spell,'self');return until(s,lambda:bool(getattr(s,'companion',None)),4)
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18979),timeout=.1):break
                except OSError:time.sleep(.05)
            time.sleep(.5)
            for mid,direction in zip((21,22,24,26),range(4)):
                s=stage(mid);check(summon(s),'banshi_summons_'+str(direction))
                hit=until(s,lambda:any(e.get('kind')=='companion_attack' for e in s.events),2)
                if not hit:print('PET DEBUG',mid,s.stats.get('class_id'),s.stats.get('hp'),getattr(s,'companion',None),s.state['npcs'],s.events[-6:],flush=True)
                check(hit,'autonomous_aggressive_attack_'+str(direction))
                attacks=[e for e in s.events if e.get('kind')=='companion_attack']
                check(bool(attacks) and attacks[-1].get('direction')==direction,'banshi_faces_target_'+str(direction));close(s)
            s=stage(27);summon(s,51);pump(s,1.3)
            check(not any(e.get('kind')=='companion_attack' for e in s.events),'unprovoked_passive_tentacles_ignored')
            center=next(n for n in s.state['npcs'] if (n['x'],n['y'])==(11,8))
            s.cast_spell(23,'npc',center['index']);pump(s,1)
            check(until(s,lambda:any(e.get('kind')=='companion_attack' and e.get('target_index')!=center['index'] for e in s.events),6),'blocked_command_attacks_reachable_tentacle');close(s)
            s=stage(28);summon(s)
            check(until(s,lambda:any(e.get('kind')=='companion_attack' for e in s.events),6),'pet_detours_around_wall');close(s)
            s=stage(29);s.move(3,1,29,9,8);until(s,lambda:not s.pending_moves)
            check(s.state['self']['x']==8,'normal_walk_cannot_overlap_npc')
            s.move(3,2,29,9,8,ghost=True);until(s,lambda:not s.pending_moves)
            check(s.state['self']['x']==8,'ghost_walk_cannot_overlap_npc');close(s)
            # Real snail definition and real Archer bow. Measure send -> damage,
            # including the queue after a walk and face, rather than transport receipt.
            s=stage(30,5);s.move(3,1,30,9,8);until(s,lambda:not s.pending_moves);s.face(3);s.events.clear()
            start=time.monotonic();s.strike(3);hit=until(s,lambda:any(e.get('kind')=='npc_damage' for e in s.events),5)
            timings['archer_after_walk_ms']=round((time.monotonic()-start)*1000,2)
            check(hit and timings['archer_after_walk_ms']<900,'archer_after_walk_responds_under_900ms')
            pump(s,.7);s.drop_item(249,1);pump(s,.15);drop=next(i for i in s.state['items'] if i['id']==249)
            s.events.clear();start=time.monotonic();s.collect(drop['uid']);hit=until(s,lambda:any(e.get('kind')=='pickup' for e in s.events),4)
            timings['pickup_ms']=round((time.monotonic()-start)*1000,2)
            check(hit and timings['pickup_ms']<250,'pickup_responds_under_250ms');close(s)
            s=stage(30,5);s.drop_item(249,1);pump(s,.2);drop=next(i for i in s.state['items'] if i['id']==249)
            # The phone may change facing every 125ms. The old queue charges
            # 20ms staging + 120ms Face, accumulating work faster than input.
            start=time.monotonic()
            for n in range(64):
                until_at=start+n*.125
                while time.monotonic()<until_at:pump(s,min(.01,until_at-time.monotonic()))
                s.face(n%4)
            s.events.clear();start=time.monotonic();s.collect(drop['uid'])
            hit=until(s,lambda:any(e.get('kind')=='pickup' for e in s.events),4)
            timings['pickup_after_turning_ms']=round((time.monotonic()-start)*1000,2)
            check(hit and timings['pickup_after_turning_ms']<250,'turning_does_not_build_action_backlog');close(s)
            # Burst received together must keep Walk->Attack order. The old
            # two-stage queue appends deferred work behind subsequent inputs.
            s=stage(31);pump(s,.5);s.events.clear();s.move(3,1,31,9,8);s.strike(3)
            pump(s,1);check(s.state['self']['x']==8,'burst_rejects_npc_collision')
            close(s)
        finally:
            for s in sessions:s.close()
            proc.terminate();proc.wait(timeout=15);stream.close()
    result=dict(result='passed' if all(checks.values()) else 'baseline_failures',checks=checks,timings=timings,isolated_database=True,production_database_opened=False)
    a.report.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

if __name__=='__main__':main()
