"""Export repaired travel geometry without regenerating or changing graphics."""
import argparse,hashlib,json
from pathlib import Path
from export_catalog import SERVER_BLOCKING_SPECS
from import_eo import parse_emf,write_json

def export(runtime,out):
    runtime=Path(runtime);out=Path(out)
    raw=(runtime/'data/maps/00048.emf').read_bytes();world=parse_emf(raw,48)
    world['relog']=list(world['spawn']);world['spawn_semantics']='Legacy relog coordinates only; online position comes from server snapshots.'
    world['server_blocked']=[[s['x'],s['y']] for s in world['tile_specs'] if s['spec'] in SERVER_BLOCKING_SPECS]
    write_json(out/'maps/00048.json',world)
    catalog=json.loads((out/'catalog.json').read_text());catalog['maps']['48']['sha256']=hashlib.sha256(raw).hexdigest();write_json(out/'catalog.json',catalog)
    manifest=json.loads((out/'manifest.json').read_text());manifest['online_content']['catalog_sha256']=hashlib.sha256((out/'catalog.json').read_bytes()).hexdigest();write_json(out/'manifest.json',manifest)
    return dict(map_id=48,sha256=catalog['maps']['48']['sha256'])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args();print(json.dumps(export(a.runtime,a.output)))
