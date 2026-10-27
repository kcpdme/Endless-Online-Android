#!/usr/bin/env python3
"""Isolated native + WebSocket balance acceptance; never opens a player database."""
import argparse,json,os,secrets,select,shutil,socket,sqlite3,subprocess,sys,tempfile,time
from contextlib import closing
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
from eo_session import Session,number
from test_online import dev_name
from configure_balance import records,encode_pub,put
from balance_model import allocation,stats,spell_preview,GEAR,benchmarks,loadout

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--runtime',type=Path,default=ROOT/'work/balance-v3/runtime');parser.add_argument('--report',type=Path,default=ROOT/'work/balance-v3/native-report.json');parser.add_argument('--godot',type=Path);parser.add_argument('--skip-stat-builds',action='store_true');args=parser.parse_args()
    processes=[];streams=[];checks=[];results=[]
    def check(ok,why):
        if not ok:raise AssertionError(why)
        checks.append(why)
    with tempfile.TemporaryDirectory(prefix='aster-balance-') as tmp:
        base=Path(tmp);runtime=base/'runtime';shutil.copytree(args.runtime,runtime,ignore=shutil.ignore_patterns('database.sdb*','*.log','*.bak'))
        os.environ['ASTER_VALE_RUNTIME']=str(runtime)
        config=runtime/'config.local.ini';config.write_text(config.read_text()+'\nPort = 18896\nRecoverSpeed = 1h\nNPCRecoverSpeed = 1h\nPriestRegenRate = 0\nPriestSittingRegenRate = 0\nIPReconnectLimit = 0\n')
        # Meeting room forces relog to its NPC-boundary entry tile. Disable
        # that redirect only in this disposable map so staged combat fixtures
        # actually stand on the intended walkable room floor.
        room=runtime/'data/maps/00021.emf';room_bytes=bytearray(room.read_bytes());room_bytes[0x2B:0x2D]=number(0,1)*2;room.write_bytes(room_bytes)
        # Durable, stationary, harmless target only in this disposable world.
        path=runtime/'data/pub/dtn001.enf';original=path.read_bytes();rows=records(original,b'ENF',39);f=rows[0]['fields']
        for start,value,size in [(11,50000,3),(16,0,2),(18,0,2),(20,0,2),(22,0,2),(24,10,2)]:put(f,start,value,size)
        path.write_bytes(encode_pub(original,rows));profile=json.loads((runtime/'data/balance-profile.json').read_text())
        def start(name,command,port,cwd=ROOT):
            log=(base/(name+'.log')).open('w');streams.append(log)
            proc=subprocess.Popen(list(map(str,command)),cwd=cwd,env=dict(os.environ,ASTER_VALE_SHORTCUT_DB=str(base/'shortcuts.sqlite3')),stdout=log,stderr=subprocess.STDOUT);processes.append(proc)
            for _ in range(100):
                if proc.poll() is not None:raise RuntimeError(name+' failed to start')
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
                except OSError:time.sleep(.1)
            else:raise RuntimeError(name+' did not listen')
            time.sleep(.5)
        def provision():
            fixture=dict(username=dev_name(),password=secrets.token_urlsafe(18),character_name=dev_name())
            s=Session(port=18896)
            try:s.register(fixture['username'],fixture['password']);s.login(fixture['username'],fixture['password']);s.create_character(fixture['character_name'])
            finally:s.close()
            return fixture
        def stage(fixture,clas,level,index=None,location=(21,9,7),spells=None,admin=0):
            # Let the native logout save complete before touching our dev row.
            time.sleep(.65)
            attributes=allocation(clas,level) if clas else allocation(6,level)
            index=(1,8,15,25,35,45).index(level) if index is None else index
            gear=loadout(profile,clas or 6,level,index);weapon,body=(i['id'] for i in gear[:2]);doll=[0]*15;doll[8]=weapon;doll[4]=body
            for item in gear[2:]:
                kind=item['type'];slot={11:7,13:6,14:0,15:1,19:10 if doll[9] else 9}.get(kind)
                if slot is not None:doll[slot]=item['id']
            if clas==5:doll[7]=423
            with closing(sqlite3.connect(runtime/'database.sdb')) as db,db:
                db.execute('UPDATE characters SET class=?,level=?,exp=?,gender=1,map=?,x=?,y=?,"str"=?,"int"=?,wis=?,agi=?,"con"=?,cha=?,hp=1,tp=32000,statpoints=7,skillpoints=9,spells=?,paperdoll=?,inventory=?,admin=? WHERE name=? AND account=?',(clas,level,round(level**3*133.1),*location,*(attributes[k] for k in ('strength','intelligence','wisdom','agility','constitution','charisma')),spells if spells is not None else ''.join(f'{i},0;' for i in range(1,51)),','.join(map(str,doll)),'1,20000;375,4;3,4;21,1;493,1;',admin,fixture['character_name'],fixture['username']))
            time.sleep(.15)
            return attributes,gear
        def direct(fixture):
            from live_session import LiveSession
            s=LiveSession('127.0.0.1',18896);characters=s.login(fixture['username'],fixture['password'])['characters'];s.enter(next(c['id'] for c in characters if c['name']==fixture['character_name']));s.snapshot();return s
        def pump_until(s,predicate,timeout=8):
            end=time.monotonic()+timeout
            while time.monotonic()<end:
                s.poll_actions()
                if predicate():return
                if select.select([s.sock],[],[],.04)[0]:s.pump()
            raise AssertionError('Native event did not arrive')
        def near(nid):
            sys.path.insert(0,str(ROOT/'tools'));from import_eo import parse_emf
            for p in sorted((runtime/'data/maps').glob('*.emf')):
                world=parse_emf(p.read_bytes(),int(p.stem));npc=next((n for n in world['npcs'] if n['id']==nid),None)
                if not npc:continue
                blocked=set(map(tuple,world.get('server_blocked',world['blocked'])));warps={(w['x'],w['y']) for w in world['warps']}
                for dx,dy in [(0,1),(1,0),(-1,0),(0,-1)]:
                    x,y=npc['x']+dx,npc['y']+dy
                    if (x,y) not in blocked|warps:return world['id'],x,y
            raise AssertionError('Service has no valid fixture position')
        clients=[]
        try:
            start('native',['stdbuf','-oL','-eL',runtime/'etheos'],18896,runtime)
            fixtures={clas:provision() for clas in (2,3,4,5,6,7)};admin_fixture=provision();time.sleep(.65)
            for index,level in enumerate(() if args.skip_stat_builds else (1,8,15,25,35,45)):
                for clas,fixture in fixtures.items():
                    attributes,equipment=stage(fixture,clas,level,index)
                    s=direct(fixture)
                    try:
                        expected=stats(clas,level,attributes,equipment)
                        for key in ('min_damage','max_damage','accuracy','evade','armor','max_hp','max_tp','strength','intelligence','wisdom','agility','constitution','charisma'):
                            check(s.stats[key]==expected[key],f'Native {profile["classes"][str(clas)]["name"]} level {level} {key}: {s.stats[key]} == {expected[key]}')
                        results.append(dict(class_id=clas,level=level,stats={k:s.stats[k] for k in expected}))
                    finally:s.close()
                time.sleep(.25)
            # Raw packet rejection independently of Python's friendly validation.
            stage(fixtures[6],6,45);warrior=direct(fixtures[6])
            warrior.equip(498,remove=True);warrior.send(30,7,number(493,2)+number(0,1));time.sleep(.15);warrior.paperdoll()
            check(warrior.equipment['weapon']==0,'Native forged equip rejects a class-incompatible level-45 weapon')
            warrior.equip(498);tp=warrior.state['self']['tp'];warrior.timestamp+=1;start_tick=warrior.timestamp
            warrior.send(12,1,number(4,2)+number(start_tick,3));time.sleep(.55)
            warrior.send(12,30,number(1,1)+number(4,2)+number(start_tick+48,3));time.sleep(.3);warrior.refresh()
            check(warrior.state['self']['tp']==tp,'Native forged cross-class cast cannot consume TP or execute');warrior.close();time.sleep(.25)
            stage(fixtures[3],3,8);apprentice=direct(fixtures[3])
            apprentice.equip(205,remove=True);apprentice.send(30,7,number(493,2)+number(0,1));time.sleep(.15);apprentice.paperdoll()
            check(apprentice.equipment['weapon']==0,'Native forged equip rejects an under-level class weapon')
            apprentice.close();time.sleep(.3)
            start('gateway',[sys.executable,ROOT/'server/gateway.py','--port',18897,'--eo-port',18896],18897)
            start('websocket',[sys.executable,ROOT/'server/ws_gateway.py','--port',18898,'--tcp-port',18897,'--deps-dir',ROOT/'work/server-build/python'],18898)
            from bootstrap_ws import load
            load(ROOT/'work/server-build/python');from test_streaming import Client
            url='ws://127.0.0.1:18898/ws'
            stage(admin_fixture,6,45,admin=4)
            admin=Client(url,admin_fixture);clients.append(admin)
            # Temporary stationary targets use the actual native command.
            admin.call('chat_send',channel='local',message='$snpc 1 6 7')
            admin.until(lambda w:len([n for n in w['npcs'] if n['id']==1])>=6)
            for clas in (2,3,7):
                stage(fixtures[clas],clas,45);actor=Client(url,fixtures[clas]);clients.append(actor)
                check(actor.entry['balance_catalog']['version']==3 and len(actor.entry['balance_catalog']['items'])==611,'WebSocket delivers complete native balance catalog')
                spell_id={2:22,3:9,7:29}[clas];spell=profile['spells'][str(spell_id)];target=next(n for n in actor.state['npcs'] if n['id']==1)
                actor.worlds.clear();before=actor.entry['player']['tp'];actor.call('spell_cast',spell_id=spell_id,target_kind='npc',target_id=target['index'])
                world=actor.until(lambda w:any(e.get('spell_id')==spell_id and e.get('kind')=='npc_damage' for e in w.get('events',[])))
                event=next(e for e in world['events'] if e.get('spell_id')==spell_id and e.get('kind')=='npc_damage')
                power=spell_preview(clas,spell,actor.entry['player']['stats'])
                if event['damage']>0:check(int(power['min_damage']*100/120)<=event['damage']<=int(power['max_damage']*100/120),'Actual native caster damage matches class scaling and smooth armour')
                check(world['player']['tp']==before-spell['tp'],'Native offensive spell charges its exact TP once')
                if clas==2:
                    actor.worlds.clear();before_hp=world['player']['hp'];before_tp=world['player']['tp'];actor.call('spell_cast',spell_id=1,target_kind='self')
                    healed=actor.until(lambda w:any(e.get('kind')=='spell_heal' and e.get('spell_id')==1 for e in w.get('events',[])))
                    expected=spell_preview(clas,profile['spells']['1'],actor.entry['player']['stats'])['heal']
                    check(healed['player']['hp']-before_hp==expected,'Native healing scales with the appropriate class attributes')
                    check(healed['player']['tp']==before_tp-profile['spells']['1']['tp'],'Native self heal charges its published TP')
                if clas==3:
                    actor.worlds.clear();before=world['player']['tp'];actor.call('spell_cast',spell_id=14,target_kind='area')
                    area=actor.until(lambda w:any(e.get('kind')=='spell_area' and e.get('spell_id')==14 for e in w.get('events',[])))
                    event=next(e for e in area['events'] if e.get('kind')=='spell_area')
                    check(1<=event['targets']<=5 and area['player']['tp']==before-30,'Area spell caps targets and charges exactly once')
                actor.close();clients.remove(actor);time.sleep(.25)
            # Recheck real offensive and healing target packets after learning.
            stage(fixtures[6],6,45);restricted=direct(fixtures[6]);tp=restricted.state['self']['tp'];hp=restricted.state['self']['hp']
            target=next(n for n in restricted.state['npcs'] if n['id']==1)
            for ident,kind in [(1,'self'),(4,'npc'),(28,'self')]:
                restricted.timestamp+=200;tick=restricted.timestamp
                restricted.send(12,1,number(ident,2)+number(tick,3));time.sleep(.52)
                if kind=='self':restricted.send(12,30,number(1,1)+number(ident,2)+number(tick+48,3))
                else:restricted.send(12,31,number(2,1)+number(1,1)+number(1,2)+number(ident,2)+number(target['index'],2)+number(tick+48,3))
                time.sleep(.15);restricted.refresh()
                check(restricted.state['self']['tp']==tp and restricted.state['self']['hp']==hp,'Native rejects a learned off-class heal, spell or pet even with a valid raw target')
            restricted.close();time.sleep(.3)
            # A real class transition ejects bow, arrows and specialist armour.
            stage(fixtures[5],5,45,location=near(166))
            switcher=Client(url,fixtures[5]);clients.append(switcher);npc=next(n for n in switcher.state['npcs'] if n['id']==166)
            switcher.call('quest_open',npc_index=npc['index']);switcher.call('quest_reply',action=2)
            switcher.until(lambda w:w.get('quest_dialog') and any(l['id']==5 for l in w['quest_dialog']['links']))
            switcher.worlds.clear();switcher.call('quest_reply',action=5)
            swapped=switcher.until(lambda w:w['player']['stats'].get('class_id')==6)
            check(all(swapped['player']['equipment'][slot]==0 for slot in ('weapon','offhand','armor')),'Changing Archer to Warrior immediately removes bow, arrows and class armour')
            owned={i['id']:i['amount'] for i in swapped['player']['inventory']}
            check(all(owned.get(ident)==1 for ident in (496,423,507)),'Class-change equipment returns exactly once to its owner bag')
            expected_unarmed=stats(6,45,allocation(5,45),[])
            check(swapped['player']['stats']['max_damage']==expected_unarmed['max_damage'],f'Class-change damage equals the new class unarmed formula: {swapped["player"]["stats"]["max_damage"]} == {expected_unarmed["max_damage"]}')
            try:switcher.call('spell_cast',spell_id=1,target_kind='self')
            except AssertionError as exc:check('class' in str(exc).lower(),'Retained Priest healing is visibly locked after a class change')
            else:raise AssertionError('Warrior must not heal')
            switcher.close();clients.remove(switcher)
            # Native owned companions: summon, active assistance, replacement,
            # idle cutoff, dismissal and exhaustion (not fake local pets).
            stage(fixtures[7],7,45,location=(21,9,8))
            summoner=Client(url,fixtures[7]);clients.append(summoner)
            before=summoner.entry['player']['tp'];summoner.call('spell_cast',spell_id=28,target_kind='self')
            try:
                summoned=summoner.until(lambda w:any(e.get('kind')=='companion' and e.get('spell_id')==28 and e.get('npc_index') for e in w.get('events',[])))
            except Exception:
                (ROOT/'work/balance-v3/summon-failure.json').write_text(json.dumps(dict(player=summoner.state['player'],events=[w.get('events',[]) for w in summoner.worlds],npcs=summoner.state['npcs']),indent=2))
                raise
            pet=summoned['companion'];check(pet and pet['npc_id']==306 and summoned['player']['tp']==before-18,f'Summoner creates a visible native spirit with one exact initial TP charge: pet={pet}, TP={summoned["player"]["tp"]}, expected={before-18}')
            check(len([n for n in summoned['npcs'] if n['id'] in (306,307,308)])==1,'One native companion is owned at a time')
            target=next(n for n in summoned['npcs'] if n['id']==1);summoner.worlds.clear()
            summoner.call('spell_cast',spell_id=23,target_kind='npc',target_id=target['index'])
            assisted=summoner.until(lambda w:any(e.get('kind')=='companion_attack' and e.get('damage',0)>0 for e in w.get('events',[])),10)
            check(any(e.get('kind')=='companion_attack' and e.get('target_index')==target['index'] for e in assisted['events']),'Spirit assists only the monster actively commanded by its owner')
            time.sleep(5.5);summoner.call('refresh');summoner.worlds.clear();time.sleep(1.4);idle=summoner.call('refresh')
            check(not any(e.get('kind')=='companion_attack' for e in idle.get('events',[])),'Companion stops attacking after the owner stops active combat')
            for ident,npc_id in [(33,307),(34,308)]:
                summoner.worlds.clear();summoner.call('spell_cast',spell_id=ident,target_kind='self')
                replaced=summoner.until(lambda w:any(e.get('kind')=='companion' and e.get('spell_id')==ident and e.get('npc_id')==npc_id for e in w.get('events',[])))
                check(len([n for n in replaced['npcs'] if n['id'] in (306,307,308)])==1,'Upgrading a companion replaces its predecessor instead of stacking pets')
            summoner.worlds.clear();summoner.call('spell_cast',spell_id=35,target_kind='self')
            dismissed=summoner.until(lambda w:any(e.get('kind')=='companion' and e.get('spell_id')==35 and not e.get('npc_index') for e in w.get('events',[])))
            check(not dismissed['companion'] and not any(n['id'] in (306,307,308) for n in dismissed['npcs']),'Dismiss Companion removes the native NPC and its ownership state')
            summoner.close();clients.remove(summoner)
            stage(fixtures[7],7,45,location=(21,9,8))
            with closing(sqlite3.connect(runtime/'database.sdb')) as db,db:db.execute('UPDATE characters SET tp=18 WHERE name=?',(fixtures[7]['character_name'],))
            exhausted=Client(url,fixtures[7]);clients.append(exhausted);exhausted.call('spell_cast',spell_id=28,target_kind='self')
            exhausted.until(lambda w:any(e.get('kind')=='companion' and e.get('npc_index') for e in w.get('events',[])))
            exhausted.worlds.clear();ended=exhausted.until(lambda w:any(e.get('kind')=='companion' and not e.get('npc_index') for e in w.get('events',[])),6)
            check(ended['player']['tp']==0 and not ended['companion'],'Companion despawns when upkeep cannot be paid without negative mana')
            exhausted.close();clients.remove(exhausted)
            # A companion is session-bound and cannot survive changing class.
            stage(fixtures[7],7,45,location=near(166))
            owner=Client(url,fixtures[7]);clients.append(owner)
            owner.call('spell_cast',spell_id=28,target_kind='self')
            owner.until(lambda w:bool(w.get('companion')))
            npc=next(n for n in owner.state['npcs'] if n['id']==166)
            owner.call('quest_open',npc_index=npc['index']);owner.call('quest_reply',action=2)
            owner.until(lambda w:w.get('quest_dialog') and any(l['id']==5 for l in w['quest_dialog']['links']))
            owner.worlds.clear();owner.call('quest_reply',action=5)
            changed=owner.until(lambda w:w['player']['stats'].get('class_id')==6 and not w.get('companion'))
            check(not any(n['id'] in (306,307,308) for n in changed['npcs']),'Changing Summoner to Warrior immediately dismisses the native companion')
            owner.close();clients.remove(owner)
            stage(fixtures[7],7,45,location=(5,33,1))
            traveller=Client(url,fixtures[7]);clients.append(traveller)
            traveller.call('spell_cast',spell_id=28,target_kind='self');traveller.until(lambda w:bool(w.get('companion')))
            traveller.worlds.clear();traveller.call('move',direction=2,input_seq=1,map_id=5,x=33,y=0)
            travelled=traveller.until(lambda w:w['map_id']==4)
            check(not travelled.get('companion') and not any(n['id'] in (306,307,308) for n in travelled['npcs']),'Map travel dismisses the companion without leaking ownership into another map')
            traveller.close();clients.remove(traveller)
            stage(fixtures[7],7,45,location=(21,9,8))
            owner=Client(url,fixtures[7]);clients.append(owner)
            owner.call('spell_cast',spell_id=28,target_kind='self');owner.until(lambda w:bool(w.get('companion')))
            owner.close();clients.remove(owner);time.sleep(.8)
            returned=Client(url,fixtures[7]);clients.append(returned)
            check(not returned.entry.get('companion') and not any(n['id'] in (306,307,308) for n in returned.entry['npcs']),'Logging out removes the native pet; reconnect cannot inherit an orphan summon')
            returned.close();clients.remove(returned)
            # Actual targeted and party healing, with a nearby nonmember.
            for clas in (2,4,5):stage(fixtures[clas],clas,45)
            priest=Client(url,fixtures[2]);member=Client(url,fixtures[4]);outsider=Client(url,fixtures[5]);clients.extend([priest,member,outsider])
            pid=lambda c:c.entry['player']['player_id']
            priest.call('party_invite',player_id=pid(member));member.until(lambda w:bool(w.get('party_invitation')));member.call('party_accept')
            for actor in (priest,member):actor.until(lambda w:len(w.get('party',[]))==2)
            priest.worlds.clear();member.worlds.clear()
            priest.call('spell_cast',spell_id=2,target_kind='player',target_id=pid(member))
            target=member.until(lambda w:any(e.get('kind')=='spell_heal' and e.get('spell_id')==2 for e in w.get('events',[])))
            heal=spell_preview(2,profile['spells']['2'],priest.entry['player']['stats'])['heal']
            check(target['player']['hp']==1+heal,'Priest targeted heal changes another player by its exact scaled amount')
            priest.until(lambda w:w['player']['tp']==priest.entry['player']['tp']-8)
            for actor in (priest,member,outsider):actor.worlds.clear()
            priest.call('spell_cast',spell_id=3,target_kind='group')
            group=priest.until(lambda w:any(e.get('kind')=='spell_group' and e.get('spell_id')==3 for e in w.get('events',[])))
            event=next(e for e in group['events'] if e.get('kind')=='spell_group' and e.get('spell_id')==3)
            check({t['player_id'] for t in event['targets']}=={pid(priest),pid(member)},'Native Group Heal affects party members and excludes a nearby nonmember')
            check(group['player']['tp']==priest.entry['player']['tp']-8-28,'Group healing charges one published TP cost')
            member.until(lambda w:any(e.get('kind')=='spell_group' and e.get('spell_id')==3 for e in w.get('events',[])))
            check(outsider.call('refresh')['player']['hp']==1,'Group healing cannot heal nonmembers')
            for actor in (priest,member,outsider):actor.close();clients.remove(actor)
            time.sleep(.3)
            # Free rebuilding preserves known spells and refunds every investment.
            stage(fixtures[2],2,45,location=near(116),spells='1,12;2,3;22,4;')
            healer=Client(url,fixtures[2]);clients.append(healer);master=next(n for n in healer.state['npcs'] if n['id']==116)
            before=healer.entry['player']['stats'];healer.call('feature_open',kind='reset',npc_index=master['index']);reset=healer.call('feature_action',kind='reset',action='reset')
            check(reset['feature']['preserved_spells'] and {s['id'] for s in reset['player']['spells']}=={1,2,22},'Free rebuild retains learned spell ownership')
            check(reset['player']['stats']['stat_points']==7+45*3 and reset['player']['stats']['skill_points']==9+12+3+4,'Free rebuild refunds invested attribute and training points')
            check(all(s['level']==0 for s in reset['player']['spells']),'Free rebuild resets training without deleting spells')
            repeat=healer.call('feature_action',kind='reset',action='reset')
            check(repeat['player']['stats']['stat_points']==reset['player']['stats']['stat_points'] and repeat['player']['stats']['skill_points']==reset['player']['stats']['skill_points'],'Repeated rebuilding cannot mint points')
            # Learn a currently legal skill through the real native master.
            healer.call('skillmaster_open',npc_index=master['index']);learned=healer.call('skill_learn',spell_id=7)
            check(any(s['id']==7 for s in learned['player']['spells']),'Priest learns its level-gated heal at the native master')
            healer.close();clients.remove(healer);time.sleep(.3)
            # Wise Man quest vendor 4 is NPC 166 in the supplied world.
            stage(fixtures[2],2,45,location=near(166),spells='1,0;22,0;')
            chooser=Client(url,fixtures[2]);clients.append(chooser);npc=next(n for n in chooser.state['npcs'] if n['id']==166)
            chooser.call('quest_open',npc_index=npc['index']);chooser.call('quest_reply',action=2)
            chooser.until(lambda w:w.get('quest_dialog') and any(l['id']==6 for l in w['quest_dialog']['links']))
            chooser.worlds.clear();chooser.call('quest_reply',action=6);changed=chooser.until(lambda w:w['player']['stats'].get('class_id')==7)
            check(changed['player']['stats']['class_id']==7,'Wise Man makes Summoner available through native class selection')
            chooser.close();clients.remove(chooser);time.sleep(.3)
            # Existing shop and crafting handlers deliver the appended IDs.
            stage(fixtures[7],7,45,location=near(33))
            buyer=Client(url,fixtures[7]);clients.append(buyer);shop=next(n for n in buyer.state['npcs'] if n['id']==33)
            buyer.call('shop_open',npc_index=shop['index']);bought=buyer.call('shop_buy',item_id=513)
            check(any(i['id']==513 and i['amount']==1 for i in bought['player']['inventory']),'Intermediate spirit weapon is purchasable at an existing native shop')
            buyer.close();clients.remove(buyer)
            stage(fixtures[3],3,45,location=near(36))
            with closing(sqlite3.connect(runtime/'database.sdb')) as db,db:
                db.execute('UPDATE characters SET inventory=? WHERE name=?',('389,1;469,2;470,2;1,200;',fixtures[3]['character_name']))
            crafter=Client(url,fixtures[3]);clients.append(crafter);shop=next(n for n in crafter.state['npcs'] if n['id']==36)
            crafter.call('shop_open',npc_index=shop['index']);crafted=crafter.call('shop_craft',item_id=493)
            check({i['id']:i['amount'] for i in crafted['player']['inventory']}=={493:1},'Native final weapon recipe consumes exactly its listed equipment, boss materials and Gold')
            crafter.close();clients.remove(crafter)
            # Future coupon grants a bounded starter bundle, preserving old ledger semantics.
            stage(fixtures[6],6,45);coupon=Client(url,fixtures[6]);clients.append(coupon)
            before={i['id']:i['amount'] for i in coupon.entry['player']['inventory']};granted=coupon.call('redeem_code',code='KCPD108');after={i['id']:i['amount'] for i in granted['player']['inventory']}
            check(after[375]-before.get(375,0)==40 and after[1]-before.get(1,0)==1000 and after[21]-before.get(21,0)==1,'Native coupon grants only the revised starter bundle')
            coupon.close();clients.remove(coupon)
            if args.godot:
                stage(fixtures[3],3,45)
                fixture_path=base/'fixture.json';fixture_path.write_text(json.dumps(fixtures[3]));fixture_path.chmod(0o600)
                env=dict(os.environ,ASTER_VALE_BALANCE_FIXTURE=str(fixture_path),ASTER_VALE_TEST_HOST=url,ASTER_VALE_TEST_REPORT=str((base/'ui-report.json')),XDG_DATA_HOME=str(base/'godot-data'),XDG_CONFIG_HOME=str(base/'godot-config'))
                result=subprocess.run([str(args.godot.resolve()),'--headless','--path',str(ROOT/'client'),'--script','res://tests/balance_live.gd'],env=env,capture_output=True,text=True,timeout=90)
                (ROOT/'work/balance-v3/ui.log').write_text(result.stdout+result.stderr)
                check(result.returncode==0 and 'BALANCE LIVE:' in result.stdout and 'SCRIPT ERROR' not in result.stderr,'Real Godot client displays live class and spell metadata')
            report=dict(result='passed',checks=len(checks),native_stat_builds=results,benchmarks=benchmarks(profile),acceptance_checks=checks,live_player_database_opened=False)
            args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ('native_stat_builds','benchmarks','acceptance_checks')}))
        finally:
            for client in clients:
                try:client.close()
                except Exception:pass
            for p in reversed(processes):
                if p.poll() is None:
                    p.terminate()
                    try:p.wait(timeout=15)
                    except subprocess.TimeoutExpired:p.kill();p.wait()
            for stream in streams:stream.close()
            for name in ('native','gateway','websocket'):
                log=base/(name+'.log')
                if log.exists():shutil.copy2(log,ROOT/'work/balance-v3'/log.name)

if __name__=='__main__':main()
