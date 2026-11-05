#!/usr/bin/env python3
"""Time actual native hits for every class and bow; reject forged rapid attacks."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time
from pathlib import Path
from eo_session import Session,number
from live_session import LiveSession
from configure_balance import records,encode_pub,put
from configure_sky_wonder import parse,grid
from combat_progression import BOWS
from configure_attack_cadence import configure
from test_online import dev_name


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--binary',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--baseline',action='store_true');p.add_argument('--port',type=int,default=18983);a=p.parse_args()
    results=[];sessions=[]
    with tempfile.TemporaryDirectory(prefix='aster-attack-cadence-') as temp:
        r=Path(temp)/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','etheos*'));shutil.copy2(a.binary,r/'etheos')
        os.environ['ASTER_VALE_RUNTIME']=str(r)
        if not a.baseline:configure(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+f'\nPort = {a.port}\nIPReconnectLimit = 0\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nCriticalFirstHit = no\nCriticalRate = 0\n')
        pub=r/'data/pub/dtn001.enf';raw=pub.read_bytes();rows=records(raw,b'ENF',39)
        for offset,value,size in ((11,500000,3),(22,0,2),(24,0,2)):put(rows[0]['fields'],offset,value,size)
        pub.write_bytes(encode_pub(raw,rows))
        prefix,g,_=parse((r/'data/maps/00021.emf').read_bytes());prefix=bytearray(prefix[:46]);prefix[43:45]=number(0,1)*2
        for x in range(2,18):
            for y in range(2,12):g['specs'].pop((x,y),None);g['warps'].pop((x,y),None)
        spawn=number(12,1)+number(8,1)+number(1,2)+number(7,1)+number(0,2)+number(1,1)
        (r/'data/maps/00021.emf').write_bytes(prefix+number(1,1)+spawn+number(0,1)*2+b''.join(grid(c) for c in g.values())+number(0,1))
        a.report.parent.mkdir(parents=True,exist_ok=True);log=a.report.with_suffix('.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
        def pump(s,seconds=.01):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                if select.select([s.sock],[],[],min(.005,max(0,end-time.monotonic())))[0]:s.pump()
        def stage(clas,bow,distance):
            name,user,password=dev_name(),dev_name(),secrets.token_urlsafe(18);base=Session('127.0.0.1',a.port)
            base.register(user,password);base.login(user,password);base.create_character(name);base.close();time.sleep(.12)
            gear=[0]*15;gear[8]=bow;gear[7]=423 if clas==5 else 0
            with sqlite3.connect(r/'database.sdb') as db:
                db.execute('UPDATE characters SET map=21,x=?,y=8,direction=3,class=?,level=50,hp=10000,tp=10000,"str"=50,"int"=50,wis=50,agi=100,"con"=100,cha=50,paperdoll=? WHERE name=?',(12-distance,clas,','.join(map(str,gear)),name))
            s=LiveSession('127.0.0.1',a.port);sessions.append(s);chars=s.login(user,password)['characters'];s.enter(chars[0]['id']);s.snapshot();pump(s,.1);s.events.clear();return s
        def sample(clas,bow,distance,send_seconds=.04,duration=1.95):
            s=stage(clas,bow,distance);times=[];start=time.monotonic();next_send=start
            while time.monotonic()-start<duration:
                now=time.monotonic()
                if now>=next_send:
                    # Deliberately forged timestamps and 25 packets/sec. Damage
                    # must still follow the native wall clock, not client claims.
                    s.timestamp+=1000;s.send(11,10,number(3,1)+number(s.timestamp,3));next_send=now+send_seconds
                pump(s)
                hits=[e for e in s.events if e.get('kind')=='npc_damage']
                while len(times)<len(hits):times.append(time.monotonic()-start)
            gaps=[round(b-a,4) for a,b in zip(times,times[1:])]
            result=dict(class_id=clas,bow=bow,distance=distance,hits=len(times),intervals=gaps,passed=len(times)>=3 and bool(gaps) and min(gaps)>=.585)
            if clas==5:
                damage=[e['damage'] for e in s.events if e.get('kind')=='npc_damage' and e.get('damage',0)>0]
                bounds=[s.stats['min_damage'],s.stats['max_damage']]
                full_impact=bool(damage) and all(bounds[0]<=amount<=bounds[1] for amount in damage)
                result.update(damage=damage,full_impact_bounds=bounds,full_impact=full_impact)
                result['passed']=result['passed'] and full_impact
            results.append(result);print(json.dumps(result),flush=True);s.close();sessions.remove(s)
            if not a.baseline and not result['passed']:raise AssertionError('Native attack cadence exceeded: '+json.dumps(result))
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',a.port),timeout=.1):break
                except OSError:time.sleep(.05)
            time.sleep(.5)
            for clas in (0,2,3,4,6,7,8):sample(clas,0,1)
            for bow,traits in BOWS.items():
                sample(5,bow,1);sample(5,bow,min(4,traits['range_tiles']))
            # Existing special close range was two tiles, as well as adjacency.
            for bow in (457,496):sample(5,bow,2)
            # Disable the optional progression feature and attempt the same exploit.
            proc.terminate();proc.wait(timeout=15);cfg.write_text(cfg.read_text()+'\nCombatProgression = no\n')
            proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT);time.sleep(.8)
            sample(6,0,1,send_seconds=.15,duration=3.2)
        finally:
            for s in sessions:s.close()
            proc.terminate();proc.wait(timeout=15);log.close()
    receipt=dict(result='passed' if all(x['passed'] for x in results) else 'baseline_failures',scenarios=results,isolated_database=True,production_database_opened=False)
    a.report.write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(result=receipt['result'],scenarios=len(results))))

if __name__=='__main__':main()
