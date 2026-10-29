#!/usr/bin/env python3
"""Restore original artwork for every positive NPC graphic in an existing catalog."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from export_catalog import export_npc
from import_eo import PEBitmaps, read_member, write_json

def restore(graphics, output):
    manifest = json.loads((output / 'manifest.json').read_text())
    catalog = json.loads((output / 'catalog.json').read_text())
    records = manifest['characters']['npcs']
    with zipfile.ZipFile(graphics) as archive:
        source = PEBitmaps(read_member(archive, 'gfx/gfx021.egf'))
    added = []
    for definition in catalog['npcs'].values():
        gid = int(definition['graphic'])
        if gid <= 0 or str(gid) in records:
            continue
        records[str(gid)] = export_npc(gid, definition['name'], lambda _gfx, rid: source.image(rid), output)
        added.append({'graphic': gid, 'name': definition['name']})
    if added:
        catalog['available_npc_graphics'] = sorted(map(int, records))
        manifest['online_content']['npc_graphics'] = catalog['available_npc_graphics']
        write_json(output / 'catalog.json', catalog)
        manifest['online_content']['catalog_sha256'] = hashlib.sha256((output / 'catalog.json').read_bytes()).hexdigest()
        write_json(output / 'manifest.json', manifest)
    return {'added': added, 'total_graphics': len(records)}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--graphics', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('client/content'))
    args = parser.parse_args()
    print(json.dumps(restore(args.graphics, args.output), indent=2))
