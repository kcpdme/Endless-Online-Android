"""Shop, every pet appearance and new-bond mortality in a disposable native world."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,sys,tempfile,time
from contextlib import closing
from pathlib import Path
from eo_session import Session,Reader,number,EOError
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put
from pet_catalog import EGGS,COMPANIONS,TIERS,EGGKEEPER
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,default=ROOT/'work/egg-economy-v11/runtime');p.add_argument('--godot',type=Path);a=p.parse_args()
    checks=[];pets=[];processes=[];streams=[]
    def check(ok,why):
        if not ok:raise AssertionError(why)
        checks.append(why)
    with tempfile.TemporaryDirectory(prefix='aster-pet-tiers-') as tmp:
        b=Path(tmp);r=b/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'));os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18930\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nBalance.7.tp_regen = 0\n')
        # One durable target and a lethal spike exist only in this isolated copy.
        path=r/'data/pub/dtn001.enf';raw=path.read_bytes();rows=records(raw,b'ENF',39)
        for off,val,size in [(11,50000,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[0]['fields'],off,val,size)
        path.write_bytes(encode_pub(raw,rows))
        from configure_sky_wonder import parse,grid
        path=r/'data/maps/00021.emf';raw=path.read_bytes();prefix,g,signs=parse(raw);prefix=bytearray(prefix);prefix[43:45]=number(0,1)*2;g['specs'][11,9]=number(35,1)
        assert not signs
        path.write_bytes(prefix+b''.join(grid(c) for c in g.values())+number(0,1))
        def start(name,command,port,cwd=ROOT):
            log=(b/(name+'.log')).open('w');streams.append(log);proc=subprocess.Popen(list(map(str,command)),cwd=cwd,env=dict(os.environ,ASTER_VALE_SHORTCUT_DB=str(b/'shortcuts.sqlite3')),stdout=log,stderr=subprocess.STDOUT);processes.append(proc)
            for _ in range(100):
                if proc.poll() is not None:raise RuntimeError(name+' failed')
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
                except OSError:time.sleep(.1)
            else:raise RuntimeError(name+' did not listen')
            time.sleep(.5)
        def provision():
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name());s=Session(port=18930)
            try:s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['character_name'])
            finally:s.close()
            time.sleep(.6);return f
        def stage(f,clas=7,level=40,inventory='1,500000;',spells='23,0;35,0;',location=(5,35,45),admin=0,hp=30000):
            time.sleep(.65)
            with closing(sqlite3.connect(r/'database.sdb')) as db,db:
                result=db.execute('UPDATE characters SET class=?,level=?,map=?,x=?,y=?,cha=100,"int"=50,"con"=1000,hp=?,tp=30000,spells=?,inventory=?,admin=? WHERE name=? AND account=?',(clas,level,*location,hp,spells,inventory,admin,f['character_name'],f['username']));assert result.rowcount==1
        def login(f):
            s=LiveSession('127.0.0.1',18930);chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['character_name']));s.snapshot();return s
        def until(s,predicate,timeout=10):
            end=time.monotonic()+timeout
            while time.monotonic()<end:
                s.poll_actions()
                if predicate():return
                if select.select([s.sock],[],[],.03)[0]:s.pump()
            raise AssertionError('Native pet event timed out')
        def shop(s):
            keeper=next(n for n in s.state['npcs'] if n['id']==EGGKEEPER['id']);s.shop_open(keeper['index']);return s.shop
        try:
            start('native',[r/'etheos'],18930,r);f=provision();op=provision()
            stage(op,clas=6,location=(5,36,45),admin=4);s=login(op)
            try:s.chat_send('local','$snpc 1 1 7');until(s,lambda:any(n['id']==1 and (n['x'],n['y'])==(36,45) for n in s.state['npcs']))
            finally:s.close()
            # A raw original-client packet cannot buy eggs after a class switch.
            stage(f,clas=6);s=login(f)
            try:
                stock=shop(s);check(len(stock['trade'])==16,'Native Eggkeeper exposes all 16 choices');gold=s.item_amount(1)
                s.send(13,11,number(612,2)+number(1,4));time.sleep(.2);s.refresh()
                check(s.item_amount(612)==0 and s.item_amount(1)==gold,'Native non-Summoner purchase refusal preserves Gold and inventory')
            finally:s.close()
            seen=set()
            for tier,t in TIERS.items():
                ident,egg=next((i,e) for i,e in EGGS.items() if e['tier']==tier)
                stage(f,level=t['level']-1,inventory=f'1,100000;{ident},1;');s=login(f)
                try:
                    s.send(14,10,number(ident,2));s.wait(14,3)
                    check(s.item_amount(ident)==1 and not any(x['id']==egg['spell_id'] for x in s.spells),'Raw native hatching rejects '+tier+' one level below its new threshold')
                finally:s.close()
            for ident,egg in EGGS.items():
                stage(f,level=egg['level']);s=login(f)
                try:
                    stock=shop(s);offer=next(o for o in stock['trade'] if o['id']==ident);check((offer['buy'],offer['sell'])==(egg['price'],egg['sell_price']),'Tier price and 40 percent buyback are native shop values')
                    gold=s.item_amount(1);s.shop_trade('buy',ident,2)
                    check(s.item_amount(ident)==2 and s.item_amount(1)==gold-2*egg['price'],'Buying two eggs charges exactly the displayed Gold')
                    s.use_item(ident);spell=egg['spell_id'];pet=COMPANIONS[spell];tier=TIERS[egg['tier']]
                    check(s.item_amount(ident)==1 and any(x['id']==spell for x in s.spells),'Hatching consumes exactly one egg and grants its own bond')
                    try:s.use_item(ident)
                    except EOError as exc:check('living pet bond' in str(exc),'Duplicate bond is refused before consuming a spare')
                    else:raise AssertionError('A second living bond was accepted')
                    before=s.stats['tp'];s.cast_spell(spell,'self');until(s,lambda:getattr(s,'companion',None) and s.companion['npc_id']==pet['npc_id'])
                    check(s.stats['tp']==before-tier['tp'],'Summon charges its tier initial TP exactly once')
                    check(len([n for n in s.state['npcs'] if n['id'] in {p['npc_id'] for p in COMPANIONS.values()}])==1,'Exactly one visible native companion is present')
                    if egg['tier'] not in seen:
                        until(s,lambda:s.stats['tp']==before-tier['tp']-tier['upkeep']);check(True,'Native tier upkeep charges the configured TP')
                        target=next(n for n in s.state['npcs'] if n['id']==1 and (n['x'],n['y'])==(36,45));s.events.clear();s.cast_spell(23,'npc',target['index'])
                        deadline=time.monotonic()+12;last_strike=0
                        while time.monotonic()<deadline and not any(e.get('kind')=='companion_attack' and e.get('damage',0)>0 for e in s.events):
                            if time.monotonic()-last_strike>.8:s.strike(3);last_strike=time.monotonic()
                            s.poll_actions()
                            if select.select([s.sock],[],[],.03)[0]:s.pump()
                        check(any(e.get('kind')=='companion_attack' and e.get('damage',0)>0 for e in s.events),'Actively commanded '+egg['tier']+' pet reaches and damages the target')
                        damage=next(e['damage'] for e in s.events if e.get('kind')=='companion_attack' and e.get('damage',0)>0);low=int(s.stats['min_damage']*tier['power']);high=__import__('math').ceil(s.stats['max_damage']*tier['power'])
                        check(max(1,low)<=damage<=max(1,high),'Native pet damage scales from the current owner attack roll');seen.add(egg['tier'])
                    s.cast_spell(35,'self');until(s,lambda:not getattr(s,'companion',None) and not s.casting)
                    check(any(x['id']==spell for x in s.spells) and s.item_amount(ident)==1,'Dismissal preserves the living bond and spare egg')
                    shop(s);gold=s.item_amount(1);s.shop_trade('sell',ident,1)
                    check(s.item_amount(ident)==0 and s.item_amount(1)==gold+egg['sell_price'],'Selling the spare bound egg pays exactly 40 percent without removing its living bond')
                    check(any(x['id']==spell for x in s.spells),'Egg buyback cannot release or sell a hatched living bond')
                    pets.append(dict(egg_id=ident,spell_id=spell,npc_id=pet['npc_id'],tier=egg['tier']))
                finally:s.close()
            stage(f,clas=6,level=45,inventory='1,100000;623,1;');s=login(f)
            try:
                shop(s);s.shop_trade('sell',623,1)
                check(s.item_amount(623)==0 and s.item_amount(1)==140000,'A former Summoner can sell an existing bound egg after changing class')
            finally:s.close()
            stage(f,level=1,inventory='1,100000;623,1;');s=login(f)
            try:
                s.send(14,10,number(623,2));time.sleep(.2);s.refresh();check(s.item_amount(623)==1 and not any(x['id']==62 for x in s.spells),'Raw under-level hatching preserves a Mythic egg')
            finally:s.close()
            # New appended summon IDs use the same native mortality path as legacy pets.
            stage(f,spells='23,0;61,0;35,0;',inventory='1,123;622,2;',location=(21,11,8),hp=1);s=login(f)
            try:
                s.walk(0);until(s,lambda:s.state['map_id']!=21)
                check(not any(x['id']==61 for x in s.spells) and s.item_amount(622)==2,'Death removes a new Banshi bond and preserves spare eggs')
            finally:s.close()
            s=login(f)
            try:check(not any(x['id']==61 for x in s.spells),'New-bond death loss persists across reconnect')
            finally:s.close()
            stage(f,spells='23,0;61,0;35,0;',inventory='1,123;622,2;',location=(156,6,8));s=login(f)
            try:
                s.cast_spell(61,'self');until(s,lambda:bool(getattr(s,'companion',None)))
                master=next(n for n in s.state['npcs'] if n['id']==116);s.skillmaster_open(master['index']);s.skill_change('forget',61)
                until(s,lambda:not getattr(s,'companion',None))
                check(not any(x['id']==61 for x in s.spells) and not any(n['id']==319 for n in s.state['npcs']),'Releasing a bond at a real skill master immediately removes its visible pet')
                s.use_item(622);check(any(x['id']==61 for x in s.spells) and s.item_amount(622)==1,'After release a replacement egg creates exactly one new bond')
            finally:s.close()
            if a.godot:
                stage(f,level=40);fixture=b/'fixture.json';fixture.write_text(json.dumps(f));fixture.chmod(0o600)
                start('gateway',[sys.executable,ROOT/'server/gateway.py','--port',18931,'--eo-port',18930],18931)
                start('websocket',[sys.executable,ROOT/'server/ws_gateway.py','--port',18932,'--tcp-port',18931,'--deps-dir',ROOT/'work/server-build/python'],18932)
                env=dict(os.environ,ASTER_VALE_PET_FIXTURE=str(fixture),ASTER_VALE_TEST_HOST='ws://127.0.0.1:18932/ws',ASTER_VALE_TEST_REPORT=str(ROOT/'work/egg-economy-v11/client-report.json'),XDG_DATA_HOME=str(b/'godot-data'),XDG_CONFIG_HOME=str(b/'godot-config'))
                result=subprocess.run([str(a.godot.resolve()),'--headless','--path',str(ROOT/'client'),'--script','res://tests/pet_tiers_live.gd'],env=env,capture_output=True,text=True,timeout=120)
                (ROOT/'work/egg-economy-v11/client-live.log').write_text(result.stdout+result.stderr);check(result.returncode==0 and 'SCRIPT ERROR' not in result.stderr,'Real Godot Eggkeeper UI and live hatching/summoning pass')
            report=dict(result='passed',checks=len(checks),native_pet_choices=pets,tiers=len(seen),native_purchase_hatch_summon_upkeep_dismiss_death=True,isolated_database=True,production_database_opened=False)
            (ROOT/'work/egg-economy-v11/native-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
        finally:
            for proc in reversed(processes):
                proc.terminate()
                try:proc.wait(timeout=15)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            for stream in streams:stream.close()
            for name in ('native','gateway','websocket'):
                if (b/(name+'.log')).exists():shutil.copy2(b/(name+'.log'),ROOT/'work/egg-economy-v11'/(name+'.log'))

if __name__=='__main__':main()
