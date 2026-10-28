"""Promote the requested test character while preserving every other stored value."""
from contextlib import closing
from pathlib import Path
import argparse,json,sqlite3

def promote(database,name='summontest',beside='skylar'):
    with closing(sqlite3.connect(database)) as db,db:
        db.execute('BEGIN IMMEDIATE');db.row_factory=sqlite3.Row
        target=db.execute('SELECT * FROM characters WHERE lower(name)=?',(name.lower(),)).fetchone()
        source=db.execute('SELECT account FROM characters WHERE lower(name)=?',(beside.lower(),)).fetchone()
        if not target or not source or target['account']!=source['account']:raise ValueError('Test character must exist on the reference character account')
        target=dict(target);old=target['admin'];rank=max(old,4)
        tables=[r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        snapshot={t:[tuple(r) for r in db.execute('SELECT * FROM "'+t.replace('"','""')+'"')] for t in tables}
        db.execute('UPDATE characters SET admin=? WHERE name=?',(rank,target['name']))
        after=dict(db.execute('SELECT * FROM characters WHERE name=?',(target['name'],)).fetchone())
        assert all(after[k]==v for k,v in target.items() if k!='admin') and after['admin']==rank
        for table,rows in snapshot.items():
            current=[tuple(r) for r in db.execute('SELECT * FROM "'+table.replace('"','""')+'"')]
            if table=='characters':
                cols=[r[1] for r in db.execute('PRAGMA table_info(characters)')];ni=cols.index('name');ai=cols.index('admin')
                rows=[tuple(rank if i==ai and r[ni]==target['name'] else v for i,v in enumerate(r)) for r in rows]
            assert sorted(current,key=repr)==sorted(rows,key=repr),'Unexpected change to '+table
    return dict(result='passed',character_name=target['name'],same_account_as=beside,previous_admin=old,admin=rank,only_requested_admin_field_changed=True,all_other_database_values_preserved=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',required=True,action='store_true');a=p.parse_args()
    print(json.dumps(promote(a.runtime/'database.sdb'),indent=2))
