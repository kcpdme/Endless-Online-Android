"""Original arena records, Princess spawn preservation, and native arena notifications."""
import tempfile,shutil,unittest
from pathlib import Path
from configure_castle import configure,restore_princess,ARENAS
from eo_session import number,string,EOError
from test_live_state import fixture
ROOT=Path(__file__).resolve().parents[1]
RUNTIME=ROOT/'work/server-build/runtime'
SOURCE=ROOT/'reference/extracted/trunk-305-EODelta/trunk 305 EODelta/data/arenas.ini'
class ArenaPacketTests(unittest.TestCase):
    def test_start_busy_and_win_use_native_values_and_flush(self):
        s=fixture();s.apply_event(45,10,number(2,1));self.assertEqual((s.events[-1]['kind'],s.events[-1]['players']),('arena_start',2));self.assertTrue(s.dirty)
        s.apply_event(45,24,b'');self.assertEqual(s.events[-1]['kind'],'arena_busy')
        s.apply_event(45,2,string('winner')+number(3,4)+b'\xff'+string('winner')+string('loser'))
        self.assertEqual((s.events[-1]['kind'],s.events[-1]['winner'],s.events[-1]['kills']),('arena_win','winner',3));self.assertEqual(s.state['self']['x'],40)
    def test_elimination_matches_original_break_fields(self):
        s=fixture();s.apply_event(45,16,number(0,2)+b'\xff'+number(0,1)+b'\xff'+number(2,4)+b'\xff'+string('attacker')+string('victim'))
        self.assertEqual((s.events[-1]['kind'],s.events[-1]['killer'],s.events[-1]['victim'],s.events[-1]['kills']),('arena_kill','attacker','victim',2))
    def test_malformed_notifications_do_not_emit_partial_winners(self):
        s=fixture()
        for action,payload in [(10,b''),(24,b'x'),(2,b'bad'),(16,number(0,2)+b'x')]:
            with self.assertRaises((EOError,RuntimeError,ValueError)):s.apply_event(45,action,payload)
        self.assertFalse(any(e.get('kind') in ('arena_win','arena_start','arena_kill') for e in s.events))
@unittest.skipUnless(SOURCE.exists() and (RUNTIME/'data/maps/00281.emf').exists(),'supplied castle resources unavailable')
class CastleResourceTests(unittest.TestCase):
    def test_configuration_restores_exact_source_rules_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'data/maps').mkdir(parents=True);(p/'config.local.ini').write_text('ExpRate = 1000%\nDropRate = 200%\n')
            for mid in [*ARENAS,281]:shutil.copy2(RUNTIME/f'data/maps/{mid:05}.emf',p/f'data/maps/{mid:05}.emf')
            report=configure(p,SOURCE);first=(p/'data/maps/00281.emf').read_bytes();config=(p/'config.local.ini').read_bytes();configure(p,SOURCE)
            self.assertEqual(first,(p/'data/maps/00281.emf').read_bytes());self.assertEqual(config,(p/'config.local.ini').read_bytes())
            self.assertEqual(report['arenas'][46]['time'],'90');self.assertEqual(report['arenas'][137]['time'],'30');self.assertEqual(report['arenas'][183]['spawns'],'18,39, 16,12,  20,39, 16,28,  22,39, 22,20,  24,39, 28,28,  26,39, 28,12')
            self.assertNotIn('giveitem',(p/'data/aster-vale-arenas.ini').read_text());self.assertIn(b'ExpRate = 1000%',config)
    def test_private_map_symlink_does_not_change_its_source(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'runtime/data/maps').mkdir(parents=True);(p/'runtime/config.local.ini').write_text('')
            for mid in ARENAS:shutil.copy2(RUNTIME/f'data/maps/{mid:05}.emf',p/f'runtime/data/maps/{mid:05}.emf')
            import zipfile
            with zipfile.ZipFile(ROOT/'work/eoserv-crawl/downloads/sample-data.zip') as z:original=z.read('sample-data/maps/00281.emf')
            (p/'source.emf').write_bytes(original);target=p/'runtime/data/maps/00281.emf';target.symlink_to(p/'source.emf')
            configure(p/'runtime',SOURCE)
            self.assertEqual((p/'source.emf').read_bytes(),original);self.assertFalse(target.is_symlink());self.assertNotEqual(target.read_bytes(),original)
    def test_spawn_append_changes_no_map_art_warps_or_existing_entities(self):
        # Independently start from untouched supplied castle map bytes.
        import zipfile,sys
        sys.path.insert(0,str(ROOT/'tools'));from import_eo import parse_emf
        with zipfile.ZipFile(ROOT/'work/eoserv-crawl/downloads/sample-data.zip') as z:raw=z.read('sample-data/maps/00281.emf')
        updated,added=restore_princess(raw);self.assertTrue(added)
        before=parse_emf(raw,281);after=parse_emf(updated,281);princess=after['npcs'].pop()
        self.assertEqual(before,after);self.assertEqual(princess,dict(x=10,y=5,id=151,spawn_type=3,respawn=180,amount=1));self.assertNotIn([10,5],before['blocked'])
        self.assertEqual(restore_princess(updated),(updated,False))
if __name__=='__main__':unittest.main()
