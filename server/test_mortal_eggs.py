"""Conservative migration and adapter contract for death-limited spirit bonds."""
import json,sqlite3,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
from configure_balance import migrate_pet_bonds
from balance_rules import check_hatch
from eo_session import EOError

class MortalEggTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.db=Path(self.tmp.name)/'characters.sdb'
        with sqlite3.connect(self.db) as db:
            db.execute('CREATE TABLE characters(name TEXT PRIMARY KEY, spells TEXT, inventory TEXT, skillpoints INT, exp INT)')
            db.execute('INSERT INTO characters VALUES (?,?,?,?,?)',('devone','23,4;28,3;33,2;34,1;35,0;','1,123;609,2;',7,888))
    def rows(self):
        with sqlite3.connect(self.db) as db:return db.execute('SELECT * FROM characters ORDER BY name').fetchall()
    def test_retains_strongest_bond_refunds_training_and_returns_other_eggs_once(self):
        report=migrate_pet_bonds(self.db)
        self.assertEqual(report,dict(already_applied=False,characters_changed=1,extra_bonds_returned_as_eggs=2,skill_points_refunded=6))
        row=self.rows()[0]
        self.assertEqual(row[1],'23,4;34,0;35,0;');self.assertEqual(row[3:],(13,888))
        self.assertEqual(dict(tuple(map(int,p.split(','))) for p in row[2].split(';') if p),{1:123,609:3,610:1})
        before=self.rows();self.assertTrue(migrate_pet_bonds(self.db)['already_applied']);self.assertEqual(before,self.rows())
    def test_failure_rolls_back_all_character_changes(self):
        with sqlite3.connect(self.db) as db:db.execute('INSERT INTO characters VALUES (?,?,?,?,?)',('devtwo','28,0;','bad inventory',7,999))
        before=self.rows()
        with self.assertRaises(ValueError):migrate_pet_bonds(self.db)
        self.assertEqual(before,self.rows())
    def test_any_existing_bond_prevents_consuming_another_egg(self):
        rules=dict(mortal_spirit_bonds=True,eggs={'609':dict(spell_id=28,level=8),'610':dict(spell_id=33,level=25)})
        session=SimpleNamespace(stats=dict(class_id=7,level=45),spells=[dict(id=33,level=0)])
        with patch('balance_rules.profile',return_value=rules):
            with self.assertRaisesRegex(EOError,'living pet bond'):check_hatch(session,609)
            session.spells=[];check_hatch(session,609)
            session.stats['class_id']=6
            with self.assertRaisesRegex(EOError,'Only Summoners'):check_hatch(session,609)
            session.stats.update(class_id=7,level=1)
            with self.assertRaisesRegex(EOError,'Reach level 8'):check_hatch(session,609)

if __name__=='__main__':unittest.main()
