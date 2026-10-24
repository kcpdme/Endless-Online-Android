"""Content installation preserves existing records/maps and is repeatable."""
import hashlib,shutil,tempfile,unittest
from pathlib import Path
from configure_feature_content import configure,pub_entries

BASE=Path(__file__).resolve().parents[1]/'work/server-build/runtime'

@unittest.skipUnless((BASE/'data/pub/dtn001.enf').exists(),'native sample resources unavailable')
class ContentTests(unittest.TestCase):
    def test_install_preserves_original_definitions_map_layers_and_admin_blade(self):
        with tempfile.TemporaryDirectory() as tmp:
            target=Path(tmp)/'runtime';shutil.copytree(BASE/'data',target/'data')
            source_npcs=pub_entries((target/'data/pub/dtn001.enf').read_bytes(),b'ENF',39)
            source_items=pub_entries((target/'data/pub/dat001.eif').read_bytes(),b'EIF',58)
            maps={mid:(target/f'data/maps/{mid:05d}.emf').read_bytes() for mid in [5,34,281]}
            report=configure(target)
            after_npcs=pub_entries((target/'data/pub/dtn001.enf').read_bytes(),b'ENF',39)
            after_items=pub_entries((target/'data/pub/dat001.eif').read_bytes(),b'EIF',58)
            self.assertEqual([r['raw'] for r in source_npcs[:-1]],[r['raw'] for r in after_npcs[:len(source_npcs)-1]])
            self.assertEqual([r['raw'] for r in source_items[:-1]],[r['raw'] for r in after_items[:len(source_items)-1]])
            self.assertEqual(after_items[490]['name'],"Skylar's Admin Blade")
            self.assertEqual(after_items[491]['name'],'Baru Flock')
            self.assertEqual(report['authored_quest_ids'],[13,14,24,52,53,54,55])
            from eo_session import Reader
            for mid,before in maps.items():
                after=(target/f'data/maps/{mid:05d}.emf').read_bytes()
                old_count=Reader(before[46:47]).num();new_count=Reader(after[46:47]).num()
                self.assertIn(new_count-old_count,(0,1))
                self.assertEqual(before[7:46],after[7:46])
                self.assertEqual(before[47:47+old_count*8],after[47:47+old_count*8])
                self.assertEqual(before[47+old_count*8:],after[47+new_count*8:])
            before={str(p.relative_to(target)):hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*') if p.is_file()}
            self.assertEqual(configure(target),report)
            after={str(p.relative_to(target)):hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*') if p.is_file()}
            self.assertEqual(before,after)
            self.assertFalse((target/'database.sdb').exists())

if __name__=='__main__':unittest.main()
