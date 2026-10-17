"""Independent checks tying generated catalog IDs/art to actual server PUBs."""
import hashlib
import json
import os
from pathlib import Path
import unittest
from PIL import Image, ImageChops
from export_catalog import parse_items, parse_npcs, pub_records, npc_frame_offset, NPC_RENDER_METADATA, WEAPON_APPEARANCE_ITEMS

ROOT=Path(__file__).resolve().parents[1]
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
    def test_equipment_layers_preserve_original_composition_and_robe(self):
        data=self.manifest['characters']['equipment_layers']
        self.assertEqual(data['missing'],[])
        layers=data['layers']
        self.assertIn('armor:40',layers)  # Plaot Robes, native item407.
        self.assertEqual(self.catalog['items']['407']['size'],6)  # Original Size2x3.
        original=self.manifest['characters']['hero_variants']['a1_b1_w1']
        atlases={key:Image.open(CONTENT/layers[key]['idle']['south']['path'].removeprefix('res://content/')) for key in ['weapon_back:4','skin:0','boots:1','armor:1','hair:0','weapon_front:4']}
        try:
            for state in ('idle','frames','attack','cast'):
                for direction in ('south','east','north','west'):
                    frames=original[state][direction];frames=[frames] if isinstance(frames,dict) else frames
                    for index,frame in enumerate(frames):
                        composed=Image.new('RGBA',(192,192))
                        for key,atlas in atlases.items():
                            raw=layers[key][state][direction];part=raw if isinstance(raw,dict) else raw[index]
                            x,y,w,h=part['region'];composed.alpha_composite(atlas.crop((x,y,x+w,y+h)))
                        with Image.open(CONTENT/frame['path'].removeprefix('res://content/')) as expected:
                            self.assertIsNone(ImageChops.difference(composed.crop((48,96,144,192)),expected).getbbox(),(state,direction,index))
        finally:
            for atlas in atlases.values():atlas.close()
    def test_all_visible_equipment_and_native_body_choices_are_exported(self):
        data=self.manifest['characters']['equipment_layers'];layers=data['layers']
        self.assertEqual(data['version'],2);self.assertEqual(data['missing'],[])
        for gender,prefix in ((1,''),(0,'f:')):
            for race in range(7):self.assertIn(f'skin:{prefix}0'+(f':{race}' if race else ''),layers)
            for style in range(1,21):
                for color in range(10):self.assertIn(f'hair:{prefix}0'+(f':{style}:{color}' if (style,color)!=(1,0) else ''),layers)
            for item in self.catalog['items'].values():
                name={10:'weapon_back',11:'offhand',12:'armor',13:'head',14:'boots'}.get(item['type'])
                if not name or not item['doll_graphic'] or (item['type']==12 and item['gender']!=gender):continue
                key=f"{name}:{prefix}{item['doll_graphic']}"
                self.assertIn(key,layers,item['name'])
                self.assertEqual(len(layers[key]['frames']['south']),4)
        for key in ('head:44','head:f:44'):
            self.assertEqual(layers[key]['mask_mode'],'hide')
            with Image.open(CONTENT/layers[key]['idle']['south']['path'].removeprefix('res://content/')) as im:
                self.assertIsNotNone(im.getbbox())
                self.assertFalse(any(p[:3] in ((8,0,0),(0,0,0)) and p[3] for p in im.getdata()),'Helmet cannot retain black/red mask pixels')
        self.assertTrue(layers['offhand:10']['on_back']);self.assertFalse(layers['offhand:1']['on_back'])
    def test_original_hat_colorkeys_preserve_mask_only_when_required(self):
        from export_player_layers import hat_bitmap
        raw=Image.new('RGBA',(3,1));raw.putdata([(8,0,0,255),(0,0,0,255),(100,100,100,255)])
        self.assertEqual([p[3] for p in hat_bitmap(raw,1).getdata()],[0,255,255])
        for graphic in (7,44):self.assertEqual([p[3] for p in hat_bitmap(raw,graphic).getdata()],[0,0,255])
    def test_catalog_tracks_actual_server_pub_hashes(self):
        for source in self.catalog['source']['files'].values():
            self.assertEqual(source['sha256'],hashlib.sha256((RUNTIME/source['path']).read_bytes()).hexdigest())
        self.assertEqual(len(self.catalog['items']),490)
        self.assertEqual(len(self.catalog['npcs']),302)
        self.assertEqual(len(self.catalog['maps']),282)
        self.assertEqual(self.manifest['online_content']['catalog_sha256'],hashlib.sha256((CONTENT/'catalog.json').read_bytes()).hexdigest())
    def test_original_spell_definitions_icons_effect_frames_and_cast_pose(self):
        spells=self.catalog['spells'];self.assertEqual(len(spells),31)
        self.assertEqual((spells['1']['name'],spells['1']['tp'],spells['1']['hp']),('Heal Self',1,4))
        self.assertEqual((spells['4']['cast_time'],spells['4']['min_damage'],spells['4']['max_damage']),(2,1,5))
        for spell in spells.values():
            with Image.open(CONTENT/spell['icon'].removeprefix('res://content/')) as icon:self.assertIsNotNone(icon.getbbox())
            effect=spell['effect']
            for path in effect['paths'].values():
                with Image.open(CONTENT/path.removeprefix('res://content/')) as sheet:
                    self.assertEqual(sheet.width%effect['frames'],0)
                    self.assertGreater(sheet.width//effect['frames'],0)
        for hero in list(self.manifest['characters']['hero_variants'].values())+list(self.manifest['characters']['weapon_variants'].values()):
            self.assertIn(4,hero['source_resources']['gfx/gfx008.egf'])
            for direction in ('south','north','east','west'):
                pose=hero['cast'][direction][0]
                with Image.open(CONTENT/pose['path'].removeprefix('res://content/')) as image:self.assertIsNotNone(image.getbbox())

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

    def test_npc_head_bounds_match_original_visible_pixels(self):
        for npc in self.manifest['characters']['npcs'].values():
            for direction in ('south','east','north','west'):
                frames=npc['idle'][direction]
                for frame in frames if isinstance(frames,list) else [frames]:
                    with Image.open(CONTENT/frame['path'].removeprefix('res://content/')) as image:
                        x,y,right,bottom=image.getbbox()
                        self.assertEqual(frame['visible_bounds'],[x,y,right-x,bottom-y])

    def test_added_weapons_have_original_distinct_four_direction_appearances(self):
        variants=self.manifest['characters']['weapon_variants']
        self.assertEqual(len(variants),len(WEAPON_APPEARANCE_ITEMS)*4)
        distinct=[]
        for item_id in WEAPON_APPEARANCE_ITEMS:
            doll=self.catalog['items'][str(item_id)]['doll_graphic']
            hero=variants[f'a1_b1_g{doll}']
            self.assertEqual(hero['appearance']['weapon_graphic'],doll)
            self.assertIn((doll-1)*100+1,hero['source_resources']['gfx/gfx017.egf'])
            for state in ('idle','frames','attack'):
                for direction in ('south','east','north','west'):
                    frames=hero[state][direction]
                    for frame in frames if isinstance(frames,list) else [frames]:
                        with Image.open(CONTENT/frame['path'].removeprefix('res://content/')) as img:
                            self.assertIsNotNone(img.getbbox())
                            # Art must leave a transparent margin rather than clip.
                            self.assertIsNone(img.getchannel('A').crop((0,0,img.width,1)).getbbox())
            frame=hero['idle']['south']
            with Image.open(CONTENT/frame['path'].removeprefix('res://content/')) as img:distinct.append(img.tobytes())
        self.assertEqual(len(set(distinct)),len(WEAPON_APPEARANCE_ITEMS))

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
