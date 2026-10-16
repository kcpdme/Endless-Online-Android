"""Parser and real reference-data integration checks. Run from any directory.

Defaults expect workspace downloads; override EO_DATA_DIR for other machines.
"""
import io
import json
import os
from pathlib import Path
import re
import unittest
import zipfile
import struct
import wave
from PIL import Image
from import_eo import decode_number, decode_string, parse_emf, PEBitmaps, read_member, safe_spawn, canonical_wav, parse_eif

ROOT=Path(__file__).resolve().parents[3]
DOWNLOADS=Path(os.environ.get('EO_DATA_DIR',str(ROOT/'work/eoserv-crawl/downloads')))
CONTENT=Path(__file__).resolve().parents[1]/'client/content'


class EncodingTests(unittest.TestCase):
    def test_base253_examples_and_boundaries(self):
        for raw,expected in [(b'\x01',0),(b'\xfd',252),(b'\x01\x02',253),
                             (b'\x02\x02',254),(b'\xfd\xfd',64008),
                             (b'\x01\x01\x02',64009),(b'\x2b\xfe\xfe\xfe',42)]:
            self.assertEqual(decode_number(raw),expected)
    def test_invalid_encoded_bytes(self):
        for raw in [b'',b'\x00',b'\xff',b'12345']:
            with self.assertRaises(ValueError):decode_number(raw)
    def test_encoded_map_name(self):
        # Independent known encoded fixture captured from map5's 24-byte header.
        self.assertEqual(decode_string(bytes.fromhex('ffffffffffffffffffffffffffffffffffffff316829685e')),'Aeven')
    def test_truncated_map_rejected(self):
        with self.assertRaises(ValueError):parse_emf(b'EMF',5)
    def test_archive_traversal_and_limits_rejected(self):
        buffer=io.BytesIO()
        with zipfile.ZipFile(buffer,'w') as archive:
            archive.writestr('../escape',b'evil');archive.writestr('safe',b'12345')
        with zipfile.ZipFile(buffer) as archive:
            with self.assertRaises(ValueError):read_member(archive,'../escape')
            with self.assertRaises(ValueError):read_member(archive,'safe',limit=4)


@unittest.skipUnless((DOWNLOADS/'sample-data.zip').exists(),'reference source archives unavailable')
class RealDataTests(unittest.TestCase):
    def test_all_289_reference_maps_parse_and_consume_bytes(self):
        with zipfile.ZipFile(DOWNLOADS/'sample-data.zip') as archive:
            names=[n for n in archive.namelist() if '/maps/' in n and n.endswith('.emf')]
            self.assertEqual(len(names),289)
            for name in names:
                with self.subTest(name=name):
                    map_id=int(re.search(r'/(\d+)',name.rsplit('/',1)[0]+'/'+name.rsplit('/',1)[1]).group(1))
                    world=parse_emf(read_member(archive,name),map_id)
                    self.assertTrue(1<=world['width']<=253)
                    self.assertTrue(1<=world['height']<=253)
    def test_aeven_counts_and_safe_spawn(self):
        with zipfile.ZipFile(DOWNLOADS/'sample-data.zip') as archive:
            world=parse_emf(read_member(archive,'sample-data/maps/00005.emf'),5)
        self.assertEqual((world['name'],world['width'],world['height']),('Aeven',87,87))
        self.assertEqual(len(world['layers']['ground']),5098)
        self.assertEqual(len(world['npcs']),26)
        self.assertEqual(len(world['blocked']),982)
        spawn=safe_spawn(world);self.assertEqual(spawn,[40,40])
        blocked={tuple(v) for v in world['blocked']}
        for dx in range(-3,4):
            for dy in range(-3,4):self.assertNotIn((spawn[0]+dx,spawn[1]+dy),blocked)
    def test_real_pe_bitmap_resource_offsets_and_color_key(self):
        with zipfile.ZipFile(DOWNLOADS/'EOzipped028.zip') as archive:
            resources=PEBitmaps(read_member(archive,'gfx/gfx008.egf'))
        skin=resources.image(1)
        self.assertEqual(skin.size,(72,406))
        self.assertEqual(skin.getpixel((0,0))[3],0)
        self.assertIsNotNone(skin.getbbox())
        with self.assertRaises(KeyError):resources.image(99999)
    def test_real_audio_header_repair_and_valid_pcm(self):
        with zipfile.ZipFile(DOWNLOADS/'EOzipped028.zip') as archive:
            raw=read_member(archive,'sfx/sfx016.wav')
        canonical,metadata=canonical_wav(raw)
        self.assertTrue(metadata['header_repaired'])
        self.assertEqual(struct.unpack_from('<I',canonical,4)[0],len(canonical)-8)
        with wave.open(io.BytesIO(canonical)) as audio:
            self.assertEqual(audio.getframerate(),22050)
            self.assertEqual(audio.getnframes(),1258)
            self.assertEqual(len(audio.readframes(audio.getnframes())),2516)

    def test_classic_item_definitions_match_actual_rendered_outfit(self):
        with zipfile.ZipFile(DOWNLOADS/'EOzipped028.zip') as archive:
            items=parse_eif(read_member(archive,'pub/dat001.eif'))
        self.assertEqual((items[21]['name'],items[21]['graphic'],items[21]['doll_graphic']),('Dagger',38,4))
        self.assertEqual((items[143]['name'],items[143]['doll_graphic'],items[143]['gender']),('Soldier Plate',1,1))
        self.assertEqual((items[80]['name'],items[80]['doll_graphic']),('Blue Boots',1))
    def test_equipment_variants_have_distinct_visible_pixels(self):
        manifest=json.loads((CONTENT/'manifest.json').read_text())
        variants=manifest['characters']['hero_variants']
        self.assertEqual(len(variants),8)
        images=[]
        for key,value in variants.items():
            frame=value['idle']['south']
            with Image.open(CONTENT/frame['path'].removeprefix('res://content/')) as img:
                images.append(img.tobytes())
        self.assertEqual(len(set(images)),8)

    def test_export_complete_and_frame_dimensions(self):
        world=json.loads((CONTENT/'world.json').read_text());manifest=json.loads((CONTENT/'manifest.json').read_text())
        for layer,entries in world['layers'].items():
            gfx=manifest['layer_gfx'][layer]
            for entry in entries:
                if entry['id']:self.assertIn(f'{gfx}:{entry["id"]}',manifest['graphics'])
        for graphic in manifest['graphics'].values():
            path=CONTENT/graphic['path'].removeprefix('res://content/')
            with Image.open(path) as img:self.assertEqual(img.size,(graphic['width'],graphic['height']))
        character_sets=[v for k,v in manifest['characters'].items() if k!='hero_variants']+list(manifest['characters'].get('hero_variants',{}).values())
        for character in character_sets:
            for direction in ['south','east','north','west']:
                self.assertTrue(character['frames'][direction])
                for frame in character['frames'][direction]:
                    with Image.open(CONTENT/frame['path'].removeprefix('res://content/')) as img:
                        self.assertEqual(img.size,tuple(frame['region'][2:]));self.assertIsNotNone(img.getbbox())


if __name__=='__main__':unittest.main(verbosity=2)
