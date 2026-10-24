"""Verify exact travel repair, preservation and already-fixed setup behavior."""
import sys,unittest
from pathlib import Path
from configure_travel import repair,EXITS
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'work/feature-content-runtime/data/maps/00048.emf'

@unittest.skipUnless(BASE.exists(),'reference map unavailable')
class TravelTests(unittest.TestCase):
    def test_only_three_wall_specs_change_and_repair_is_idempotent(self):
        sys.path.insert(0,str(ROOT/'tools'));from import_eo import parse_emf
        raw=BASE.read_bytes();updated,removed=repair(raw);before=parse_emf(raw,48);after=parse_emf(updated,48)
        self.assertEqual(set(map(tuple,removed)),set(EXITS))
        before['tile_specs']=[s for s in before['tile_specs'] if (s['x'],s['y']) not in EXITS]
        before['blocked']=[p for p in before['blocked'] if tuple(p) not in EXITS]
        self.assertEqual(before,after)
        self.assertEqual(repair(updated),(updated,[]))
        corrupt=bytearray(raw);corrupt[0]=0
        with self.assertRaises(ValueError):repair(bytes(corrupt))

if __name__=='__main__':unittest.main()
