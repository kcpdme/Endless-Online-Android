"""Independent checks tying generated catalog IDs/art to actual server PUBs."""
import hashlib
import json
import os
from pathlib import Path
import unittest
from export_catalog import parse_items, parse_npcs, pub_records, npc_frame_offset, NPC_RENDER_METADATA

ROOT=Path(__file__).resolve().parents[3]
RUNTIME=Path(os.environ.get('EO_RUNTIME',str(ROOT/'work/server-build/runtime')))
CONTENT=Path(__file__).resolve().parents[1]/'client/content'


class InvalidPubTests(unittest.TestCase):
    def test_wrong_signature_and_truncated_data_rejected(self):
        for data in [b'EIF',b'NOT'+b'\x01'*100]:
            with self.assertRaises(ValueError):parse_items(data)


@unittest.skipUnless((RUNTIME/'data/pub/dat001.eif').exists() and (CONTENT/'catalog.json').exists(),'runtime/catalog unavailable')
class RuntimeCatalogTests(unittest.TestCase):
    def setUp(self):
        self.catalog=json.loads((CONTENT/'catalog.json').read_text())
        self.manifest=json.loads((CONTENT/'manifest.json').read_text())
    def test_catalog_tracks_actual_server_pub_hashes(self):
        for source in self.catalog['source']['files'].values():
            self.assertEqual(source['sha256'],hashlib.sha256((RUNTIME/source['path']).read_bytes()).hexdigest())
        self.assertEqual(len(self.catalog['items']),490)
        self.assertEqual(len(self.catalog['npcs']),302)
        self.assertEqual(len(self.catalog['maps']),282)
        self.assertEqual(self.manifest['online_content']['catalog_sha256'],hashlib.sha256((CONTENT/'catalog.json').read_bytes()).hexdigest())
    def test_starter_definitions_match_actual_server_equipment(self):
        items=parse_items((RUNTIME/'data/pub/dat001.eif').read_bytes())
        for item_id,name,doll in [('21','Dagger',4),('80','Blue Boots',1),('143','Soldier Plate',1)]:
            self.assertEqual((items[item_id]['name'],items[item_id]['doll_graphic']),(name,doll))
            self.assertEqual(self.catalog['items'][item_id],items[item_id])
    def test_all_map5_spawn_npcs_resolve_to_real_graphics(self):
        selected=self.catalog['maps']['5']
        self.assertEqual((selected['name'],selected['width'],selected['height']),('Aeven',87,87))
        self.assertEqual(len(selected['npc_spawns']),26)
        for spawn in selected['npc_spawns']:
            definition=self.catalog['npcs'][str(spawn['id'])]
            self.assertIn(str(definition['graphic']),self.manifest['characters']['npcs'])
        self.assertEqual(len(self.manifest['characters']['npcs']),11)
    def test_all11_npc_offsets_match_reference_formulas(self):
        npcs=self.manifest['characters']['npcs']
        self.assertEqual(set(map(int,npcs)),set(NPC_RENDER_METADATA))
        for graphic,npc in npcs.items():
            metadata=NPC_RENDER_METADATA[int(graphic)]
            for direction in ['south','west','north','east']:
                self.assertEqual(npc['idle'][direction]['offset'],npc_frame_offset(metadata,direction,'idle',0))
                for state in ['frames','attack']:
                    for index,frame in enumerate(npc[state][direction]):
                        self.assertEqual(frame['offset'],npc_frame_offset(metadata,direction,state,index))
        # Independently calculated reference fixtures cover directional signs,
        # 23px baseline, and special second attack offsets for the city guards.
        guard=npcs['35']
        self.assertEqual(guard['idle']['south']['offset'],[-5,6])
        self.assertEqual(guard['idle']['east']['offset'],[5,6])
        self.assertEqual(guard['attack']['south'][1]['offset'],[-11,9])
        self.assertEqual(guard['attack']['north'][1]['offset'],[11,3])
        self.assertEqual(npcs['2']['idle']['south']['offset'],[0,5])
        self.assertEqual(npcs['54']['idle']['south']['offset'],[0,9])
    def test_all_five_money_piles_exist_and_thresholds_match_reference(self):
        piles=self.catalog['money_graphics']
        self.assertEqual([r['minimum_amount'] for r in piles],[0,2,100,10000,100000])
        self.assertEqual([r['ground'] for r in piles],['23:269','23:271','23:273','23:275','23:277'])
        for row in piles:
            metadata=self.manifest['graphics'][row['ground']]
            self.assertTrue((CONTENT/metadata['path'].removeprefix('res://content/')).is_file())

    def test_every_catalog_item_icon_and_ground_sprite_is_exported(self):
        self.assertEqual(self.catalog['missing_graphics'],[])
        for item in self.catalog['items'].values():
            if not item['graphic']:continue
            for role in ['icon','ground']:
                metadata=self.manifest['graphics'][item[role]]
                self.assertTrue((CONTENT/metadata['path'].removeprefix('res://content/')).is_file())


if __name__=='__main__':unittest.main(verbosity=2)
