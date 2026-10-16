#!/usr/bin/env python3
"""Real EO map transition + file negotiation round trip. Only edits its newly-created dev fixture."""
import argparse,json,pathlib,secrets,sqlite3,time
from eo_session import Session
from run import state_path
from test_online import provision,dev_name

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');p.add_argument('--report',type=pathlib.Path);p.add_argument('--credentials-out',type=pathlib.Path);a=p.parse_args()
    state=state_path(a.state_dir);database=state/'runtime/database.sdb';s,fixture=provision();character=fixture['character_name'];s.close();time.sleep(.5)
    assert character.startswith('dev') and fixture['username'].startswith('dev')
    # Put only this brand-new offline test character one tile from the known level-0 doorless exit.
    with sqlite3.connect(database) as db:
        assert db.execute('SELECT account FROM characters WHERE name=?',(character,)).fetchone()[0]==fixture['username']
        db.execute('UPDATE characters SET map=5,x=33,y=1 WHERE name=? AND account=?',(character,fixture['username']))
    def login():
        session=Session();reply=session.login(fixture['username'],fixture['password']);c=next(c for c in reply['characters'] if c['name']==character);session.enter(c['id']);return session
    s=login();start=s.refresh()['self'];assert (start['map_id'],start['x'],start['y'])==(5,33,1)
    outbound=s.walk(2)['self'];assert (outbound['map_id'],outbound['x'],outbound['y'])==(4,19,47),outbound
    outgoing=s.map_content[4];assert outgoing['sha256']==__import__('hashlib').sha256((state/'runtime/data/maps/00004.emf').read_bytes()).hexdigest()
    s.close();time.sleep(.5)
    with sqlite3.connect(f'file:{database}?mode=ro',uri=True) as db:row=db.execute('SELECT map,x,y FROM characters WHERE name=?',(character,)).fetchone()
    assert row==(4,19,47),row
    s=login();resumed=s.state['self'];assert (resumed['map_id'],resumed['x'],resumed['y'])==(4,19,47)
    inbound=s.walk(0)['self'];assert (inbound['map_id'],inbound['x'],inbound['y'])==(5,33,1),inbound
    incoming=s.map_content[5];assert incoming['sha256']==__import__('hashlib').sha256((state/'runtime/data/maps/00005.emf').read_bytes()).hexdigest()
    s.close();time.sleep(.5)
    with sqlite3.connect(f'file:{database}?mode=ro',uri=True) as db:final=db.execute('SELECT map,x,y FROM characters WHERE name=?',(character,)).fetchone()
    assert final==(5,33,1)
    report={'result':'passed','runtime':'actual pinned etheos over native EO v28','database_reset':False,
            'fixture_setup':'Only the newly created dev-prefixed test character was placed one tile from a real exit while offline.',
            'outbound':{'source':[5,33,1],'step_direction':2,'warp_tile':[33,0],'destination':[4,19,47],'authoritative_snapshot':True,'map_download':outgoing},
            'reconnect':{'sqlite_position_persisted':[4,19,47],'welcome_resumed':[4,19,47]},
            'return':{'step_direction':0,'warp_tile':[19,48],'destination':[5,33,1],'authoritative_snapshot':True,'map_download':incoming},
            'final_sqlite_position':[5,33,1],'limitations':'Geometry/rendering validation is separate; level/key requirements remain enforced by the server.'}
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    fixture.pop('character_id',None)
    if a.credentials_out:a.credentials_out.parent.mkdir(parents=True,exist_ok=True);a.credentials_out.write_text(json.dumps(fixture,indent=2)+'\n');a.credentials_out.chmod(0o600)
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
