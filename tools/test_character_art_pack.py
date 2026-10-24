import copy
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image
from character_art_pack import stage, verify, publish, read, write, digest


class CharacterArtPackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        art = self.root / 'client/content/characters/skin.png'
        art.parent.mkdir(parents=True)
        Image.new('RGBA', (8, 8), (120, 80, 40, 255)).save(art)
        frame = dict(path='res://content/characters/skin.png', region=[0, 0, 8, 8], offset=[0, 8])
        self.layer = dict(idle=dict(south=frame), frames=dict(south=[copy.deepcopy(frame), copy.deepcopy(frame)]))
        write(self.root / 'client/content/manifest.json', dict(characters=dict(equipment_layers=dict(layers={'skin:0':self.layer})), map_paths={'5':'res://content/maps/5.json'}))
        self.original = digest(art)
        self.pack = self.root / 'client/art_packs/painted_v1'

    def complete(self):
        image = self.pack / 'draft/characters/skin.png'
        Image.new('RGBA', (16, 16), (180, 100, 40, 255)).save(image)
        layers = read(self.pack / 'draft/layers.json')
        for frame in [layers['skin:0']['idle']['south'], *layers['skin:0']['frames']['south']]:
            frame['region'] = [0, 0, 16, 16]; frame['pixel_scale'] = 2
        write(self.pack / 'draft/layers.json', layers)
        write(self.pack / 'draft/reviewed_layers.json', ['skin:0'])

    def test_staging_keeps_originals_and_excludes_drafts(self):
        result = stage(self.root, 'painted_v1')
        self.assertTrue(result['original_assets_unchanged'])
        self.assertEqual(result['maps_copied'], 0)
        self.assertEqual(read(self.pack / 'pack.json')['status'], 'draft')
        for folder in ('source', 'draft', 'concepts'):
            self.assertTrue((self.pack / folder / '.gdignore').exists())
        self.assertEqual(digest(self.root / 'client/content/characters/skin.png'), self.original)
        with self.assertRaises(ValueError): stage(self.root, 'painted_v1')

    def test_baseline_tampering_is_detected(self):
        stage(self.root, 'painted_v1')
        (self.root / 'client/content/characters/skin.png').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'Baseline'): verify(self.root, 'painted_v1')

    def test_no_unreviewed_or_unchanged_publication(self):
        stage(self.root, 'painted_v1')
        with self.assertRaisesRegex(ValueError, 'reviewed'): publish(self.root, 'painted_v1', 'stage01')
        write(self.pack / 'draft/reviewed_layers.json', ['skin:0'])
        with self.assertRaisesRegex(ValueError, 'unchanged'): publish(self.root, 'painted_v1', 'stage01')
        self.assertEqual(read(self.pack / 'pack.json')['status'], 'draft')

    def test_complete_release_is_separate_and_previous_release_survives(self):
        stage(self.root, 'painted_v1'); self.complete()
        self.assertEqual(publish(self.root, 'painted_v1', 'stage01')['layers'], 1)
        first = read(self.pack / 'pack.json')
        self.assertIn('/releases/stage01/', first['layers']['skin:0']['idle']['south']['path'])
        self.assertTrue(verify(self.root, 'painted_v1')['original_assets_unchanged'])
        (self.pack / 'draft/characters/skin.png').write_bytes(b'broken draft')
        self.assertEqual(read(self.pack / 'releases/stage01/pack.json'), first)
        with self.assertRaises(ValueError): publish(self.root, 'painted_v1', 'stage01')
        self.assertEqual(read(self.pack / 'pack.json'), first)

    def test_invalid_geometry_or_animation_cannot_publish(self):
        stage(self.root, 'painted_v1'); self.complete()
        valid = read(self.pack / 'draft/layers.json')
        for bad in ('offset', 'count', 'region', 'outside_pack'):
            layers = copy.deepcopy(valid); frame = layers['skin:0']['idle']['south']
            if bad == 'offset': frame['offset'] = [0, 10]
            if bad == 'count': layers['skin:0']['frames']['south'].pop()
            if bad == 'region': frame['region'][0] = 10
            if bad == 'outside_pack': frame['path'] = 'res://content/characters/skin.png'
            write(self.pack / 'draft/layers.json', layers)
            with self.assertRaises((ValueError, KeyError)): publish(self.root, 'painted_v1', 'stage01')
            self.assertEqual(read(self.pack / 'pack.json')['status'], 'draft')

    def test_pack_name_cannot_escape_asset_directory(self):
        with self.assertRaises(ValueError): stage(self.root, '../../content')

    def test_shared_npc_fix_does_not_invalidate_character_baseline(self):
        stage(self.root, 'painted_v1')
        path=self.root/'client/content/manifest.json'; manifest=read(path)
        manifest['characters']['npcs']={'171':{'transparent_poses':['idle','frames']}}
        write(path,manifest)
        self.assertTrue(verify(self.root,'painted_v1')['original_assets_unchanged'])
        manifest['characters']['equipment_layers']['layers']['skin:0']['idle']['south']['offset']=[0,9]
        write(path,manifest)
        with self.assertRaisesRegex(ValueError,'character layer definitions'):verify(self.root,'painted_v1')


if __name__ == '__main__': unittest.main()
