#!/usr/bin/env python3
"""Export all runtime EO map geometry, graphics, and read-only PUB definitions.

Input is actual staged server data, not client-v28 PUB assumptions. Output is
ignored local development content. Catalog is descriptive; the server remains
sole authority for combat, movement, inventory, NPC state, and item ownership.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from collections import OrderedDict
from PIL import ImageOps
from import_eo import Reader, decode_number, parse_emf, PEBitmaps, read_member, write_json, LAYER_GFX, export_hero


def pub_records(data,signature,size,names=1):
    r=Reader(data)
    if r.take(3)!=signature.encode():raise ValueError(f'not a {signature} PUB file')
    r.take(4);count=r.num(2);r.num();records={}
    for record_id in range(1,count+1):
        lengths=[r.num() for _ in range(names)]
        text=[r.take(n).decode('ascii',errors='replace') for n in lengths]
        fields=r.take(size)
        if text[0].lower()=='eof':break
        records[record_id]=(text,fields)
    if r.pos!=len(data):raise ValueError(f'{signature} unconsumed bytes {len(data)-r.pos}')
    return records


def parse_items(data):
    items={}
    for item_id,(names,f) in pub_records(data,'EIF',58).items():
        number=lambda start,size=1:decode_number(f[start:start+size])
        graphic=number(0,2)
        items[str(item_id)]={'id':item_id,'name':names[0],'graphic':graphic,
          'type':number(2),'subtype':number(3),'special':number(4),
          'hp':number(5,2),'tp':number(7,2),'min_damage':number(9,2),'max_damage':number(11,2),
          'accuracy':number(13,2),'evade':number(15,2),'armor':number(17,2),
          **{key:number(20+i) for i,key in enumerate(['strength','intelligence','wisdom','agility','constitution','charisma'])},
          **{key+'_requirement':number(41+i*2,2) for i,key in enumerate(['strength','intelligence','wisdom','agility','constitution','charisma'])},
          'doll_graphic':number(32,3),'gender':number(35),'level_requirement':number(37,2),
          'class_requirement':number(39,2),'weight':number(55),'size':number(57),
          'icon':f'23:{graphic*2}' if graphic else None,
          'ground':f'23:{graphic*2-1}' if graphic else None}
    return items


def parse_classes(data):
    return {str(id):{'id':id,'name':names[0],'base':decode_number(f[:1]),'type':decode_number(f[1:2])}
            for id,(names,f) in pub_records(data,'ECF',14).items()}


def parse_npcs(data):
    npcs={}
    for npc_id,(names,f) in pub_records(data,'ENF',39).items():
        number=lambda start,size=1:decode_number(f[start:start+size])
        npcs[str(npc_id)]={'id':npc_id,'name':names[0],'graphic':number(0,2),
          'boss':number(3,2),'child':number(5,2),'type':number(7,2),
          'vendor_id':number(9,2),'hp':number(11,3),'min_damage':number(16,2),
          'max_damage':number(18,2),'accuracy':number(20,2),'evade':number(22,2),
          'armor':number(24,2),'exp':number(36,3)}
    return npcs


from npc_render_metadata import NPC_RENDER_METADATA, NPC_STANDING_ANIMATION
SERVER_BLOCKING_SPECS={0,1,2,3,4,5,6,7,9,16,18,20,21,22,23,24,25,26,27,28}

MONEY_GRAPHICS=[{'minimum_amount':amount,'ground':f'23:{gid}'}
                for amount,gid in [(0,269),(2,271),(100,273),(10000,275),(100000,277)]]
WEAPON_APPEARANCE_ITEMS=(19,22,32,37,38,281)


def npc_frame_offset(metadata,direction,state,index):
    x,y,attack_x,attack_y,_=metadata
    horizontal_sign=-1 if direction in ('north','east') else 1
    attack_vertical_sign=-1 if direction in ('south','east') else 1
    if state=='attack' and index==1:
        return [(x+attack_x)*horizontal_sign,23-y+attack_y*attack_vertical_sign]
    return [x*horizontal_sign,23-y]


class UnsupportedNPCArt(ValueError):pass


def export_npc(graphic,definition_name,image,out):
    npc={'name':definition_name,'graphic':graphic,'idle':{},'frames':{},'attack':{},
         'source_member':'gfx/gfx021.egf'}
    metadata=NPC_RENDER_METADATA[graphic]
    npc['render_metadata']=dict(zip(['x_offset','y_offset','attack_x_offset','attack_y_offset','name_label_offset'],metadata))
    npc['render_metadata']['source']='EndlessClient NPCMetadataProvider.cs / NPCRenderer.UpdateDrawAreas'
    npc['animate_idle']=graphic in NPC_STANDING_ANIMATION
    base=(graphic-1)*40
    standing={gid:image(21,base+gid) for gid in range(1,5)}
    usable_standing=[gid for gid,img in standing.items() if img.getbbox()]
    if not usable_standing:raise UnsupportedNPCArt(f'NPC graphic{graphic} has no visible original standing art')
    npc['pose_fallbacks']=[]
    for direction,back,flip in [('south',0,False),('east',0,True),('north',1,True),('west',1,False)]:
        for state,offsets in [('idle',([1+back*2,2+back*2] if npc['animate_idle'] else [1+back*2])),('frames',[5+back*4+i for i in range(4)]),('attack',[13+back*2+i for i in range(2)])]:
            frames=[]
            for index,offset in enumerate(offsets):
                frame=image(21,base+offset)
                fallback=None
                if not frame.getbbox():
                    fallback=next((gid for gid in [1+back*2,2+back*2]+usable_standing if gid in usable_standing))
                    frame=standing[fallback]
                    npc['pose_fallbacks'].append({'state':state,'direction':direction,'frame':index,'blank_source_graphic_id':base+offset,'fallback_source_graphic_id':base+fallback})
                if flip:frame=ImageOps.mirror(frame)
                name=f'characters/npc{graphic}_{direction}_{state}_{index}.png';frame.save(out/name)
                frames.append({'path':'res://content/'+name,'region':[0,0,frame.width,frame.height],'offset':npc_frame_offset(metadata,direction,'idle' if fallback else state,0 if fallback else index),
                               'source_graphic_id':base+offset,**({'fallback_source_graphic_id':base+fallback} if fallback else {})})
            npc[state][direction]=frames[0] if state=='idle' and len(frames)==1 else frames
    return npc


def export_catalog(runtime:Path,graphics_zip:Path,out:Path,map_id=5):
    pub=runtime/'data/pub';maps_dir=runtime/'data/maps'
    manifest=json.loads((out/'manifest.json').read_text())
    files={'items':pub/'dat001.eif','npcs':pub/'dtn001.enf','classes':pub/'dat001.ecf'}
    items=parse_items(files['items'].read_bytes());npcs=parse_npcs(files['npcs'].read_bytes())
    maps={};worlds={}
    (out/'maps').mkdir(exist_ok=True)
    for path in sorted(maps_dir.glob('[0-9][0-9][0-9][0-9][0-9].emf')):
        world=parse_emf(path.read_bytes(),int(path.stem))
        world['relog']=list(world['spawn'])
        world['spawn_semantics']='Legacy relog coordinates only; online position comes from server snapshots.'
        world['server_blocked']=[[e['x'],e['y']] for e in world['tile_specs'] if e['spec'] in SERVER_BLOCKING_SPECS]
        worlds[world['id']]=world
        geometry_path=f'maps/{world["id"]:05}.json'
        (out/geometry_path).write_text(json.dumps(world,ensure_ascii=False,separators=(',',':'))+'\n')
        maps[str(world['id'])]={'path':'res://content/'+geometry_path,'id':world['id'],'name':world['name'],'width':world['width'],'height':world['height'],
            'relog':world['spawn'],'npc_spawns':world['npcs'],'warp_count':len(world['warps']),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'client_geometry_available':True}
    selected=maps[str(map_id)]
    catalog={'schema_version':1,'classes':parse_classes(files['classes'].read_bytes()),'items':items,'npcs':npcs,'maps':maps,'selected_map':map_id,
      'source':{'kind':'staged etheos runtime data','files':{key:{'path':str(path.relative_to(runtime)),
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for key,path in files.items()},
        'graphics_archive':graphics_zip.name,'graphics_sha256':hashlib.sha256(graphics_zip.read_bytes()).hexdigest(),
        'rights':'Original game data and art have unresolved publication rights. Local reference use does not grant redistribution rights.'},
      'warnings':['Catalog descriptions are not gameplay authority; the server supplies actual state.',
        'All282 map geometries and spawned NPC graphics are exported. Unsupported player appearances still require further composition.']}
    missing=[];containers={};cache=OrderedDict()
    with zipfile.ZipFile(graphics_zip) as archive:
        def image(gfx,gid):
            key=(gfx,gid)
            if key not in cache:
                if gfx not in containers:containers[gfx]=PEBitmaps(read_member(archive,f'gfx/gfx{gfx:03}.egf'))
                cache[key]=containers[gfx].image(gid)
                if len(cache)>96:cache.popitem(last=False)
            cache.move_to_end(key)
            return cache[key]
        map_references={}
        for world in worlds.values():
            for layer,entries in world['layers'].items():
                for entry in entries:
                    if entry['id']>0:map_references.setdefault((LAYER_GFX[layer],entry['id']),set()).add(world['id'])
            if world['fill_tile']>0:map_references.setdefault((3,world['fill_tile']),set()).add(world['id'])
        for (gfx,gid),map_ids in sorted(map_references.items()):
            graphic_key=f'{gfx}:{gid}'
            if graphic_key in manifest['graphics']:continue
            try:img=image(gfx,gid)
            except KeyError:
                missing.append({'map_graphic':graphic_key,'maps':sorted(map_ids)});continue
            name=f'gfx/{gfx:03}_{gid:05}.png';img.save(out/name)
            manifest['graphics'][graphic_key]={'path':'res://content/'+name,'width':img.width,'height':img.height}
        for item in items.values():
            if not item['graphic']:continue
            for key in ('icon','ground'):
                gid=int(item[key].split(':')[1]);graphic_key=f'23:{gid}'
                if graphic_key in manifest['graphics']:continue
                try:img=image(23,gid)
                except KeyError:
                    missing.append({'item':item['id'],'graphic':graphic_key});continue
                name=f'gfx/023_{gid:05}.png';img.save(out/name)
                manifest['graphics'][graphic_key]={'path':'res://content/'+name,'width':img.width,'height':img.height}
        for row in MONEY_GRAPHICS:
            graphic_key=row['ground'];gid=int(graphic_key.split(':')[1]);img=image(23,gid)
            name=f'gfx/023_{gid:05}.png';img.save(out/name)
            manifest['graphics'][graphic_key]={'path':'res://content/'+name,'width':img.width,'height':img.height}
        catalog['money_graphics']=MONEY_GRAPHICS
        manifest['characters']['weapon_variants']={}
        for item_id in WEAPON_APPEARANCE_ITEMS:
            item=items[str(item_id)];doll=item['doll_graphic']
            for armor_on in (0,1):
                for boots_on in (0,1):
                    key=f'a{armor_on}_b{boots_on}_g{doll}'
                    manifest['characters']['weapon_variants'][key]=export_hero(out,image,armor_on,boots_on,doll,key)
        npc_graphics={}
        for map_data in maps.values():
            for spawn in map_data['npc_spawns']:
                definition=npcs.get(str(spawn['id']))
                if definition and definition['graphic']>0:npc_graphics[definition['graphic']]=definition['name']
        manifest['characters']['npcs']={}
        for graphic,name in sorted(npc_graphics.items()):
            try:character=export_npc(graphic,name,image,out)
            except (KeyError,UnsupportedNPCArt) as error:
                missing.append({'npc_graphic':graphic,'missing_resource':str(error),'reason':'missing or blank original NPC art'});continue
            manifest['characters']['npcs'][str(graphic)]=character
    manifest['map_paths']={str(mid):record['path'] for mid,record in maps.items()}
    catalog['world_validation']=validate_world(worlds,map_id)
    provenance_file=graphics_zip.with_name(graphics_zip.name+'.metadata.json')
    if provenance_file.exists():catalog['source']['graphics_provenance']=json.loads(provenance_file.read_text())
    catalog['appearance_bindings']={'snapshot_equipment_order':['boots','reserved','reserved','reserved','armor','reserved','hat','shield','weapon'],
        'character_selection_equipment_order':['boots','armor','hat','shield','weapon'],
        'rendered_appearance':{'gender':1,'race':0,'hairstyle':1,'haircolor':0,'armor_doll_graphic':1,'boots_doll_graphic':1,'weapon_doll_graphic':4},
        'additional_weapon_items':list(WEAPON_APPEARANCE_ITEMS),
        'reference':'etheos Character::AddPaperdollData B000A0HSW / BAHSW'}
    catalog['available_npc_graphics']=sorted(int(g) for g in manifest['characters']['npcs'])
    catalog['missing_graphics']=missing
    catalog['npc_pose_fallbacks']={gid:char['pose_fallbacks'] for gid,char in manifest['characters']['npcs'].items() if char['pose_fallbacks']}
    manifest['runtime_catalog']='res://content/catalog.json'
    manifest['online_content']={'map':map_id,'map_count':len(maps),'npc_graphics':catalog['available_npc_graphics'],
                               'catalog_sha256':hashlib.sha256(json.dumps(catalog,sort_keys=True).encode()).hexdigest()}
    write_json(out/'catalog.json',catalog)
    manifest['online_content']['catalog_sha256']=hashlib.sha256((out/'catalog.json').read_bytes()).hexdigest()
    write_json(out/'manifest.json',manifest)
    return {'items':len(items),'npcs':len(npcs),'maps':len(maps),'selected_map':selected,
            'npc_graphics':catalog['available_npc_graphics'],'missing_graphics':missing,'world_validation':catalog['world_validation']}


def validate_world(worlds,start_map):
    graph={mid:set() for mid in worlds};invalid=[];warp_count=0
    for mid,world in worlds.items():
        for warp in world['warps']:
            warp_count+=1;target=worlds.get(warp['map'])
            if target is None:
                invalid.append({'source_map':mid,'warp':warp,'reason':'missing destination map'})
            elif not(0<=warp['destination'][0]<target['width'] and 0<=warp['destination'][1]<target['height']):
                invalid.append({'source_map':mid,'warp':warp,'reason':'destination outside map bounds'})
            else:graph[mid].add(warp['map'])
    reached={start_map};pending=[start_map]
    while pending:
        for target in graph.get(pending.pop(),set()):
            if target not in reached:reached.add(target);pending.append(target)
    return {'map_count':len(worlds),'warp_count':warp_count,
      'reachable_from_start_ignoring_level_and_doors':sorted(reached),
      'unreachable_from_start':sorted(set(worlds)-reached),'invalid_warps':invalid,
      'semantics':'Warps retain original destination, level requirement, and door value. Server controls transitions; relog is not a safe spawn guarantee.'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=Path,required=True);p.add_argument('--graphics-zip',type=Path,required=True)
    p.add_argument('--output',type=Path,default=Path(__file__).resolve().parent.parent/'client/content')
    p.add_argument('--map',type=int,default=5);a=p.parse_args()
    result=export_catalog(a.runtime,a.graphics_zip,a.output,a.map)
    print(json.dumps({k:v for k,v in result.items() if k!='selected_map'},indent=2))


if __name__=='__main__':main()
