"""Permanent native pet ownership migration and read-only collection snapshots."""
from collections import Counter
from contextlib import closing
import math
import sqlite3
import time
from pet_catalog import EGGS

def pairs(raw):
    values=[]
    for entry in raw.split(';'):
        if not entry:continue
        ident,value=map(int,entry.split(','))
        if ident<=0 or value<0:raise ValueError('Malformed pet migration data')
        values.append((ident,value))
    return values

def migrate_collection(database):
    """Preserve all known pets, refund training and create their bound keepsakes."""
    by_spell={e['spell_id']:e for e in EGGS.values()}
    report=dict(characters_changed=0,pets_preserved=0,hatched_keepsakes_added=0,deferred_keepsakes=0,skill_points_refunded=0)
    with closing(sqlite3.connect(database)) as db,db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('CREATE TABLE IF NOT EXISTS aster_pet_state (character_name VARCHAR(16) PRIMARY KEY, selected_spell INTEGER NOT NULL DEFAULT 0, ready_at INTEGER NOT NULL DEFAULT 0)')
        db.execute('CREATE TABLE IF NOT EXISTS aster_pet_collection_migrations (version INTEGER PRIMARY KEY)')
        if db.execute('SELECT 1 FROM aster_pet_collection_migrations WHERE version=12').fetchone():return dict(already_applied=True,**report)
        for name,raw,inventory,bank,points in db.execute('SELECT name,spells,inventory,bank,skillpoints FROM characters').fetchall():
            spells=pairs(raw);owned=[i for i,_ in spells if i in by_spell]
            if not owned:continue
            report['pets_preserved']+=len(owned)
            bag=Counter();stored=Counter()
            for i,n in pairs(inventory):bag[i]+=n
            for i,n in pairs(bank):stored[i]+=n
            if any(n<=0 for n in bag.values()) or any(n<=0 for n in stored.values()):raise ValueError('Malformed egg inventory')
            refunded=sum(n for i,n in spells if i in by_spell)
            if points+refunded>64000:raise ValueError('Skill point refund exceeds native capacity')
            changed=bool(refunded)
            for ident in owned:
                token=by_spell[ident]['hatched_id']
                if bag[token] or stored[token]:continue
                if len([i for i,n in bag.items() if n])>=250:
                    report['deferred_keepsakes']+=1;continue
                bag[token]=1;changed=True;report['hatched_keepsakes_added']+=1
            selected=max(owned,key=lambda i:by_spell[i]['level'])
            db.execute('INSERT OR IGNORE INTO aster_pet_state (character_name,selected_spell,ready_at) VALUES (?,?,0)',(name,selected))
            if changed:
                db.execute('UPDATE characters SET spells=?,inventory=?,skillpoints=? WHERE name=?',(''.join(f'{i},{0 if i in by_spell else n};' for i,n in spells),''.join(f'{i},{n};' for i,n in bag.items() if n),points+refunded,name))
                report['characters_changed']+=1;report['skill_points_refunded']+=refunded
        db.execute('INSERT INTO aster_pet_collection_migrations VALUES (12)')
    return dict(already_applied=False,**report)

def state(session):
    from balance_rules import profile
    if not profile().get('pet_collection'):return None
    return dict(selected_spell=int(getattr(session,'pet_selected_spell',0)),cooldown_seconds=max(0,math.ceil(getattr(session,'pet_ready_at',0)-time.monotonic())))
