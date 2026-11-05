#!/usr/bin/env python3
"""Real Dragon Warrior buyback/crafting and hot rehash in a disposable native world."""
import argparse, hashlib, json, os, secrets, select, shutil, signal, socket, sqlite3, subprocess, tempfile, time
from pathlib import Path
from configure_dragon_warrior import configure
from configure_classic_economy import ini
from eo_session import Session, EOError
from live_session import LiveSession
from test_online import dev_name


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=Path,required=True); p.add_argument('--binary',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True); a=p.parse_args(); checks=[]
    def check(ok,why):
        assert ok,why
        checks.append(why)
    with tempfile.TemporaryDirectory(prefix='aster-dragon-warrior-') as td:
        r=Path(td)/'runtime'; shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','etheos*'))
        shutil.copy2(a.binary,r/'etheos'); os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini'; cfg.write_text(cfg.read_text()+'\nPort = 18982\nIPReconnectLimit = 0\n')
        untouched={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for parent in (r/'data/maps',r/'data/pub') for f in parent.iterdir() if f.is_file()}
        drops=(r/'data/aster-vale-drops.ini').read_bytes()
        raw=ini(drops.decode())['225'].split(',')
        chances={int(raw[i]):float(raw[i+3]) for i in range(0,len(raw),4)}
        check(all(chances.get(i)==1 for i in (456,458,459)), 'Actual runtime has Saw Sword, Draco and Dracota at 1% each')
        a.report.parent.mkdir(parents=True,exist_ok=True); log=a.report.with_suffix('.log').open('w')
        proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT); s=None
        def pump(seconds=.3):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                if select.select([s.sock],[],[],min(.02,max(0,end-time.monotonic())))[0]: s.pump()
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18982),timeout=.1): break
                except OSError: time.sleep(.05)
            time.sleep(.5)
            username,name,password=dev_name(),dev_name(),secrets.token_urlsafe(18)
            creator=Session(port=18982)
            try: creator.register(username,password); creator.login(username,password); creator.create_character(name)
            finally: creator.close()
            time.sleep(.3)
            with sqlite3.connect(r/'database.sdb') as db:
                db.execute('UPDATE characters SET map=269,x=13,y=14,class=6,level=50,hp=30000,tp=30000,"con"=1000,inventory=? WHERE name=?',('469,21;470,20;1,400;',name))
            s=LiveSession('127.0.0.1',18982); chars=s.login(username,password)['characters']; s.enter(chars[0]['id']); s.snapshot()
            npc=next(n for n in s.state['npcs'] if n['id']==253)
            before=s.shop_open(npc['index'])['shop']
            check([{k:offer[k] for k in ('id','buy','sell')} for offer in before['trade']]==[dict(id=469,buy=0,sell=250)], 'Native Dragon Warrior retains classic 250-Gold claw buyback')
            identity=s.player_id; configure(r); os.kill(proc.pid,signal.SIGHUP); pump(.7)
            shop=s.shop_open(npc['index'])['shop']
            check({row['id'] for row in shop['craft']}=={458,459}, 'Hot rehash exposes both armor recipes through real native shop packets')
            for recipe in shop['craft']:
                check(recipe['ingredients']==[dict(id=469,amount=10),dict(id=470,amount=10),dict(id=1,amount=200)], 'Native recipe ingredients fit protocol and match the advertised cost')
            check(s.player_id==identity and proc.poll() is None, 'Rehash preserves the connected character and world process')
            s.shop_trade('sell',469,1)
            check(s.item_amount(1)==650 and s.item_amount(469)==20, 'Selling one Dragon Claw pays exactly 250 Gold')
            s.shop_trade('craft',458); s.shop_trade('craft',459)
            expected={1:250,458:1,459:1}
            check({row['id']:row['amount'] for row in s.inventory}==expected, 'Crafting both genders consumes exact materials and Gold and delivers one of each')
            try: s.shop_trade('craft',458)
            except EOError as e: check('ingredients' in str(e), 'Missing materials reject another craft')
            else: raise AssertionError('Craft succeeded without materials')
            s.close(); s=None; time.sleep(.4)
            with sqlite3.connect(r/'database.sdb') as db:
                saved=db.execute('SELECT inventory FROM characters WHERE name=?',(name,)).fetchone()[0]
            parsed={int(pair.split(',')[0]):int(pair.split(',')[1]) for pair in saved.split(';') if pair}
            check(parsed==expected, 'Native inventory persists both crafted items and the exact remaining Gold')
            check((r/'data/aster-vale-drops.ini').read_bytes()==drops and all(hashlib.sha256((r/rel).read_bytes()).hexdigest()==sha for rel,sha in untouched.items()), 'Drop tables, all PUB definitions and all map geometry remain unchanged')
            result=dict(result='passed',checks=checks,shop=shop,dragon_drop_chances=chances,isolated_database=True,production_database_opened=False,hot_rehash_preserves_connection=True)
            a.report.write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result))
        finally:
            if s: s.close()
            proc.terminate(); proc.wait(timeout=15); log.close()


if __name__=='__main__': main()
