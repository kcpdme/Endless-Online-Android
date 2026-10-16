#!/usr/bin/env python3
"""Equip every added original weapon on a fresh level-50 dev character."""
import argparse,json,pathlib,sqlite3,time,os,subprocess,tempfile
from test_online import provision
from live_session import LiveSession
from run import state_path

WEAPONS=(19,22,32,37,38,281)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);p.add_argument('--godot',type=pathlib.Path);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');a=p.parse_args()
    base,f=provision();base.close();time.sleep(.6)
    assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
    with sqlite3.connect(state_path(a.state_dir)/'runtime/database.sdb') as db:
        db.execute('UPDATE characters SET level=50,exp=16637500,inventory=? WHERE account=? AND name=?',('1,1000000;'+''.join(f'{i},1;' for i in WEAPONS),f['username'],f['character_name']))
    s=LiveSession()
    try:
        characters=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in characters if c['name']==f['character_name']))
        assert s.stats['level']==50 and next(i['amount'] for i in s.inventory if i['id']==1)==1000000
        for weapon in WEAPONS:
            current=s.equipment.get('weapon',0)
            if current:s.equip(current,remove=True)
            s.equip(weapon)
            assert s.equipment['weapon']==weapon
            assert not any(i['id']==weapon for i in s.inventory)
            s.equip(weapon,remove=True)
            assert s.equipment['weapon']==0 and next(i['amount'] for i in s.inventory if i['id']==weapon)==1
    finally:s.close()
    time.sleep(.6)
    s=LiveSession()
    try:
        characters=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in characters if c['name']==f['character_name']))
        assert s.stats['level']==50
        assert all(any(i['id']==weapon and i['amount']==1 for i in s.inventory) for weapon in WEAPONS)
        assert next(i['amount'] for i in s.inventory if i['id']==1)==1000000
    finally:s.close()
    report=dict(result='passed',fresh_dev_fixture_only=True,level_50_and_million_gold_persist=True,original_weapons_equip_unequip_and_inventory_receipts=list(WEAPONS),all_weapons_persist_after_relogin=True)
    if a.godot:
        time.sleep(.6)
        with tempfile.TemporaryDirectory(prefix='astervale-weapons-') as temp:
            env=dict(os.environ,XDG_DATA_HOME=temp,XDG_CONFIG_HOME=temp,ASTER_VALE_TEST_HOST=a.url,ASTER_VALE_TEST_USERNAME=f['username'],ASTER_VALE_TEST_PASSWORD=f['password'])
            root=pathlib.Path(__file__).resolve().parents[1]
            result=subprocess.run([str(a.godot.resolve()),'--headless','--path',str(root/'client'),'--script','res://tests/weapons_live.gd'],env=env,capture_output=True,text=True,timeout=100)
            print(result.stdout+result.stderr)
            assert result.returncode==0 and 'WEAPONS LIVE PASS:' in result.stdout and 'SCRIPT ERROR:' not in result.stderr
        report['godot_six_equips_five_one_tap_swaps_original_appearances_bag_conservation']=True
    if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
