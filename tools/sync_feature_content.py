"""Sync reviewed native PUB/map changes while preserving existing exported art."""
import argparse,hashlib,json,sys
from pathlib import Path
from export_catalog import parse_items,parse_npcs
from import_eo import parse_emf

def sync(runtime,out):
    runtime=Path(runtime);out=Path(out);path=out/'catalog.json';catalog=json.loads(path.read_text());manifest=json.loads((out/'manifest.json').read_text())
    for key,name,parse in [('items','dat001.eif',parse_items),('npcs','dtn001.enf',parse_npcs)]:
        raw=(runtime/'data/pub'/name).read_bytes();catalog[key]=parse(raw);catalog['source']['files'][key]['sha256']=hashlib.sha256(raw).hexdigest()
    for ident in [303,304,305]:
        graphic=str(catalog['npcs'][str(ident)]['graphic'])
        if graphic not in manifest['characters']['npcs']:raise ValueError('Missing already-exported NPC graphic '+graphic)
    for ident in range(1,493):
        if str(ident) not in catalog['items']:raise ValueError('Item catalog gap')
    for mid,record in catalog['maps'].items():
        source=runtime/('data/maps/%05d.emf'%int(mid));raw=source.read_bytes();world_path=out/record['path'].removeprefix('res://content/');world=json.loads(world_path.read_text())
        parsed=parse_emf(raw,int(mid));world.update(pk=parsed['pk'],map_effect=parsed['map_effect'])
        if int(mid) in (5,34,281):world['npcs']=parsed['npcs'];record['npc_spawns']=parsed['npcs']
        record.update(pk=parsed['pk'],map_effect=parsed['map_effect'],sha256=hashlib.sha256(raw).hexdigest())
        world_path.write_text(json.dumps(world,ensure_ascii=False,separators=(',',':'))+'\n')
    path.write_text(json.dumps(catalog,indent=2)+'\n')
    return dict(items=len(catalog['items']),npcs=len(catalog['npcs']),maps=len(catalog['maps']))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--out',type=Path,default=Path(__file__).resolve().parents[1]/'client/content');a=p.parse_args();print(json.dumps(sync(a.runtime,a.out)))
