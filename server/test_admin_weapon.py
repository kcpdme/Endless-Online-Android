"""Exact item stats, original record preservation and transactional grant safety."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from admin_weapon import ITEM_ID, NAME, patch_weapon, records, grant
from eo_session import number, Reader


def fixture():
    rows = []
    for ident in range(1, ITEM_ID+1):
        name = b'eof' if ident == ITEM_ID else b'Ultima Blade' if ident == 281 else f'Item {ident}'.encode()
        fields = bytearray(number(0, 1)*58)
        fields[2] = number(10, 1)[0]
        fields[32:35] = number(33, 3)
        rows.append(number(len(name), 1)+name+fields)
    return b'EIF'+number(1, 4)+number(len(rows), 2)+number(0, 1)+b''.join(rows)


class AdminWeaponTests(unittest.TestCase):
    def test_exact_stats_preserved_originals_and_idempotent(self):
        original = fixture(); updated, changed = patch_weapon(original)
        before = records(original); after = records(updated)
        self.assertTrue(changed)
        self.assertEqual([r[3] for r in before[:-1]], [r[3] for r in after[:ITEM_ID-1]])
        ident, name, fields, raw = after[ITEM_ID-1]
        self.assertEqual((ident, name), (ITEM_ID, NAME))
        self.assertEqual([Reader(fields[o:o+2]).num(2) for o in (9,11)], [1000,1000])
        self.assertEqual(Reader(fields[4:5]).num(), 4)
        self.assertEqual(Reader(fields[32:35]).num(3), 33)
        self.assertEqual(after[-1][3], before[-1][3])
        self.assertNotEqual(original[3:7], updated[3:7])
        self.assertEqual(patch_weapon(updated), (updated,False))
        with self.assertRaises(ValueError): patch_weapon(updated.replace(NAME.encode(), b'X'*len(NAME)))
        with self.assertRaises((ValueError,RuntimeError)): patch_weapon(original[:-1])

    def test_one_copy_inventory_only_and_transactional_rejection(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'database.sdb'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE characters(name TEXT PRIMARY KEY,admin INTEGER,inventory TEXT,paperdoll TEXT,spells TEXT)')
                db.executemany('INSERT INTO characters VALUES(?,?,?,?,?)', [('devadmin',4,'1,99;281,1;','0,0,0,0,0,0,0,0,21,','1,2;'),('devpeer',0,'1,33;','0,','1,0;')])
            self.assertTrue(grant(path,'DEVADMIN')['added'])
            self.assertFalse(grant(path,'devadmin')['added'])
            with self.assertRaises(ValueError): grant(path,'devpeer')
            with self.assertRaises(ValueError): grant(path,'missing')
            with sqlite3.connect(path) as db:
                self.assertEqual(db.execute('SELECT * FROM characters ORDER BY name').fetchall(), [('devadmin',4,'1,99;281,1;491,1;','0,0,0,0,0,0,0,0,21,','1,2;'),('devpeer',0,'1,33;','0,','1,0;')])
                self.assertEqual(db.execute('SELECT * FROM aster_admin_weapon_grants').fetchall(), [('devadmin',491)])
                db.execute("UPDATE characters SET inventory='1,99;',paperdoll='0,0,0,0,0,0,0,0,491,' WHERE name='devadmin'")
            self.assertFalse(grant(path,'devadmin')['added'])
