"""Original resource import repairs preserve source bytes and existing spawn policy."""
import unittest,tempfile,shutil,re
from pathlib import Path
from prepare_quests import prepare
from import_inns import install
ROOT=Path(__file__).resolve().parents[1]
RUNTIME=ROOT/'work/server-build/runtime'
SOURCE=ROOT/'reference/extracted/trunk-305-EODelta/trunk 305 EODelta/data/home.ini'

@unittest.skipUnless(SOURCE.exists(),'supplied original data unavailable')
class ContentRepairTests(unittest.TestCase):
    def test_native_quest_entry_and_cancel_fixes_preserve_original_text_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            q=Path(temp)/'quests';q.mkdir()
            originals={}
            for ident in (17,46):
                raw=(RUNTIME/f'data/quests/{ident:05}.txt').read_bytes();originals[ident]=raw;(q/f'{ident:05}.txt').write_bytes(raw)
            report=prepare(q)
            self.assertTrue(all(r['enabled'] for r in report))
            for ident,raw in originals.items():self.assertEqual((q/f'{ident:05}.txt').read_bytes(),raw)
            maze=(q/'00017.eqf').read_text(encoding='latin1');limbo=(q/'00046.eqf').read_text(encoding='latin1')
            self.assertRegex(maze,r'TalkedToNpc\(\s*17\s*\) goto GoReset')
            self.assertRegex(limbo,r'state Begin\s*\{\s*action SetState\("Begin1"\);')
            self.assertIn('state Begin1',limbo) # old saved states stay valid
    def test_five_inns_with_correct_vendor_ids_beds_and_idempotent_import(self):
        with tempfile.TemporaryDirectory() as temp:
            r=Path(temp);(r/'data/pub').mkdir(parents=True);(r/'data/maps').symlink_to(RUNTIME/'data/maps',target_is_directory=True)
            shutil.copy2(RUNTIME/'data/pub/dtn001.enf',r/'data/pub/dtn001.enf')
            (r/'data/aster-vale-home.ini').write_text('Version = 2\naeven.name = Aeven\naeven.location = 5, 40,40\nlevel.0 = aeven\n')
            report=install(r,SOURCE);first=(r/'data/aster-vale-home.ini').read_bytes()
            self.assertEqual(len(report['inns']),5)
            self.assertIn(b'aeven.location = 5, 40,40',first);self.assertIn(b'level.0 = aeven',first)
            self.assertIn(b'aeven.innkeeper = 2',first);self.assertIn(b'aeven.sleep = 86, 4, 8',first)
            self.assertIn(b'aeven.question1 = How many houses',first)
            install(r,SOURCE);self.assertEqual((r/'data/aster-vale-home.ini').read_bytes(),first)

if __name__=='__main__':unittest.main()
