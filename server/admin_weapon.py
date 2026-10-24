"""Operator-only admin blade definition and one-time grant; stop/back up world first.

Not imported by the public gateway. Existing items and character equipment stay
unchanged. The caller owns backups and rollback across PUB/database files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
from eo_session import Reader, number

ITEM_ID = 491
TEMPLATE_ID = 281
NAME = "Skylar's Admin Blade"
DAMAGE = 1000


def records(data):
    r = Reader(data)
    if r.take(3) != b'EIF': raise ValueError('Expected native EIF')
    r.take(4); count = r.num(2); r.num(); result = []
    for ident in range(1, count + 1):
        start = r.pos
        name = r.take(r.num()).decode('latin1'); fields = r.take(58)
        result.append((ident, name, fields, data[start:r.pos]))
    if r.rest() or not result or result[-1][1].lower() != 'eof':
        raise ValueError('Expected a complete EIF ending with eof')
    return result


def patch_weapon(data):
    entries = records(data)
    if len(entries) < ITEM_ID or entries[TEMPLATE_ID-1][1] != 'Ultima Blade':
        raise ValueError('Unexpected native item catalog')
    fields = bytearray(entries[TEMPLATE_ID-1][2])
    if Reader(fields[2:3]).num() != 10 or Reader(fields[3:4]).num() != 0:
        raise ValueError('Template must remain a melee weapon')
    fields[4:5] = number(4, 1)  # Native Lore: cannot trade/drop, including death.
    fields[9:11] = number(DAMAGE, 2); fields[11:13] = number(DAMAGE, 2)
    fields[37:53] = b''.join(number(0, 2) for _ in range(8))
    fields[55:56] = number(0, 1)
    raw_name = NAME.encode('latin1')
    record = number(len(raw_name), 1) + raw_name + fields
    if entries[ITEM_ID-1][1] == NAME:
        if entries[ITEM_ID-1][3] != record: raise ValueError('Existing admin blade definition differs')
        return data, False
    if len(entries) != ITEM_ID or entries[-1][1].lower() != 'eof':
        raise ValueError('Admin blade item ID is occupied; do not overwrite another item')
    body = b''.join(entry[3] for entry in entries[:-1]) + record + entries[-1][3]
    revision = int.from_bytes(hashlib.sha256(body).digest()[:4], 'little') % (253**4)
    return data[:3] + number(revision, 4) + number(len(entries)+1, 2) + data[9:10] + body, True


def grant(database, character):
    character = character.strip().lower()
    with sqlite3.connect(database, timeout=10) as db:
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT name,admin,inventory,paperdoll FROM characters WHERE name=?', (character,)).fetchone()
        if row is None or row[1] < 4: raise ValueError('Grant requires the explicitly named administrator character')
        db.execute('CREATE TABLE IF NOT EXISTS aster_admin_weapon_grants (character TEXT NOT NULL, item_id INTEGER NOT NULL, PRIMARY KEY(character,item_id))')
        if db.execute('SELECT 1 FROM aster_admin_weapon_grants WHERE character=? AND item_id=?', (character, ITEM_ID)).fetchone():
            return dict(character=character, item_id=ITEM_ID, added=False, already_granted=True)
        inventory = row[2]
        owned = any(int(pair.split(',')[0]) == ITEM_ID and int(pair.split(',')[1]) > 0 for pair in inventory.split(';') if pair)
        owned = owned or ITEM_ID in [int(value) for value in row[3].split(',') if value]
        if not owned:
            updated = inventory + ('' if not inventory or inventory.endswith(';') else ';') + f'{ITEM_ID},1;'
            db.execute('UPDATE characters SET inventory=? WHERE name=? AND inventory=?', (updated, character, inventory))
        db.execute('INSERT INTO aster_admin_weapon_grants VALUES (?,?)', (character, ITEM_ID))
    return dict(character=character, item_id=ITEM_ID, added=not owned, already_granted=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--character', required=True)
    p.add_argument('--world-stopped', action='store_true', required=True)
    a = p.parse_args(); pub = a.runtime/'data/pub/dat001.eif'
    data, changed = patch_weapon(pub.read_bytes())
    if changed: pub.write_bytes(data)
    print(json.dumps(dict(pub_changed=changed, grant=grant(a.runtime/'database.sdb', a.character)), indent=2))
