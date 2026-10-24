#!/usr/bin/env python3
"""Validate and publish the two composed, animated starter-outfit appearances."""
import argparse
import copy
import hashlib
import os
import shutil
from pathlib import Path
from PIL import Image
from character_art_pack import ROOT, read, write, verify, confined, local_resource, frames

STATES={'idle':1,'frames':4,'attack':2,'cast':1,'ranged_attack':2,'sit_chair':1,'sit_floor':1}
DIRECTIONS=('south','east','north','west')

def publish(root, release):
    if not release.isalnum() or len(release)>40:raise ValueError('Use a short alphanumeric release name')
    verify(root,'painted_v1')
    pack=root/'client/art_packs/painted_v1'; draft=pack/'draft/pilot'
    entries=read(draft/'appearances.json'); assets={}; report={}
    if set(entries)!={'peasant_male','peasant_female'}:raise ValueError('Expected both complete pilot appearances')
    for name,entry in entries.items():
        gender=1 if name=='peasant_male' else 0
        expected={'gender':gender,'race':0,'hairstyle':1,'haircolor':0,'boots':4,'armor':16 if gender else 14,'hat':0,'shield':0,'weapon':0}
        if entry.get('match')!=expected:raise ValueError('Pilot match must preserve the native outfit IDs')
        character=entry['character']; checks=0
        for state,count in STATES.items():
            if set(character[state])!=set(DIRECTIONS):raise ValueError('Missing direction')
            for direction in DIRECTIONS:
                rows=character[state][direction]; rows=rows if isinstance(rows,list) else [rows]
                if len(rows)!=count:raise ValueError('Missing animation phase')
                hashes=set()
                for frame in rows:
                    path=confined(draft,local_resource(root,frame['path']))
                    if path not in assets:
                        with Image.open(path) as source:assets[path]=source.convert('RGBA')
                    image=assets[path];x,y,w,h=frame['region']
                    if (frame.get('pixel_scale'),frame.get('logical_canvas'),frame.get('trim_offset'),frame.get('offset'))!=(4,[192,192],[72,112],[0,8]):raise ValueError('Invalid world size or foot anchor')
                    if min(x,y)<0 or x+w>image.width or y+h>image.height or (w,h)!=(192,320):raise ValueError('Frame outside atlas')
                    part=image.crop((x,y,x+w,y+h)); box=part.getbbox()
                    if not box or min(box[:2])<=1 or box[2]>=w-1 or box[3]>=h-1:raise ValueError('Empty/clipped pose')
                    hashes.add(hashlib.sha256(part.tobytes()).hexdigest());checks+=1
                if len(hashes)!=count:raise ValueError('Repeated static artwork in an animated pose')
        report[name]={'frames':checks,'png_bytes':sum(p.stat().st_size for p in {local_resource(root,f['path']) for f in frames(character)})}
    dest=pack/'releases'/release
    if dest.exists():raise ValueError('Release already exists; use a new name')
    dest.mkdir(parents=True)
    entries=copy.deepcopy(entries);copied={}
    for entry in entries.values():
        for frame in frames(entry['character']):
            source=local_resource(root,frame['path'])
            if source not in copied:
                target=dest/source.name;shutil.copy2(source,target);copied[source]='res://'+str(target.relative_to(root/'client'))
            frame['path']=copied[source]
    data={'schema':1,'id':'painted_v1','status':'ready','release':release,'layers':{},'appearances':entries,'coverage':'Default skin and hair; male/female peasant outfit with Brown Boots; unarmed, no hat/shield.','animation_method':'cutout_mesh_v1'}
    write(dest/'pack.json',data);write(pack/'pack.pending.json',data);os.replace(pack/'pack.pending.json',pack/'pack.json')
    return {'result':'passed','release':release,'appearances':report,'atlas_count':len(copied),'gpu_atlas_bytes_rgba':sum(im.width*im.height*4 for im in assets.values()),'classic_assets_unchanged':True}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--release',required=True);args=parser.parse_args()
    import json
    print(json.dumps(publish(ROOT,args.release),indent=2))
