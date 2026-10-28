"""Measure real level-50 equipped TP upkeep/recovery in an isolated native world."""
from pathlib import Path
import json,os,secrets,select,shutil,socket,sqlite3,subprocess,tempfile,time,statistics
from contextlib import closing
from eo_session import Session
from live_session import LiveSession
from test_online import dev_name
from provision_summoner_test import build_kit
ROOT=Path(__file__).resolve().parents[1]

def main():
    base=ROOT/'work/pet-owner-scale';profile=json.loads((base/'runtime/data/balance-profile.json').read_text());fields,kit=build_kit(profile)
    with tempfile.TemporaryDirectory(prefix='aster-summoner-tp-') as tmp:
        r=Path(tmp)/'runtime';shutil.copytree(base/'runtime',r,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'));os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18940\nRecoverSpeed = 90s\nTPRecoverRate = 10%\nSitTPRecoverRate = 20%\nIPReconnectLimit = 0\n')
        log=(base/'tp-native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT);s=None
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18940),timeout=.1):break
                except OSError:time.sleep(.1)
            time.sleep(.6)
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name());c=Session(port=18940)
            try:c.register(f['username'],f['password']);c.login(f['username'],f['password']);c.create_character(f['name'])
            finally:c.close()
            time.sleep(.7)
            with closing(sqlite3.connect(r/'database.sdb')) as db,db:
                result=db.execute('UPDATE characters SET '+','.join('"'+k+'"=?' for k in fields)+' WHERE name=? AND account=?',(*fields.values(),f['name'],f['username']));assert result.rowcount==1
            s=LiveSession('127.0.0.1',18940);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']));s.snapshot()
            assert s.stats['max_tp']==kit['max_tp']==1108 and s.stats['max_hp']==kit['max_hp'] and s.stats['weight']==60 and s.stats['max_weight']==70
            assert s.equipment['weapon']==494 and s.equipment['armor']==503
            s.use_item(624);before=s.stats['tp'];s.cast_spell(63,'self');started=time.monotonic();spawned=False;previous=before;changes=[]
            while time.monotonic()-started<12:
                s.poll_actions()
                if select.select([s.sock],[],[],.04)[0]:s.pump()
                if getattr(s,'companion',None):spawned=True
                current=s.stats['tp']
                if current!=previous:
                    changes.append(dict(seconds=round(time.monotonic()-started,3),before=previous,after=current,delta=current-previous));previous=current
            assert spawned and getattr(s,'companion',None) and changes[0]['delta']==-45
            ticks=[e for e in changes if e['delta']==-12];recovery=[e for e in changes if e['delta']>0]
            assert len(ticks)>=3 and len(recovery)>=3 and all(e['delta']==4 for e in recovery)
            cadence=statistics.mean(b['seconds']-a['seconds'] for a,b in zip(ticks,ticks[1:]))
            s.cast_spell(35,'self')
            report=dict(result='passed',isolated_database=True,live_player_database_opened=False,character_level=50,exact_kit_native_stats_match=True,max_tp=1108,max_hp=kit['max_hp'],weight=60,max_weight=70,mythic_initial_tp=45,mythic_upkeep_tp=12,observed_upkeep_ticks=len(ticks),mean_observed_upkeep_seconds=round(cadence,3),observed_standing_recovery_tp=4,recovery_interval_seconds=2,observation_seconds=12,tp_changes=changes,full_depletion_observed=False)
            (base/'tp-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='tp_changes'},indent=2))
        finally:
            if s:s.close()
            proc.terminate();proc.wait(timeout=15);log.close()

if __name__=='__main__':main()
