#!/usr/bin/env python3
"""Export original equipment for both genders and all native skin/hair choices.

Offsets, hat mask modes and directional offhand depth follow EndlessClient's
CharacterSpriteCalculator, CharacterPropertyRendererBuilder and renderers.
Private art is written only into ignored client/content.
"""
import argparse,json,zipfile,math
from pathlib import Path
from PIL import Image,ImageOps
from import_eo import PEBitmaps,read_member,write_json,export_hero

HIDE_HAIR={16,17,18,19,20,21,25,26,28,30,31,34,35,36,37,38,40,41,44,46,47}
FACE_MASK={7,8,9,10,11,12,13,14,15,32,33,48,50}
BACK_SHIELDS={10,11,14,15,16,18,19}
STATES=(('idle',1),('frames',4),('attack',2),('cast',1))
DIRECTIONS=(('south',0,False),('east',0,True),('north',1,True),('west',1,False))

def hat_bitmap(raw,graphic):
    pixels=list(raw.get_flattened_data() if hasattr(raw,'get_flattened_data') else raw.getdata())
    clip=graphic not in HIDE_HAIR|FACE_MASK and any(p[:3]==(8,0,0) for p in pixels)
    result=raw.copy()
    result.putdata([(r,g,b,0 if (r,g,b)==(8,0,0) or ((r,g,b)==(0,0,0) and not clip) else 255) for r,g,b,a in pixels])
    return result

def export_layers(out,image,items,raw_image=None):
    layers={};missing=[]
    def store(key,hero,images):
        atlas=Image.new('RGBA',(192*8,192*4));visible=False
        path=f'characters/layer_{key.replace(":","_")}.png'
        for index,(frame,im) in enumerate(images):
            visible=visible or bool(im.getbbox());x=index%8*192;y=index//8*192
            atlas.alpha_composite(im,(x,y));frame.update(region=[x,y,192,192],path='res://content/'+path)
        assert len(images)==32
        if visible or key.startswith('weapon_front:'):
            atlas.save(out/path);layers[key]=hero
        else:missing.append({'layer':key,'reason':'blank original art'})
    def layer(name,graphic,gender=1,race=0,hairstyle=1,haircolor=0):
        # Keep v18 male/default keys for old fixtures and starter verification.
        key=f'{name}:{graphic}' if gender==1 else f'{name}:f:{graphic}'
        if name=='skin' and race:key+=f':{race}'
        if name=='hair' and (hairstyle,haircolor)!=(1,0):key+=f':{hairstyle}:{haircolor}'
        try:
            hero=export_hero(out,image,graphic if name=='armor' else 0,graphic if name=='boots' else 0,graphic if name.startswith('weapon') else 0,'layer_'+key.replace(':','_'),component=name,gender=gender,race=race,hairstyle=hairstyle,haircolor=haircolor)
        except KeyError as error:
            missing.append({'layer':key,'resource':str(error)});return
        images=[]
        for state,_ in STATES:
            for direction,_,_ in DIRECTIONS:
                raw=hero[state][direction]
                for frame in [raw] if isinstance(raw,dict) else raw:
                    path=out/frame['path'].removeprefix('res://content/')
                    with Image.open(path) as im:images.append((frame,im.copy()))
                    path.unlink()
        store(key,hero,images)
    def accessory(name,graphic,gender):
        key=f'{name}:{graphic}' if gender==1 else f'{name}:f:{graphic}'
        hero={state:{} for state,_ in STATES};images=[]
        hero['graphic']=graphic;hero['component']=name
        hero['mask_mode']='hide' if graphic in HIDE_HAIR else 'face' if graphic in FACE_MASK else 'standard'
        hero['on_back']=graphic in BACK_SHIELDS
        try:
            for state,count in STATES:
                for direction,back,flip in DIRECTIONS:
                    frames=[]
                    for index in range(count):
                        walking=state=='frames';second=state=='attack' and index==1
                        canvas=Image.new('RGBA',(192,192));px=87;py=126
                        if name=='head':
                            gid=(graphic-1)*10+1+back*2
                            raw=(raw_image or image)(16-gender,gid)
                            art=hat_bitmap(raw,graphic) if raw_image else raw
                            # All original hair sheets are 28x54; hats share their anchor.
                            x=-6+(2 if flip else 0);y=-12-gender
                            if second:
                                x+=4 if flip else -4
                                if back:x+=(-2 if flip else 2)*gender
                                y+=1 if back else 5-gender
                            x+=-2 if flip else 0;y-=3
                        else:
                            on_back=graphic in BACK_SHIELDS
                            gid=(3 if state=='attack' else 1)+back if on_back else (3+index+back*4 if walking else 13+index+back*2 if state=='attack' else 11+back if state=='cast' else 1+back)
                            art=image(20-gender,(graphic-1)*50+gid)
                            if on_back:
                                x=-math.floor(abs(art.width-18)/2);y=-math.floor(58/3)-gender
                                if second:x+=2 if flip else -2
                            else:
                                x=math.floor(abs(art.width-18)/2);y=math.floor(abs(art.height-58)/2)+5-gender-int(walking)
                                x+=(-27-2*int(second)+2) if not flip else (-12+2*int(second)-3)
                        if flip:art=ImageOps.mirror(art)
                        canvas.alpha_composite(art,(px+int(x),py+int(y)))
                        frame={'offset':[0,8]};frames.append(frame);images.append((frame,canvas))
                    hero[state][direction]=frames[0] if state=='idle' else frames
        except KeyError as error:
            missing.append({'layer':key,'resource':str(error)});return
        store(key,hero,images)
    for gender in (1,0):
        for race in range(7):layer('skin',0,gender=gender,race=race)
        for hairstyle in range(1,21):
            for color in range(10):layer('hair',0,gender=gender,hairstyle=hairstyle,haircolor=color)
        for name,kind in [('armor',12),('boots',14),('weapon_back',10),('weapon_front',10),('head',13),('offhand',11)]:
            ids=sorted({i['doll_graphic'] for i in items.values() if i['type']==kind and i['doll_graphic']>0 and (kind!=12 or i['gender']==gender)})
            for graphic in ids:
                if name in ('head','offhand'):accessory(name,graphic,gender)
                else:layer(name,graphic,gender=gender)
    return {'version':2,'layers':layers,'missing':missing,'supported_body':{'genders':[0,1],'races':list(range(7)),'hairstyles':list(range(21)),'haircolors':list(range(10))},'order':['offhand_back','weapon_back','skin','boots','armor','head_and_hair','weapon_front','offhand_front']}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--graphics-zip',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args()
    m=json.loads((a.output/'manifest.json').read_text());items=json.loads((a.output/'catalog.json').read_text())['items'];containers={};cache={}
    with zipfile.ZipFile(a.graphics_zip) as archive:
        def image(gfx,gid,raw=False):
            if gfx not in containers:containers[gfx]=PEBitmaps(read_member(archive,f'gfx/gfx{gfx:03}.egf'))
            if (gfx,gid,raw) not in cache:cache[gfx,gid,raw]=containers[gfx].image(gid,transparent=not raw)
            return cache[gfx,gid,raw]
        result=export_layers(a.output,image,items,lambda gfx,gid:image(gfx,gid,True))
    m['characters']['equipment_layers']=result;write_json(a.output/'manifest.json',m)
    print(json.dumps({'layers':len(result['layers']),'missing':result['missing']},indent=2))
if __name__=='__main__':main()
