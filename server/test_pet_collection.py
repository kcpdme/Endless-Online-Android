"""Permanent collection migration, private keepsakes and shared recovery metadata."""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import sqlite3,tempfile,unittest
from pet_collection import migrate_collection,state
from pet_catalog import EGGS,HATCHED_EGGS
from balance_rules import check_hatch
from eo_session import EOError

class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.db=Path(self.temp.name)/'world.sdb'
        with sqlite3.connect(self.db) as db:
            db.execute('CREATE TABLE characters(name TEXT,spells TEXT,inventory TEXT,bank TEXT,skillpoints INTEGER)')
            db.execute('INSERT INTO characters VALUES (?,?,?,?,?)',('devpets','23,4;28,2;33,3;34,1;35,0;','1,100;609,2;','626,1;',7))
    def row(self):
        with sqlite3.connect(self.db) as db:return db.execute('SELECT * FROM characters').fetchone()
    def test_keeps_all_pets_refunds_training_and_is_retry_safe(self):
        result=migrate_collection(self.db);row=self.row()
        self.assertEqual(result['pets_preserved'],3);self.assertEqual(result['skill_points_refunded'],6)
        self.assertEqual(row[1],'23,4;28,0;33,0;34,0;35,0;');self.assertEqual(row[4],13)
        bag=dict(tuple(map(int,p.split(','))) for p in row[2].split(';') if p)
        self.assertEqual(bag,{1:100,609:2,625:1,627:1});self.assertEqual(row[3],'626,1;')
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute('SELECT selected_spell,ready_at FROM aster_pet_state').fetchone(),(34,0))
            db.execute('UPDATE aster_pet_state SET ready_at=123456')
        self.assertTrue(migrate_collection(self.db)['already_applied']);self.assertEqual(row,self.row())
        with sqlite3.connect(self.db) as db:self.assertEqual(db.execute('SELECT ready_at FROM aster_pet_state').fetchone()[0],123456)
    def test_malformed_inventory_rolls_back_without_losing_a_pet(self):
        with sqlite3.connect(self.db) as db:db.execute('INSERT INTO characters VALUES (?,?,?,?,?)',('devbad','28,0;','broken','',0))
        before=self.row()
        with self.assertRaises(ValueError):migrate_collection(self.db)
        self.assertEqual(before,self.row())
    def test_full_bag_keeps_ownership_without_overflow(self):
        bag=''.join(f'{i},1;' for i in range(1,251))
        with sqlite3.connect(self.db) as db:db.execute('UPDATE characters SET inventory=?,bank=?',(bag,''))
        result=migrate_collection(self.db);self.assertEqual(result['deferred_keepsakes'],3)
        self.assertEqual(self.row()[2],bag);self.assertEqual(len(self.row()[1].split(';'))-1,5)
    def test_shared_native_timer_is_read_only_and_counts_down(self):
        session=SimpleNamespace(pet_selected_spell=34,pet_ready_at=400)
        with patch('balance_rules.profile',return_value={'pet_collection':True}),patch('pet_collection.time.monotonic',return_value=100):self.assertEqual(state(session),dict(selected_spell=34,cooldown_seconds=300))
        with patch('balance_rules.profile',return_value={'pet_collection':True}),patch('pet_collection.time.monotonic',return_value=401):self.assertEqual(state(session)['cooldown_seconds'],0)
        self.assertEqual(session.pet_ready_at,400)
    def test_second_species_allowed_and_duplicate_kept(self):
        session=SimpleNamespace(stats=dict(class_id=7,level=50),spells=[dict(id=28,level=0)])
        with patch('balance_rules.profile',return_value=dict(pet_collection=True,eggs={str(i):e for i,e in EGGS.items()})):
            check_hatch(session,610)
            with self.assertRaisesRegex(EOError,'already hatched'):check_hatch(session,609)
        self.assertEqual(len(HATCHED_EGGS),16)

if __name__=='__main__':unittest.main()
