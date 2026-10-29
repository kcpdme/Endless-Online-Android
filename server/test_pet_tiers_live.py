"""Shop, every pet appearance and permanent collections and cooldowns in a disposable native world."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,sys,tempfile,time
from contextlib import closing
from pathlib import Path
from eo_session import Session,Reader,number,EOError
from live_session import LiveSession
from test_online import dev_name
from configure_balance import records,encode_pub,put,num
from pet_catalog import EGGS,COMPANIONS,TIERS,EGGKEEPER
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,default=ROOT/'work/pet-collection-v12/runtime');p.add_argument('--godot',type=Path);a=p.parse_args()
    checks=[];pets=[];processes=[];streams=[]
    def check(ok,why):
        if not ok:raise AssertionError(why)
        checks.append(why)
    with tempfile.TemporaryDirectory(prefix='aster-pet-tiers-') as tmp:
        b=Path(tmp);r=b/'runtime';shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'));os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18930\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nIPReconnectLimit = 0\nCriticalRate = 0\nBalance.7.tp_regen = 0\nProtectNPCDrop = 0\nBalanceEgg.609.chance = 100\n')
        # One durable target and a lethal spike exist only in this isolated copy.
        path=r/'data/pub/dtn001.enf';raw=path.read_bytes();rows=records(raw,b'ENF',39)
        for off,val,size in [(11,50000,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[0]['fields'],off,val,size)
        original_wolf_exp=num(rows[73]['fields'],36,3)
        for off,val,size in [(11,1,3),(16,0,2),(18,0,2),(22,0,2),(24,0,2)]:put(rows[73]['fields'],off,val,size)
        path.write_bytes(encode_pub(raw,rows))
        drops=r/'data/aster-vale-drops.ini';import re
        drops.write_text(re.sub(r'^74\s*=.*$', '74 = 1,1,1,100, 609,1,1,100',drops.read_text(),flags=re.M))
        from configure_sky_wonder import parse,grid
        path=r/'data/maps/00021.emf';raw=path.read_bytes();prefix,g,signs=parse(raw);prefix=bytearray(prefix);prefix[43:45]=number(0,1)*2;g['specs'][11,9]=number(35,1)
        assert not signs
        path.write_bytes(prefix+b''.join(grid(c) for c in g.values())+number(0,1))
        # Real PK, arena and travel fixtures, with no edits to public maps.
        for mid,pk in [(22,True),(23,False)]:
            pre=bytearray(prefix);pre[31:32]=number(3 if pk else 0,1);pre[43:45]=number(2 if mid==23 else 0,1)*2
            for x in range(2,13):
                for y in range(2,11):g['specs'].pop((x,y),None)
            (r/f'data/maps/{mid:05d}.emf').write_bytes(pre+b''.join(grid(c) for c in g.values())+number(0,1))
        arena=r/'data/aster-vale-arenas.ini';arena.write_text(arena.read_text()+'\n23.enabled = yes\n23.time = 2\n23.block = 2\n23.spawns = 4,8,4,9, 5,8,5,9\n')
        (r/'data/quests/00000.eqf').write_text('Main { questname "Unmultiplied EXP fixture" version 2 }\nstate Begin { action GiveEXP(17) action End() }\n')
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
        def stage(f,clas=7,level=40,inventory='1,500000;',spells='23,0;35,0;',location=(5,35,45),admin=0,hp=30000,tp=30000):
            time.sleep(.65)
            with closing(sqlite3.connect(r/'database.sdb')) as db,db:
                result=db.execute('UPDATE characters SET class=?,level=?,map=?,x=?,y=?,cha=100,"int"=50,"con"=1000,hp=?,tp=?,spells=?,inventory=?,admin=? WHERE name=? AND account=?',(clas,level,*location,hp,tp,spells,inventory,admin,f['character_name'],f['username']));assert result.rowcount==1
                if admin==4 and clas==6:db.execute('UPDATE characters SET paperdoll=? WHERE name=?',(','.join(map(str,[0]*8+[491]+[0]*6)),f['character_name']))
                db.execute('DELETE FROM aster_pet_state WHERE character_name=?',(f['character_name'],))
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
            s=login(f)
            try:check(s.stats['experience']==17,'Quest GiveEXP grants exactly its written reward at x1')
            finally:s.close()
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
                    hatch_result=s.use_item(ident);spell=egg['spell_id'];pet=COMPANIONS[spell];tier=TIERS[egg['tier']]
                    if not (s.item_amount(ident)==1 and any(x['id']==spell for x in s.spells)):print('HATCH DIAGNOSTIC',dict(egg=ident,bag=s.inventory,spells=s.spells,events=hatch_result.get('events',[])[-10:],clas=s.stats.get('class_id'),level=s.stats.get('level')),flush=True)
                    check(s.item_amount(ident)==1 and any(x['id']==spell for x in s.spells),'Hatching consumes exactly one egg and unlocks its permanent pet')
                    check(s.item_amount(egg['hatched_id'])==1,'Hatching creates one physical Hatched Egg keepsake')
                    try:s.use_item(ident)
                    except EOError as exc:check('already hatched' in str(exc),'Duplicate species is refused before consuming a spare')
                    else:raise AssertionError('A duplicate hatch was accepted')
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
                    check(any(x['id']==spell for x in s.spells) and s.item_amount(ident)==1,'Dismissal preserves the permanent pet and spare egg')
                    check(295<=s.snapshot()['pet_state']['cooldown_seconds']<=300,'Dismissal starts a real five-minute shared native cooldown')
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
            # Ordinary death retains ownership and starts a persistent cooldown.
            stage(f,spells='23,0;61,0;35,0;',inventory='1,123;622,2;638,1;',location=(21,11,8),hp=1);s=login(f)
            try:
                s.walk(0);until(s,lambda:s.state['map_id']!=21)
                check(any(x['id']==61 for x in s.spells) and s.item_amount(622)==2 and s.item_amount(638)==1,'Ordinary death keeps the permanent Banshi pet, Hatched Egg and spare Eggs')
                check(295<=s.snapshot()['pet_state']['cooldown_seconds']<=300,'Death starts five-minute recovery')
            finally:s.close()
            s=login(f)
            try:check(any(x['id']==61 for x in s.spells) and s.snapshot()['pet_state']['cooldown_seconds']>280,'Death ownership and cooldown survive reconnect')
            finally:s.close()
            # Collect five species, retain all, and prevent raw spell/item bypasses.
            choices=[612,609,610,619,611]
            stage(f,inventory='1,500000;'+''.join(f'{i},1;' for i in choices));s=login(f)
            try:
                for i in choices:s.use_item(i)
                check(all(any(x['id']==EGGS[i]['spell_id'] for x in s.spells) and s.item_amount(EGGS[i]['hatched_id'])==1 for i in choices),'Five hatched species coexist as permanent unlocks and Lore keepsakes')
                s.use_item(EGGS[611]['hatched_id']);check(s.snapshot()['pet_state']['selected_spell']==34,'Using a Hatched Egg binds its collected pet without consuming it')
                s.cast_spell(34,'self');until(s,lambda:bool(getattr(s,'companion',None)))
                s.cast_spell(35,'self');until(s,lambda:not getattr(s,'companion',None) and not s.casting)
                before=s.stats['tp'];s.cast_spell(28,'self');until(s,lambda:not s.casting)
                check(not getattr(s,'companion',None) and s.stats['tp']==before,'A different summon spell cannot bypass the shared cooldown or spend call TP')
                s.send(14,10,number(EGGS[609]['hatched_id'],2));s.wait(14,3)
                check(s.snapshot()['pet_state']['selected_spell']==34,'Raw Hatched Egg binding cannot bypass cooldown')
                for family,action,payload in [(14,24,number(627,2)+number(1,3)+b'\xff\xff'),(14,12,number(627,2)+number(1,4)),(13,16,number(627,2)+number(1,4))]:
                    s.send(family,action,payload);time.sleep(.1);s.refresh()
                check(s.item_amount(627)==1,'Raw drop, junk and shop sale cannot remove a Hatched Egg')
            finally:s.close()
            s=login(f)
            try:check(len([x for x in s.spells if x['id'] in {EGGS[i]['spell_id'] for i in choices}])==5 and s.snapshot()['pet_state']['cooldown_seconds']>280,'All five pets and shared recovery survive logout')
            finally:s.close()
            time.sleep(.7)
            with closing(sqlite3.connect(r/'database.sdb')) as db,db:
                db.execute('UPDATE aster_pet_state SET ready_at=? WHERE character_name=?',(int(time.time())-1,f['character_name']))
            s=login(f)
            try:
                check(s.snapshot()['pet_state']['cooldown_seconds']==0,'Expired native persistent recovery becomes ready on reconnect')
                s.use_item(EGGS[609]['hatched_id']);check(s.snapshot()['pet_state']['selected_spell']==28,'After expiry another collected species can be bound')
                s.cast_spell(28,'self');until(s,lambda:bool(getattr(s,'companion',None)))
            finally:s.close()
            s=login(f)
            try:check(s.snapshot()['pet_state']['cooldown_seconds']==0 and s.snapshot()['pet_state']['selected_spell']==28,'Logging out with a called pet preserves selection and starts no cooldown')
            finally:s.close()
            stage(f,spells='23,0;28,0;35,0;',inventory='1,123;625,1;',tp=TIERS['rare']['tp']);s=login(f)
            try:
                s.cast_spell(28,'self');until(s,lambda:bool(getattr(s,'companion',None)))
                until(s,lambda:not getattr(s,'companion',None) and s.snapshot()['pet_state']['cooldown_seconds']>0)
                check(any(x['id']==28 for x in s.spells) and s.item_amount(625)==1,'TP exhaustion preserves the pet and starts shared recovery')
            finally:s.close()
            stage(f,spells='23,0;61,0;35,0;',inventory='1,123;638,1;',location=(156,6,8));s=login(f)
            try:
                master=next(n for n in s.state['npcs'] if n['id']==116);s.skillmaster_open(master['index'])
                try:s.skill_change('forget',61)
                except EOError:pass
                else:raise AssertionError('Permanent pet was forgettable')
                s.send(16,4,number(s.skillmaster['id'],4)+number(61,2));time.sleep(.2);s.refresh()
                check(any(x['id']==61 for x in s.spells),'Adapter and raw skill-master forgetting cannot erase collected pets')
            finally:s.close()
            # Travel removes the active entity, preserves the collection and starts no timer.
            stage(f,spells='28,0;35,0;',inventory='1,123;625,1;',admin=4);s=login(f)
            try:
                s.cast_spell(28,'self');until(s,lambda:bool(getattr(s,'companion',None)))
                s.chat_send('local','$warp 22 4 8');until(s,lambda:s.state['map_id']==22 and not s.warp)
                check(s.snapshot()['pet_state']['cooldown_seconds']==0 and any(x['id']==28 for x in s.spells),'Map travel preserves ownership and starts no pet recovery')
            finally:s.close()
            # PK death preserves ownership and starts the same recovery.
            stage(f,spells='28,0;35,0;',inventory='1,123;625,1;',location=(22,4,8),hp=1);victim=login(f)
            stage(op,clas=6,location=(22,4,9),admin=4);attacker=login(op)
            try:
                for _ in range(8):
                    attacker.strike(2)
                    end=time.monotonic()+.8
                    while time.monotonic()<end:
                        for actor in (victim,attacker):
                            actor.poll_actions()
                            if select.select([actor.sock],[],[],.01)[0]:actor.pump()
                    if victim.state['map_id']!=22:break
                check(victim.state['map_id']!=22 and any(x['id']==28 for x in victim.spells) and victim.item_amount(625)==1,'Real PK death preserves Hatched Egg and pet')
                check(victim.snapshot()['pet_state']['cooldown_seconds']>280,'PK death starts shared recovery')
            finally:victim.close();attacker.close()
            stage(f,spells='28,0;35,0;',inventory='1,123;625,1;',admin=4);victim=login(f)
            stage(op,clas=6,admin=4);attacker=login(op)
            try:
                victim.chat_send('local','$warp 23 4 8');attacker.chat_send('local','$warp 23 5 8')
                end=time.monotonic()+8
                while time.monotonic()<end and not (victim.state['self']['y']==9 and attacker.state['self']['y']==9):
                    for actor in (victim,attacker):
                        actor.poll_actions()
                        if select.select([actor.sock],[],[],.02)[0]:actor.pump()
                check(victim.state['self']['y']==9 and attacker.state['self']['y']==9,'Both fixtures enter the actual native arena round')
                attacker.strike(1)
                until(victim,lambda:victim.state['self']['x']==2)
                check(any(x['id']==28 for x in victim.spells) and victim.item_amount(625)==1 and victim.snapshot()['pet_state']['cooldown_seconds']>280,'Arena elimination preserves pet and starts recovery')
                check(attacker.snapshot()['pet_state']['cooldown_seconds']==0,'Arena winner receives no pet cooldown')
            finally:victim.close();attacker.close()
            # Egg access stays owner/class bound with mortality disabled and ordinary protection expired.
            for clas in (7,6):
                stage(op,clas=6,location=(22,5,8),admin=4);attacker=login(op)
                try:attacker.chat_send('local','$snpc 74 1 7');until(attacker,lambda:any(n['id']==74 for n in attacker.state['npcs']))
                finally:attacker.close()
                stage(f,clas=clas,location=(22,4,8),admin=4);s=login(f)
                try:
                    before=s.stats['experience'];s.events.clear()
                    for _ in range(6):
                        s.strike(3)
                        try:until(s,lambda:any(e.get('kind')=='npc_killed' for e in s.events),1)
                        except AssertionError:continue
                        break
                    kill=next(e for e in s.events if e.get('kind')=='npc_killed')
                    check(s.stats['experience']-before==original_wolf_exp,'Native kill EXP equals original monster PUB reward exactly')
                    check(kill['drop']['id']==1 and kill['drop']['amount']==1,'A guaranteed classic Gold drop is preserved even when the bonus egg succeeds')
                    if clas==7:until(s,lambda:any(i['id']==609 for i in s.state['items']))
                    eggs=[i for i in s.state['items'] if i['id']==609]
                    check(bool(eggs)==(clas==7),'Only Summoner receives even a fixture-guaranteed bonus egg drop')
                    if clas==7:
                        bonus_uid=eggs[0]['uid']
                        stage(op,clas=7,location=(22,5,8));thief=login(op)
                        try:
                            thief.send(14,27,number(bonus_uid,2));time.sleep(.2);thief.refresh()
                            check(thief.item_amount(609)==0,'Another Summoner cannot pick up an egg after ordinary protection expires')
                        finally:thief.close()
                        s.send(14,27,number(bonus_uid,2));until(s,lambda:s.item_amount(609)==1)
                        check(True,'The Summoner kill owner can collect their egg')
                finally:s.close()
            if a.godot:
                stage(f,level=40);fixture=b/'fixture.json';fixture.write_text(json.dumps(f));fixture.chmod(0o600)
                start('gateway',[sys.executable,ROOT/'server/gateway.py','--port',18931,'--eo-port',18930],18931)
                start('websocket',[sys.executable,ROOT/'server/ws_gateway.py','--port',18932,'--tcp-port',18931,'--deps-dir',ROOT/'work/server-build/python'],18932)
                env=dict(os.environ,ASTER_VALE_PET_FIXTURE=str(fixture),ASTER_VALE_TEST_HOST='ws://127.0.0.1:18932/ws',ASTER_VALE_TEST_REPORT=str(ROOT/'work/pet-collection-v12/client-report.json'),XDG_DATA_HOME=str(b/'godot-data'),XDG_CONFIG_HOME=str(b/'godot-config'))
                result=subprocess.run([str(a.godot.resolve()),'--headless','--path',str(ROOT/'client'),'--script','res://tests/pet_tiers_live.gd'],env=env,capture_output=True,text=True,timeout=120)
                (ROOT/'work/pet-collection-v12/client-live.log').write_text(result.stdout+result.stderr);check(result.returncode==0 and 'SCRIPT ERROR' not in result.stderr,'Real Godot Eggkeeper UI and live hatching/summoning pass')
            report=dict(result='passed',checks=len(checks),native_pet_choices=pets,tiers=len(seen),native_purchase_hatch_summon_upkeep_dismiss_death=True,permanent_multi_species_collection=True,shared_cooldown_raw_bypass_denied=True,pk_and_arena_death_keep_pets=True,travel_and_logout_start_no_cooldown=True,original_monster_and_literal_quest_exp=True,summoner_only_owner_bound_drops=True,bonus_eggs_preserve_guaranteed_classic_loot=True,isolated_database=True,production_database_opened=False)
            (ROOT/'work/pet-collection-v12/native-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
        finally:
            for proc in reversed(processes):
                proc.terminate()
                try:proc.wait(timeout=15)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            for stream in streams:stream.close()
            for name in ('native','gateway','websocket'):
                if (b/(name+'.log')).exists():shutil.copy2(b/(name+'.log'),ROOT/'work/pet-collection-v12'/(name+'.log'))

if __name__=='__main__':main()
