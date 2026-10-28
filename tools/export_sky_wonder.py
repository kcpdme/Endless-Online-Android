"""Sync the repaired native cloud-bridge geometry and original art to Android."""
import argparse,hashlib,json
from pathlib import Path
from export_catalog import SERVER_BLOCKING_SPECS
from import_eo import parse_emf,write_json

MAPS=(23,71,73)
def export(runtime,out):
    runtime=Path(runtime);out=Path(out)
    catalog=json.loads((out/'catalog.json').read_text());hashes={}
    for mid in MAPS:
        raw=(runtime/f'data/maps/{mid:05}.emf').read_bytes();world=parse_emf(raw,mid)
        world['relog']=list(world['spawn']);world['spawn_semantics']='Legacy relog coordinates only; online position comes from server snapshots.'
        world['server_blocked']=[[s['x'],s['y']] for s in world['tile_specs'] if s['spec'] in SERVER_BLOCKING_SPECS]
        write_json(out/f'maps/{mid:05}.json',world)
        entry=catalog['maps'][str(mid)];entry['sha256']=hashlib.sha256(raw).hexdigest();entry['name']=world['name'];hashes[str(mid)]=entry['sha256']
    write_json(out/'catalog.json',catalog)
    manifest=json.loads((out/'manifest.json').read_text());manifest['online_content']['catalog_sha256']=hashlib.sha256((out/'catalog.json').read_bytes()).hexdigest();write_json(out/'manifest.json',manifest)
    return dict(maps=hashes)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args();print(json.dumps(export(a.runtime,a.output)))
