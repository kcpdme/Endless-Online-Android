#!/usr/bin/env python3
"""Export independent original male equipment layers, avoiding outfit combinations.

Frame offsets and draw order match the existing EO compositor. Private original
art is read from the supplied archive and written only into ignored content.
"""
import argparse,json,zipfile
from pathlib import Path
from PIL import Image
from import_eo import PEBitmaps,read_member,write_json,export_hero

def export_layers(out,image,items):
    layers={};missing=[]
    def layer(name,graphic,armor=0,boots=0,weapon=0):
        key=f'{name}:{graphic}'
        try:hero=export_hero(out,image,armor,boots,weapon,'layer_'+name+str(graphic),component=name)
        except KeyError as error:
            missing.append({'layer':key,'resource':str(error)});return
        atlas=Image.new('RGBA',(192*8,192*4));index=0;visible=False
        for state in ('idle','frames','attack','cast'):
            for direction in ('south','east','north','west'):
                raw=hero[state][direction];frames=[raw] if isinstance(raw,dict) else raw
                for frame in frames:
                    path=out/frame['path'].removeprefix('res://content/')
                    with Image.open(path) as im:
                        visible=visible or bool(im.getbbox());x=index%8*192;y=index//8*192
                        atlas.alpha_composite(im,(x,y))
                    path.unlink();frame['region']=[x,y,192,192];frame['path']=f'res://content/characters/layer_{name}_{graphic}.png';index+=1
        assert index==32
        if visible or name=='weapon_front':
            atlas.save(out/f'characters/layer_{name}_{graphic}.png');layers[key]=hero
        else:missing.append({'layer':key,'reason':'blank original art'})
    layer('skin',0);layer('hair',0)
    for name,kind in [('armor',12),('boots',14),('weapon_back',10),('weapon_front',10)]:
        ids=sorted({i['doll_graphic'] for i in items.values() if i['type']==kind and i['doll_graphic']>0 and (kind!=12 or i['gender']==1)})
        for graphic in ids:layer(name,graphic,**{'armor' if kind==12 else 'boots' if kind==14 else 'weapon':graphic})
    return {'layers':layers,'missing':missing,'supported_body':{'gender':1,'race':0,'hairstyle':1,'haircolor':0},'order':['weapon_back','skin','boots','armor','hair','weapon_front']}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--graphics-zip',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args()
    m=json.loads((a.output/'manifest.json').read_text());items=json.loads((a.output/'catalog.json').read_text())['items'];containers={};cache={}
    with zipfile.ZipFile(a.graphics_zip) as archive:
        def image(gfx,gid):
            if gfx not in containers:containers[gfx]=PEBitmaps(read_member(archive,f'gfx/gfx{gfx:03}.egf'))
            if (gfx,gid) not in cache:cache[gfx,gid]=containers[gfx].image(gid)
            return cache[gfx,gid]
        result=export_layers(a.output,image,items)
    m['characters']['equipment_layers']=result;write_json(a.output/'manifest.json',m)
    print(json.dumps({'layers':len(result['layers']),'missing':result['missing']},indent=2))
if __name__=='__main__':main()
