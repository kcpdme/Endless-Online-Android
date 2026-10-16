#!/usr/bin/env python3
"""Import one EO EMF map and only referenced PE bitmap resources.

Reference: ethanmoffat/EndlessClient EOLib.IO serializers and rendering classes.
Original game content is development reference material; redistribution rights
are unresolved. No executable from the input archives is executed or extracted.
Dependencies: Python 3.10+, Pillow. ZIP members are read in memory with limits.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import struct
import zipfile
import wave
from PIL import Image, ImageOps

LAYERS = ['ground','objects','overlay','walls_down','walls_right','roof','wall_top','shadow','overlay2']
LAYER_GFX = dict(zip(LAYERS,[3,4,5,6,6,7,3,22,5]))
BLOCKING_SPECS = {0,1,2,3,4,5,6,7,9,16,18,20,21,22,23,24,25,26,27,28,30,173}


def decode_number(data: bytes) -> int:
    """EO's little-endian base-253 integers (1 => 0; 254 pads)."""
    if not 1 <= len(data) <= 4:
        raise ValueError('EO number width must be 1..4')
    value = 0
    for n, byte in enumerate(data):
        if byte in (0,255):
            raise ValueError(f'invalid EO integer byte {byte}')
        if byte == 254:
            break
        value += (byte-1)*253**n
    return value


def decode_string(data: bytes) -> str:
    out=[]
    flip = len(data)%2 == 1
    for c in reversed(data):
        if c == 255:
            break
        if flip:
            if 0x22 <= c <= 0x4f: c=0x71-c
            elif 0x50 <= c <= 0x7e: c=0xcd-c
        elif 0x22 <= c <= 0x7e: c=0x9f-c
        out.append(c)
        flip=not flip
    return bytes(out).decode('ascii',errors='replace')


class Reader:
    def __init__(self,data:bytes): self.data=data; self.pos=0
    def take(self,n:int)->bytes:
        if n<0 or self.pos+n>len(self.data):
            raise ValueError(f'truncated data at byte {self.pos}; need {n}')
        result=self.data[self.pos:self.pos+n]; self.pos+=n
        return result
    def num(self,n=1)->int: return decode_number(self.take(n))


def read_member(archive:zipfile.ZipFile,name:str,limit=64*1024*1024)->bytes:
    path=PurePosixPath(name.replace('\\','/'))
    if path.is_absolute() or '..' in path.parts: raise ValueError('unsafe ZIP member path')
    info=archive.getinfo(name)
    if info.file_size>limit: raise ValueError('oversize ZIP member')
    return archive.read(info)


def parse_emf(data:bytes,map_id:int)->dict:
    r=Reader(data)
    if r.take(3)!=b'EMF': raise ValueError('not an EMF map')
    r.take(4)
    name=decode_string(r.take(24)); r.take(6)
    width=r.num()+1; height=r.num()+1; fill=r.num(2)
    available=r.num(); scroll=r.num(); relog=[r.num(),r.num()]; r.num()
    world=dict(id=map_id,name=name,width=width,height=height,tile_width=64,tile_height=32,
               fill_tile=fill,spawn=relog,layers={},blocked=[],warps=[],npcs=[],tile_specs=[])
    for _ in range(r.num()):
        world['npcs'].append(dict(x=r.num(),y=r.num(),id=r.num(2),spawn_type=r.num(),respawn=r.num(2),amount=r.num()))
    r.take(r.num()*4) # unused legacy entity records
    chests=[]
    for _ in range(r.num()):
        chests.append(dict(x=r.num(),y=r.num(),key=r.num(2),slot=r.num(),item_id=r.num(2),respawn=r.num(2),amount=r.num(3)))
    world['chests']=chests
    def bounds(x,y):
        if not(0<=x<width and 0<=y<height): raise ValueError(f'out of bounds tile {x},{y}')
    for _ in range(r.num()):
        y=r.num(); columns=r.num()
        for _ in range(columns):
            x=r.num(); spec=r.num(); bounds(x,y)
            world['tile_specs'].append(dict(x=x,y=y,spec=spec))
            if spec in BLOCKING_SPECS: world['blocked'].append([x,y])
    for _ in range(r.num()):
        y=r.num(); columns=r.num()
        for _ in range(columns):
            x=r.num(); bounds(x,y)
            world['warps'].append(dict(x=x,y=y,map=r.num(2),destination=[r.num(),r.num()],level=r.num(),door=r.num(2)))
    for layer in LAYERS:
        world['layers'][layer]=[]
        if r.pos==len(data): continue
        for _ in range(r.num()):
            y=r.num(); columns=r.num()
            for _ in range(columns):
                x=r.num(); graphic=r.num(2); bounds(x,y)
                world['layers'][layer].append(dict(x=x,y=y,id=graphic))
    signs=[]
    if r.pos<len(data):
        for _ in range(r.num()):
            x=r.num(); y=r.num(); length=r.num(2)
            # Sign length includes title-length byte after encoded text.
            text=r.take(length-1); title_length=r.num()
            signs.append(dict(x=x,y=y,text=decode_string(text),title_length=title_length))
    world['signs']=signs
    if r.pos!=len(data): raise ValueError(f'{len(data)-r.pos} unconsumed map bytes')
    return world


class PEBitmaps:
    """Minimal read-only PE resource walker. Extracts RT_BITMAP DIBs only."""
    def __init__(self,data:bytes):
        self.data=data
        if data[:2]!=b'MZ': raise ValueError('not a PE resource container')
        pe=struct.unpack_from('<I',data,0x3c)[0]
        if data[pe:pe+4]!=b'PE\0\0': raise ValueError('invalid PE signature')
        count=struct.unpack_from('<H',data,pe+6)[0]
        optional_size=struct.unpack_from('<H',data,pe+20)[0]
        optional=pe+24; magic=struct.unpack_from('<H',data,optional)[0]
        dirs=optional+(96 if magic==0x10b else 112)
        resource_rva,resource_size=struct.unpack_from('<II',data,dirs+16)
        self.sections=[]
        for i in range(count):
            section=optional+optional_size+i*40
            virtual_size,rva,raw_size,raw_offset=struct.unpack_from('<IIII',data,section+8)
            self.sections.append((rva,max(virtual_size,raw_size),raw_offset,raw_size))
        self.base=self.offset(resource_rva)
        self.resources={}
        def entries(relative):
            offset=self.base+relative
            named,ids=struct.unpack_from('<HH',data,offset+12)
            if named+ids>65536: raise ValueError('oversize PE resource directory')
            return [struct.unpack_from('<II',data,offset+16+8*i) for i in range(named+ids)]
        for kind,kind_dir in entries(0):
            if kind!=2 or not(kind_dir&0x80000000): continue
            for rid,language_dir in entries(kind_dir&0x7fffffff):
                if rid&0x80000000: continue
                for _,leaf in entries(language_dir&0x7fffffff):
                    if leaf&0x80000000: raise ValueError('unexpected PE resource tree depth')
                    rva,size=struct.unpack_from('<II',data,self.base+leaf)
                    if size>16*1024*1024: raise ValueError('oversize bitmap')
                    offset=self.offset(rva)
                    if offset+size>len(data): raise ValueError('truncated bitmap')
                    self.resources.setdefault(rid,data[offset:offset+size])
    def offset(self,rva):
        for start,size,offset,raw_size in self.sections:
            if start<=rva<start+size:
                if rva-start>=raw_size: raise ValueError('resource points outside raw section')
                return offset+rva-start
        raise ValueError('RVA not mapped to a PE section')
    def image(self,graphic_id:int,transparent=True)->Image.Image:
        # EO IDs use resource number +100 in EGF PE containers.
        dib=self.resources[graphic_id+100]
        image=Image.open(io.BytesIO(dib)).convert('RGBA')
        # Original EO color key: exactly black, including unused sheet space.
        if not transparent:return image
        pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
        image.putdata([(r,g,b,0 if (r,g,b)==(0,0,0) else 255) for r,g,b,_ in pixels])
        return image


def safe_spawn(world:dict,preferred=(40,40))->list[int]:
    blocked={tuple(v) for v in world['blocked']}
    ground={(v['x'],v['y']):v['id'] for v in world['layers']['ground']}
    avoid={(v['x'],v['y']) for v in world['warps']}
    unavailable=blocked|avoid
    def safe(x,y):
        return 0<=x<world['width'] and 0<=y<world['height'] and (x,y) not in unavailable and ground.get((x,y),world['fill_tile'])>0
    candidates=[]
    for y in range(3,world['height']-3):
        for x in range(3,world['width']-3):
            score=sum(safe(x+dx,y+dy) for dx in range(-3,4) for dy in range(-3,4))
            if safe(x,y): candidates.append((-score,(x-preferred[0])**2+(y-preferred[1])**2,x,y))
    if not candidates: raise ValueError('map has no usable spawn')
    _,_,x,y=min(candidates)
    return [x,y]


def write_json(path:Path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sample-data',type=Path,required=True)
    parser.add_argument('--client-zip',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parent.parent/'client/content')
    parser.add_argument('--map',type=int,default=5)
    args=parser.parse_args()
    out=args.output; (out/'gfx').mkdir(parents=True,exist_ok=True); (out/'characters').mkdir(exist_ok=True)
    with zipfile.ZipFile(args.sample_data) as sample,zipfile.ZipFile(args.client_zip) as client:
        map_member=f'sample-data/maps/{args.map:05}.emf'
        world=parse_emf(read_member(sample,map_member),args.map)
        world['spawn']=safe_spawn(world)
        manifest={'schema_version':1,'graphics':{},'characters':{},'layer_gfx':LAYER_GFX,
          'source':{'map_archive':args.sample_data.name,'map_member':map_member,
                    'map_archive_sha256':hashlib.sha256(args.sample_data.read_bytes()).hexdigest(),
                    'graphics_archive':args.client_zip.name,
                    'graphics_archive_sha256':hashlib.sha256(args.client_zip.read_bytes()).hexdigest(),
                    'map_source_url':'https://etheosstorage.blob.core.windows.net/data/sample-data.zip',
                    'graphics_source_url':'https://cache.tehsausage.com/EndlessOnline/EOzipped028.zip',
                    'reference_code':'https://github.com/ethanmoffat/EndlessClient',
                    'rights':'Original game assets are development reference content. Publication and redistribution rights remain unresolved.'},
          'warnings':['Only map geometry, graphics, and reference spawn records are imported; NPC logic, quests, and warp transitions are not implemented.','PUB definitions in server sample-data and v28 client may differ; do not assume identical item or NPC identifiers.']}
        containers={}; cache={}
        def image(gfx,gid):
            key=(gfx,gid)
            if key in cache:return cache[key]
            if gfx not in containers:containers[gfx]=PEBitmaps(read_member(client,f'gfx/gfx{gfx:03}.egf'))
            cache[key]=containers[gfx].image(gid)
            return cache[key]
        def export(gfx,gid):
            key=f'{gfx}:{gid}'
            if key in manifest['graphics']:return
            img=image(gfx,gid); name=f'gfx/{gfx:03}_{gid:05}.png'; img.save(out/name)
            manifest['graphics'][key]=dict(path='res://content/'+name,width=img.width,height=img.height)
        for layer,entries in world['layers'].items():
            for entry in entries:
                if entry['id']>0:export(LAYER_GFX[layer],entry['id'])
        if world['fill_tile']>0:export(3,world['fill_tile'])
        manifest['sounds']=export_sounds(out,client)
        variants={}
        for armor_on in (0,1):
            for boots_on in (0,1):
                for weapon_on in (0,1):
                    key=f'a{armor_on}_b{boots_on}_w{weapon_on}'
                    variants[key]=export_hero(out,image,armor_on,boots_on,4 if weapon_on else 0,key)
        manifest['characters']['hero_variants']=variants
        manifest['characters']['hero']=variants['a1_b1_w0']
        manifest['characters']['hero_equipped']=variants['a1_b1_w1']
        # Preserve classic paperdoll artwork without applying sprite color keys.
        paper=PEBitmaps(read_member(client,'gfx/gfx002.egf')).image(49,transparent=False)
        (out/'ui').mkdir(exist_ok=True)
        paper.crop((0,290,380,580)).save(out/'ui/paperdoll_male.png')
        paper.crop((14,302,214,568)).save(out/'ui/paperdoll_silhouette.png')
        manifest['paperdoll']={
            'background':'res://content/ui/paperdoll_male.png',
            'silhouette_panel':'res://content/ui/paperdoll_silhouette.png',
            'background_size':[380,290],
            'source_graphic':'2:49','source_member':'gfx/gfx002.egf',
            'background_source_region':[0,290,380,290],
            'silhouette_source_region':[14,302,200,266],
            'slots':{'hat':[87,21,56,54],'weapon':[22,82,56,98],
                     'armor':[86,82,56,98],'shield':[152,82,56,98],
                     'boots':[87,220,56,54],'gloves':[22,188,56,54],
                     'belt':[87,188,56,23],'necklace':[152,51,56,23],
                     'accessory':[55,250,23,23],'ring1':[152,190,23,23],
                     'ring2':[185,190,23,23],'armlet1':[152,220,23,23],
                     'armlet2':[185,220,23,23],'bracer1':[152,250,23,23],
                     'bracer2':[185,250,23,23]}}
        items=parse_eif(read_member(client,'pub/dat001.eif'))
        manifest['starter_equipment']={}
        for slot,item_id in [('weapon',21),('armor',143),('boots',80)]:
            item=items[item_id]
            icon_id=item['graphic']*2
            export(23,icon_id);export(23,icon_id-1)
            manifest['starter_equipment'][slot]={**item,'icon':f'23:{icon_id}','ground':f'23:{icon_id-1}'}
        manifest['reference_layer_offsets']={
          'coordinate_basis':'relative to tile center iso(x,y)+(0,16)',
          'objects':['-width/2-2','14-height'],
          'overlay':['-width/2-2','14-height'],
          'walls_down':[-32,'15-height'],
          'walls_right':[0,'15-height'],
          'roof':[-32,-80],'wall_top':[-32,-48],
          'shadow':[-56,-28],'overlay2':['-width/2-2','14-height']}

        # NPC graphic3 is the classic green slime. Each frame is a separate
        # resource, not a packed sheet (NPCSpriteSheet.cs, stride40).
        manifest['characters']['monster']={'name':'Classic green slime training creature','idle':{},'frames':{},'attack':{},'graphic':3}
        for direction,back,flip in [('south',0,False),('east',0,True),('north',1,True),('west',1,False)]:
            for state,ids in [('idle',[81+back*2]),('frames',[85+back*4+i for i in range(4)]),('attack',[93+back*2+i for i in range(2)])]:
                frames=[]
                for index,gid in enumerate(ids):
                    frame=image(21,gid)
                    if flip:frame=ImageOps.mirror(frame)
                    name=f'characters/blob_{direction}_{state}_{index}.png'; frame.save(out/name)
                    frames.append(dict(path='res://content/'+name,region=[0,0,frame.width,frame.height],offset=[0,0]))
                manifest['characters']['monster'][state][direction]=frames[0] if state=='idle' else frames
        for gid in [1,2,3,75,76]:export(23,gid)
        manifest['sample_item_graphic']='23:75'
        manifest['sample_item_icon']='23:76'
        write_json(out/'world.json',world);write_json(out/'manifest.json',manifest)
        print(json.dumps(dict(map=world['name'],dimensions=[world['width'],world['height']],spawn=world['spawn'],graphics=len(manifest['graphics']),blocked=len(world['blocked']),npcs=len(world['npcs']),layers={k:len(v) for k,v in world['layers'].items()}),indent=2))


def parse_eif(data:bytes)->dict:
    """Read classic58-byte item records, retaining appearance and item icon IDs."""
    r=Reader(data)
    if r.take(3)!=b'EIF':raise ValueError('not an EIF item file')
    r.take(4);count=r.num(2);r.num();items={}
    for item_id in range(1,count+1):
        name=r.take(r.num()).decode('ascii',errors='replace')
        fields=r.take(58)
        if name=='eof':break
        items[item_id]={'id':item_id,'name':name,'graphic':decode_number(fields[:2]),
            'type':decode_number(fields[2:3]),'doll_graphic':decode_number(fields[32:35]),
            'gender':decode_number(fields[35:36]),'source_member':'pub/dat001.eif'}
    return items


def canonical_wav(data:bytes)->tuple[bytes,dict]:
    """Decode declared PCM data and write exact RIFF/data lengths.

    The v28 melee WAV contains bytes after its declared data chunk and an
    incorrect RIFF length. Keep declared audio frames; discard trailing bytes.
    This avoids treating unrelated trailing bytes as audible PCM.
    """
    with wave.open(io.BytesIO(data),'rb') as source:
        params=source.getparams()
        if params.comptype!='NONE' or params.nchannels not in (1,2) or params.sampwidth not in (1,2):
            raise ValueError('unsupported reference audio format')
        frames=source.readframes(params.nframes)
        if len(frames)!=params.nframes*params.nchannels*params.sampwidth:
            raise ValueError('truncated PCM audio')
    buffer=io.BytesIO()
    with wave.open(buffer,'wb') as output:
        output.setparams(params);output.writeframes(frames)
    result=buffer.getvalue()
    return result,dict(duration_seconds=round(params.nframes/params.framerate,4),
      sample_rate=params.framerate,channels=params.nchannels,bits_per_sample=params.sampwidth*8,
      header_repaired=struct.unpack_from('<I',data,4)[0]!=len(data)-8,
      source_bytes=len(data),output_bytes=len(result))


def export_sounds(out,client):
    (out/'audio').mkdir(exist_ok=True)
    sounds={}
    for name,member in [('attack','sfx/sfx016.wav'),('pickup','sfx/sfx021.wav'),('punch','sfx/sfx011.wav')]:
        raw=read_member(client,member);canonical,metadata=canonical_wav(raw)
        (out/'audio'/f'{name}.wav').write_bytes(canonical)
        sounds[name]=dict(path=f'res://content/audio/{name}.wav',source_member=member,
            source_sha256=hashlib.sha256(raw).hexdigest(),**metadata)
    return sounds


def export_hero(out,image,armor_on=1,boots_on=1,weapon_graphic=0,variant="a1_b1_w0"):
    """Male race0, hair1/color0, selectable armor/boots/dagger; exact EO offsets.

    18x58 parent draw rectangle from CharacterRenderer. Skin source calculations
    and offsets follow CharacterSpriteCalculator, SkinRenderLocationCalculator,
    HairRenderLocationCalculator, ArmorRenderer, BootsRenderer. Compose layers
    to fixed 96x96 transparent canvases; feet anchor stays (48,88).
    """
    hero={'name':'Classic adventurer','anchor':[48,88],'frame_width':96,'frame_height':96,'frames':{},'idle':{},'attack':{},
          'appearance':{'gender':1,'race':0,'hair_style':1,'hair_color':0,'armor_graphic':armor_on,'boots_graphic':boots_on,'weapon_graphic':weapon_graphic},
          'composition':'Layered source bitmaps precomposed for prototype; replace with runtime equipment layering later.'}
    hero['source_resources']={'gfx/gfx008.egf':[1,2,3],'gfx/gfx009.egf':[2,4]}
    if armor_on:hero['source_resources']['gfx/gfx013.egf']=list(range(1,11))+list(range(13,17))
    if boots_on:hero['source_resources']['gfx/gfx011.egf']=list(range(1,13))
    if weapon_graphic:
        base=(weapon_graphic-1)*100
        hero['source_resources']['gfx/gfx017.egf']=[base+i for i in list(range(1,11))+list(range(13,18))]
    for direction,back,flip in [('south',0,False),('east',0,True),('north',1,True),('west',1,False)]:
        for state,count in [('idle',1),('frames',4),('attack',2)]:
            frames=[]
            for index in range(count):
                walking=state=='frames'; attacking=state=='attack'; frame=index+1
                sheet=image(8,2 if walking else 3 if attacking else 1)
                columns=16 if walking else 8 if attacking else 4
                sw=sheet.width//columns; sh=sheet.height//7
                sx=sheet.width//2+back*(sheet.width//4)+(index*sw if walking or attacking else 0)+(1 if walking and not back else 0)
                skin=sheet.crop((sx,0,sx+sw,sh))
                hair=image(9,2+back*2)
                armor_id=3+index+back*4 if walking else 13+index+back*2 if attacking else 1+back
                boots_id=3+index+back*4 if walking else 11+back if attacking and frame==2 else 1+back
                armor=image(13,armor_id);boots=image(11,boots_id)
                canvas=Image.new('RGBA',(96,96))
                parent_x=39;parent_y=30 # 18x58 draw area bottom at anchor y88
                def paste(img,x,y):
                    if flip:img=ImageOps.mirror(img)
                    canvas.alpha_composite(img,(parent_x+int(x),parent_y+int(y)))
                def draw_weapon(gid):
                    blade=image(17,(weapon_graphic-1)*100+gid)
                    factor=1 if flip else -1
                    bx=-math.floor(abs(blade.width-18)/2)+9*factor
                    if attacking and frame==2:bx+=2*factor
                    by=-math.floor(abs(blade.height-58)/2)-7-(1 if walking else 0)
                    paste(blade,bx,by)
                # The primary weapon sits behind skin except the front half of
                # a down/right second swing; that pose uses a split resource.
                split=weapon_graphic and attacking and frame==2 and not back
                weapon_id=3+index+back*4 if walking else 13+index+back*2 if attacking else 1+back
                if weapon_graphic:draw_weapon(14 if split else weapon_id)
                skin_x=-math.floor(abs(sw-18)/2)
                if attacking and frame==1:skin_x+=2 if flip else -2
                paste(skin,skin_x,-math.floor(abs(sh-58)/2))
                boots_x=-math.floor(abs(boots.width-18)/2);boots_y=math.floor(58/3)*2-2
                if walking:boots_y-=1+(1 if frame==2 else 0)
                elif attacking and frame==2:
                    factor=1 if flip else -1;boots_x+=2*factor;boots_y+=factor-(2 if flip else 0)
                if boots_on:paste(boots,boots_x,boots_y)
                armor_x=-math.floor(abs(armor.width-18)/2)-2
                if attacking and frame==2:armor_x+=4 if flip else 0
                else:armor_x+=2
                armor_y=-math.floor(abs(armor.height-58)/2)-(5 if walking else 4)
                if armor_on:paste(armor,armor_x,armor_y)
                hair_x=-math.floor(abs(hair.width-18)/2)-1+(2 if flip else 0)
                hair_y=-math.floor(abs(hair.height-29)/2)-1
                if attacking and frame==2:
                    hair_x+=4 if flip else -4
                    if back:hair_x+=-2 if flip else 2
                    hair_y+=1 if back else 4
                paste(hair,hair_x,hair_y)
                if split:draw_weapon(17)
                name=f'characters/hero_{variant}_{direction}_{state}_{index}.png';canvas.save(out/name)
                # Canvas extends eight pixels below feet; tell renderer via offset.
                frames.append(dict(path='res://content/'+name,region=[0,0,96,96],offset=[0,8]))
            hero[state][direction]=frames[0] if state=='idle' else frames
    return hero


if __name__=='__main__':main()
