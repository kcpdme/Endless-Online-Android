#!/usr/bin/env python3
"""Verify the actual Bone Spider spawn and kill/respawn in a disposable world."""
import argparse, hashlib, json, os, secrets, select, shutil, socket, sqlite3, subprocess, tempfile, time
from pathlib import Path
from eo_session import Session, Reader
from live_session import LiveSession
from test_online import dev_name


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--binary', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    a = p.parse_args()
    checks = []

    def check(ok, why):
        assert ok, why
        checks.append(why)

    with tempfile.TemporaryDirectory(prefix='aster-bone-spider-') as temp:
        r = Path(temp)/'runtime'
        shutil.copytree(a.runtime, r, ignore=shutil.ignore_patterns('database.sdb*', '*.log', 'etheos*'))
        shutil.copy2(a.binary, r/'etheos')
        os.environ['ASTER_VALE_RUNTIME'] = str(r)
        # Accelerate only the private world's respawn clock, retaining the real
        # 375-second map record and all actual geometry/NPC stats.
        cfg = r/'config.local.ini'
        cfg.write_text(cfg.read_text()+'\nPort = 18981\nIPReconnectLimit = 0\nSpawnRate = 1%\n')
        original = {name:hashlib.sha256((r/name).read_bytes()).hexdigest() for name in ('data/maps/00102.emf', 'data/pub/dtn001.enf')}
        reader = Reader((r/'data/maps/00102.emf').read_bytes()); reader.take(46)
        spawns = []
        for _ in range(reader.num()):
            x,y,ident,kind,delay,amount = reader.num(),reader.num(),reader.num(2),reader.num(),reader.num(2),reader.num()
            if ident == 183: spawns.append((x,y,kind,delay,amount))
        check(spawns == [(40,40,1,375,1)], 'Exactly one natural Bone Spider near 40,40 with a 375-second respawn')
        a.report.parent.mkdir(parents=True, exist_ok=True)
        log = a.report.with_suffix('.log').open('w')
        proc = subprocess.Popen([str(r/'etheos')], cwd=r, stdout=log, stderr=subprocess.STDOUT)
        s = None

        def pump(seconds=.04, stop=None):
            end = time.monotonic()+seconds
            while time.monotonic()<end:
                if stop and stop(): break
                if select.select([s.sock],[],[],min(.02,max(0,end-time.monotonic())))[0]: s.pump()

        def bone():
            return next((n for n in s.state['npcs'] if n['id']==183), None)

        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18981), timeout=.1): break
                except OSError: time.sleep(.05)
            time.sleep(.5)
            username,name,password = dev_name(),dev_name(),secrets.token_urlsafe(18)
            creator = Session(port=18981)
            try:
                creator.register(username,password); creator.login(username,password); creator.create_character(name)
            finally: creator.close()
            time.sleep(.3)
            gear = [0]*15; gear[8] = 457; gear[7] = 423
            with sqlite3.connect(r/'database.sdb') as db:
                db.execute('UPDATE characters SET map=102,x=40,y=35,class=5,level=50,hp=30000,tp=30000,"str"=1000,agi=1000,"con"=1000,paperdoll=? WHERE name=?', (','.join(map(str,gear)),name))
            s = LiveSession('127.0.0.1',18981)
            chars = s.login(username,password)['characters']; s.enter(chars[0]['id']); s.snapshot()
            check(bone() is not None, 'Natural Bone Spider is delivered in the real native snapshot at the admin landing')
            first = dict(bone())
            deadline = time.monotonic()+20
            while time.monotonic()<deadline:
                n = bone()
                if not n: break
                me = s.state['self']; dx,dy = n['x']-me['x'],n['y']-me['y']
                if dx==0 or dy==0:
                    s.strike(3 if dx>0 else 1 if dx<0 else 0 if dy>0 else 2)
                pump(.65, lambda: bone() is None)
            check(any(e.get('kind')=='npc_killed' and e.get('npc_index')==first['index'] for e in s.events), 'The natural Bone Spider can be attacked and killed')
            check(bone() is None, 'Killed Bone Spider leaves the visible NPC list')
            killed_at = time.monotonic()
            while bone() is None and time.monotonic()-killed_at<7: pump()
            respawn = time.monotonic()-killed_at
            check(bone() is not None and bone()['index']==first['index'], 'The same natural spawn returns after its respawn timer')
            # Native dead_since truncates to whole seconds, and the spawn
            # poll can add another interval. Measure from the observed death.
            check(2.5<respawn<6, 'Respawn matches 375 seconds scaled by the private 1% SpawnRate')
            check(all(hashlib.sha256((r/name).read_bytes()).hexdigest()==sha for name,sha in original.items()), 'Original map geometry, spawn record and NPC definitions remain unchanged')
            result = dict(result='passed', checks=checks, first_spawn=first, respawn_seconds=round(respawn,3), production_respawn_seconds=375, private_spawn_rate=.01, isolated_database=True)
            a.report.write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result))
        finally:
            if s: s.close()
            proc.terminate(); proc.wait(timeout=15); log.close()


if __name__ == '__main__': main()
