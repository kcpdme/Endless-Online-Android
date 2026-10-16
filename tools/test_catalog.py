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
        self.assertEqual(len(self.manifest['characters']['npcs']),158)
    def test_all_world_npc_offsets_match_reference_formulas(self):
        npcs=self.manifest['characters']['npcs']
        self.assertTrue(set(map(int,npcs)).issubset(set(NPC_RENDER_METADATA)))
        for graphic,npc in npcs.items():
            metadata=NPC_RENDER_METADATA[int(graphic)]
            for direction in ['south','west','north','east']:
                idle=npc['idle'][direction]
                idle_frames=idle if isinstance(idle,list) else [idle]
                for index,frame in enumerate(idle_frames):self.assertEqual(frame['offset'],npc_frame_offset(metadata,direction,'idle',0 if frame.get('fallback_source_graphic_id') else index))
                for state in ['frames','attack']:
                    for index,frame in enumerate(npc[state][direction]):
                        self.assertEqual(frame['offset'],npc_frame_offset(metadata,direction,'idle' if frame.get('fallback_source_graphic_id') else state,0 if frame.get('fallback_source_graphic_id') else index))
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

    def test_all282_map_geometry_paths_and_graphics_resolve(self):
        for map_id,record in self.catalog['maps'].items():
            path=CONTENT/record['path'].removeprefix('res://content/')
            self.assertTrue(path.exists())
            world=json.loads(path.read_text())
            self.assertEqual((world['id'],world['name'],world['width'],world['height']),
                             (int(map_id),record['name'],record['width'],record['height']))
            for layer,entries in world['layers'].items():
                gfx=self.manifest['layer_gfx'][layer]
                for entry in entries:
                    if entry['id']:self.assertIn(f'{gfx}:{entry["id"]}',self.manifest['graphics'])
            if world['fill_tile']:self.assertIn(f'3:{world["fill_tile"]}',self.manifest['graphics'])
            self.assertIn('relog',world);self.assertIn('server_blocked',world)
    def test_actual_aeven_north_transition_and_return_fixture(self):
        world5=json.loads((CONTENT/'maps/00005.json').read_text())
        world4=json.loads((CONTENT/'maps/00004.json').read_text())
        outbound=next(w for w in world5['warps'] if (w['x'],w['y'])==(33,0))
        inbound=next(w for w in world4['warps'] if (w['x'],w['y'])==(19,48))
        self.assertEqual((outbound['map'],outbound['destination'],outbound['level'],outbound['door']),(4,[19,47],0,0))
        self.assertEqual((inbound['map'],inbound['destination']),(5,[33,1]))
        self.assertNotIn([19,47],world4['server_blocked'])
        self.assertNotIn([33,1],world5['server_blocked'])
    def test_world_validation_preserves_known_legacy_bad_warps(self):
        validation=self.catalog['world_validation']
        self.assertEqual(validation['warp_count'],3945)
        self.assertEqual(len(validation['reachable_from_start_ignoring_level_and_doors']),228)
        self.assertEqual(len(validation['unreachable_from_start']),54)
        self.assertEqual(len(validation['invalid_warps']),8)
        self.assertTrue(all(row['source_map']==47 for row in validation['invalid_warps']))

    def test_every_catalog_item_icon_and_ground_sprite_is_exported(self):
        self.assertEqual([r['npc_graphic'] for r in self.catalog['missing_graphics']],[171])
        for item in self.catalog['items'].values():
            if not item['graphic']:continue
            for role in ['icon','ground']:
                metadata=self.manifest['graphics'][item[role]]
                self.assertTrue((CONTENT/metadata['path'].removeprefix('res://content/')).is_file())


if __name__=='__main__':unittest.main(verbosity=2)
