#!/usr/bin/env python3
"""Restore original Ancient Wraith transparency/attack art in an existing pack."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from export_catalog import export_npc
from import_eo import PEBitmaps, read_member, write_json

def restore(graphics, output):
    manifest=json.loads((output/'manifest.json').read_text())
    catalog=json.loads((output/'catalog.json').read_text())
    definition=catalog['npcs']['255']
    if definition['name']!='Ancient Wraith' or definition['graphic']!=171:
        raise ValueError('Unexpected native Ancient Wraith definition')
    with zipfile.ZipFile(graphics) as archive:
        raw=read_member(archive,'gfx/gfx021.egf'); source=PEBitmaps(raw)
        def image(gfx,gid):
            if gfx!=21:raise ValueError('Unexpected NPC art source')
            return source.image(gid)
        character=export_npc(171,definition['name'],image,output)
    manifest['characters']['npcs']['171']=character
    catalog['missing_graphics']=[r for r in catalog.get('missing_graphics',[]) if r.get('npc_graphic')!=171]
    catalog['available_npc_graphics']=sorted(map(int,manifest['characters']['npcs']))
    manifest['online_content']['npc_graphics']=catalog['available_npc_graphics']
    write_json(output/'catalog.json',catalog)
    manifest['online_content']['catalog_sha256']=hashlib.sha256((output/'catalog.json').read_bytes()).hexdigest()
    write_json(output/'manifest.json',manifest)
    return dict(result='passed',npc_id=255,graphic=171,source_member='gfx/gfx021.egf',source_sha256=hashlib.sha256(raw).hexdigest(),invisible_states=character['transparent_poses'],visible_attack_resources=list(range(6813,6817)),shared_by_classic_and_enhanced=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--graphics',required=True,type=Path)
    parser.add_argument('--output',default=Path('client/content'),type=Path)
    args=parser.parse_args();print(json.dumps(restore(args.graphics,args.output),indent=2))

if __name__=='__main__':main()
