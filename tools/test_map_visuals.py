"""Keep the approach chest visible without moving native collision or loot."""
import copy
import unittest
import json
import zipfile
from PIL import Image
from pathlib import Path
from import_eo import parse_emf
from import_eo import PEBitmaps,read_member
from map_visuals import restore_chest_art

ROOT=Path(__file__).resolve().parents[1]

class ChestVisualTests(unittest.TestCase):
    def test_original_missing_art_is_restored_at_the_actual_blocked_chest(self):
        world=parse_emf((ROOT/'work/server-build/runtime/data/maps/00136.emf').read_bytes(),136)
        before=copy.deepcopy(world)
        self.assertFalse(any((o['x'],o['y'])==(7,55) for o in world['layers']['objects']))
        restore_chest_art(world)
        self.assertIn(dict(x=7,y=55,id=247),world['layers']['objects'])
        self.assertEqual(world['tile_specs'],before['tile_specs'])
        self.assertEqual(world['chests'],before['chests'])
        self.assertEqual(world['blocked'],before['blocked'])
        self.assertEqual(world['warps'],before['warps'])
        self.assertEqual(world['npcs'],before['npcs'])
        self.assertEqual(len(world['layers']['objects']),len(before['layers']['objects'])+1)
        for layer,entries in before['layers'].items():
            if layer!='objects':self.assertEqual(world['layers'][layer],entries)
        repaired=copy.deepcopy(world);restore_chest_art(world)
        self.assertEqual(world,repaired)

    def test_other_maps_are_unchanged(self):
        world=dict(id=53);restore_chest_art(world)
        self.assertEqual(world,dict(id=53))

    def test_golden_chest_art_is_an_original_walkable_portal_not_a_loot_chest(self):
        world=parse_emf((ROOT/'work/server-build/runtime/data/maps/00136.emf').read_bytes(),136)
        restore_chest_art(world)
        self.assertIn(dict(x=7,y=46,id=250),world['layers']['objects'])
        self.assertFalse(any((s['x'],s['y'],s['spec'])==(7,46,9) for s in world['tile_specs']))
        portal=next(w for w in world['warps'] if (w['x'],w['y'])==(7,46))
        self.assertEqual((portal['map'],portal['destination']),(136,[7,84]))
        self.assertNotIn([7,46],world['blocked'])
        self.assertFalse(any((c['x'],c['y'])==(7,46) for c in world['chests']))

    def test_minimap_atlas_is_the_original_nine_cell_resource(self):
        with zipfile.ZipFile(ROOT/'work/eoserv-crawl/downloads/EOzipped028.zip') as archive:
            original=PEBitmaps(read_member(archive,'gfx/gfx002.egf')).image(45)
        manifest=json.loads((ROOT/'client/content/manifest.json').read_text())
        self.assertEqual(manifest['minimap']['cells'],9)
        record=manifest['graphics']['2:45']
        with Image.open(ROOT/'client'/record['path'].removeprefix('res://')) as exported:
            self.assertEqual(exported.size,original.size)
            self.assertEqual(exported.tobytes(),original.tobytes())

if __name__=='__main__':unittest.main()
