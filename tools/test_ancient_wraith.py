import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from PIL import Image, ImageOps
from export_catalog import export_npc, UnsupportedNPCArt
from import_eo import PEBitmaps, read_member

ROOT=Path(__file__).resolve().parents[1]
ARCHIVE=ROOT/'reference/gfx.zip'

class BlankNPCPolicyTests(unittest.TestCase):
    def test_unknown_blank_standing_still_reports_missing_art(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(UnsupportedNPCArt):
                export_npc(2,'Test NPC',lambda *_:Image.new('RGBA',(45,67)),Path(d))

    def test_wraith_blank_attack_is_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'characters').mkdir()
            with self.assertRaisesRegex(UnsupportedNPCArt,'unexpected attack'):
                export_npc(171,'Ancient Wraith',lambda *_:Image.new('RGBA',(45,67)),Path(d))

    def test_ordinary_unused_blank_pose_keeps_existing_standing_fallback(self):
        def image(_gfx,gid):
            return Image.new('RGBA',(45,67),(100,80,60,255) if gid in range(41,45) else (0,0,0,0))
        with tempfile.TemporaryDirectory() as d:
            out=Path(d);(out/'characters').mkdir()
            npc=export_npc(2,'Rat',image,out)
            self.assertTrue(npc['pose_fallbacks'])
            self.assertNotIn('transparent_poses',npc)

@unittest.skipUnless(ARCHIVE.exists(),'Original graphics archive unavailable')
class OriginalAncientWraithTests(unittest.TestCase):
    def test_all_exported_directions_match_original_transparent_and_attack_pixels(self):
        with zipfile.ZipFile(ARCHIVE) as archive:
            source=PEBitmaps(read_member(archive,'gfx/gfx021.egf'))
        for gid in range(6801,6817):
            self.assertEqual(source.image(gid).getbbox() is None,gid<6813)
        with tempfile.TemporaryDirectory() as d:
            out=Path(d);(out/'characters').mkdir()
            npc=export_npc(171,'Ancient Wraith',lambda _gfx,gid:source.image(gid),out)
            self.assertEqual(npc['transparent_poses'],['frames','idle'])
            self.assertEqual(npc['pose_fallbacks'],[])
            for direction,flip in [('south',False),('east',True),('north',True),('west',False)]:
                for state in ('idle','frames','attack'):
                    rows=npc[state][direction]
                    rows=rows if isinstance(rows,list) else [rows]
                    for frame in rows:
                        expected=source.image(frame['source_graphic_id'])
                        if flip:expected=ImageOps.mirror(expected)
                        with Image.open(out/frame['path'].removeprefix('res://content/')) as actual:
                            self.assertEqual(actual.tobytes(),expected.tobytes())
                            self.assertEqual(actual.getbbox() is None,state!='attack')
                        if state!='attack':self.assertEqual(frame['visible_bounds'],[0,0,0,0])

    def test_installed_content_retains_native_wraith_room_and_resolves_real_art(self):
        catalog=json.loads((ROOT/'client/content/catalog.json').read_text())
        manifest=json.loads((ROOT/'client/content/manifest.json').read_text())
        self.assertEqual((catalog['npcs']['255']['name'],catalog['npcs']['255']['graphic']),('Ancient Wraith',171))
        spawns=[n for n in catalog['maps']['277']['npc_spawns'] if n['id']==255]
        self.assertEqual(sum(n['amount'] for n in spawns),9)
        self.assertIn('171',manifest['characters']['npcs'])
        self.assertNotIn(171,[r['npc_graphic'] for r in catalog['missing_graphics']])

if __name__=='__main__':unittest.main()
