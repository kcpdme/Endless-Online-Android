"""Starter policy and additive operator skill-grant persistence/rollback."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from configure_starters import configure
from grant_spells import grant, merge_spells
from eo_session import number


def esf():
    return b'ESF' + number(1, 4) + number(3, 2) + number(0, 1) + b''.join(number(len(name), 1) + number(0, 1) + name + number(0, 1) * 51 for name in (b'Heal Self', b'Small Heal', b'Group Heal'))


class StarterTests(unittest.TestCase):
    def test_policy_is_idempotent_preserves_private_settings_and_old_players(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'config.local.ini'
            p.write_text('StartItems = 21,1;80,1;143,1\nPasswordSalt = keep-private\nExpRate = 1000%\n')
            configure(td); before = p.read_bytes(); configure(td)
            self.assertEqual(p.read_bytes(), before)
            self.assertIn('PasswordSalt = keep-private\nExpRate = 1000%', p.read_text())
            self.assertIn('StartItemsMale = 1,1000;144,1;21,1;453,1', p.read_text())
            self.assertIn('StartItemsFemale = 1,1000;151,1;21,1;453,1', p.read_text())
            self.assertIn('StartSpells = 1,0', p.read_text())

    def test_grant_adds_missing_spells_preserves_levels_all_other_fields_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as td:
            dbpath = Path(td) / 'test.sdb'; pub = Path(td) / 'test.esf'; pub.write_bytes(esf())
            with sqlite3.connect(dbpath) as db:
                db.execute('CREATE TABLE characters (name TEXT PRIMARY KEY, spells TEXT, inventory TEXT, hp INT)')
                db.executemany('INSERT INTO characters VALUES (?,?,?,?)', [('devone', '1,42;9,7;', '1,777;', 333), ('devtwo', '', '21,2;', 444), ('other', '1,99;', '', 555)])
            result = grant(dbpath, pub, ['DevOne', 'devtwo'])
            self.assertEqual(result[0]['added'], [2, 3])
            with sqlite3.connect(dbpath) as db:
                rows = db.execute('SELECT * FROM characters ORDER BY name').fetchall()
            self.assertEqual(rows, [('devone', '1,42;9,7;2,0;3,0;', '1,777;', 333), ('devtwo', '1,0;2,0;3,0;', '21,2;', 444), ('other', '1,99;', '', 555)])
            self.assertTrue(all(not r['added'] for r in grant(dbpath, pub, ['devone', 'devtwo'])))
            with self.assertRaises(ValueError): grant(dbpath, pub, ['devone', 'missing'])
            with sqlite3.connect(dbpath) as db: self.assertEqual(db.execute('SELECT * FROM characters ORDER BY name').fetchall(), rows)

    def test_malformed_existing_spells_refuse_partial_grants(self):
        for value in ('1,2;1,3;', '1,-1;', '1,2,3;', 'bad'):
            with self.assertRaises(ValueError): merge_spells(value, [1, 2])


if __name__ == '__main__': unittest.main()
