"""Synchronize the reviewed Aeven merchant spawn and catalog map identity."""
import hashlib,json
from pathlib import Path
from import_eo import parse_emf,write_json
from export_catalog import SERVER_BLOCKING_SPECS

def export(runtime,content):
    runtime=Path(runtime);content=Path(content);raw=(runtime/'data/maps/00005.emf').read_bytes();world=parse_emf(raw,5)
    world['relog']=list(world['spawn']);world['spawn_semantics']='Legacy relog coordinates only; online position comes from server snapshots.'
    world['server_blocked']=[[s['x'],s['y']] for s in world['tile_specs'] if s['spec'] in SERVER_BLOCKING_SPECS]
    write_json(content/'maps/00005.json',world)
    catalog=json.loads((content/'catalog.json').read_text());catalog['maps']['5'].update(sha256=hashlib.sha256(raw).hexdigest(),npc_spawns=world['npcs']);write_json(content/'catalog.json',catalog)
    manifest=json.loads((content/'manifest.json').read_text());manifest['online_content']['catalog_sha256']=hashlib.sha256((content/'catalog.json').read_bytes()).hexdigest();write_json(content/'manifest.json',manifest)
