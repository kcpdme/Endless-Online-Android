"""Operator-only, additive learned-spell grant; run ONLY with the world stopped.

The caller owns stopping services and a consistent private database backup.
Preserves existing training levels and every non-spell character/account field.
This utility is deliberately separate from the public gateway.
"""
import argparse
import json
from pathlib import Path
import sqlite3
from eo_session import Reader


def spell_ids(path):
    r = Reader(Path(path).read_bytes())
    if r.take(3) != b'ESF':
        raise ValueError('Expected native ESF spell definitions')
    r.take(4); count = r.num(2); r.num(); result = []
    for ident in range(1, count + 1):
        n, shout = r.num(), r.num()
        name = r.take(n).decode('latin1'); r.take(shout); r.take(51)
        if name.lower() == 'eof': break
        if name.strip(): result.append(ident)
    if not result: raise ValueError('No native spells found')
    return result


def merge_spells(value, ids):
    existing = {}
    for entry in value.split(';'):
        if not entry.strip(): continue
        pair = entry.split(',')
        if len(pair) != 2: raise ValueError('Invalid stored spell entry')
        ident, level = map(int, pair)
        if ident in existing or ident <= 0 or level < 0: raise ValueError('Invalid stored spell identity/level')
        existing[ident] = level
    added = [ident for ident in ids if ident not in existing]
    # Keep existing entries exactly as stored, append missing skills at level zero.
    merged = value.rstrip(';')
    for ident in added: merged += (';' if merged else '') + f'{ident},0'
    if added: merged += ';'
    return merged, added


def grant(database, esf, names):
    ids = spell_ids(esf)
    normalized = [name.strip().lower() for name in names]
    if len(set(normalized)) != len(normalized) or not normalized: raise ValueError('Choose unique character names')
    result = []
    with sqlite3.connect(database, timeout=10) as db:
        db.execute('BEGIN IMMEDIATE')
        # Validate all requested targets before changing any of them.
        rows = [db.execute('SELECT name, spells FROM characters WHERE name = ?', (name,)).fetchone() for name in normalized]
        if any(row is None for row in rows): raise ValueError('A requested character does not exist')
        for name, before in rows:
            after, added = merge_spells(before, ids)
            if added: db.execute('UPDATE characters SET spells = ? WHERE name = ? AND spells = ?', (after, name, before))
            result.append(dict(name=name, added=added, total_available_spells=len(ids), existing_training_preserved=True))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True, type=Path)
    parser.add_argument('--esf', required=True, type=Path)
    parser.add_argument('--characters', nargs='+', required=True)
    parser.add_argument('--world-stopped', action='store_true', required=True)
    args = parser.parse_args()
    print(json.dumps(grant(args.database, args.esf, args.characters), indent=2))
