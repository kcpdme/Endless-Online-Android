"""Apply castle restoration and export its map metadata and original Princess art."""
import argparse,json,sys,zipfile,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'server'))
from configure_castle import configure
from export_catalog import export_npc,SERVER_BLOCKING_SPECS
from import_eo import parse_emf,PEBitmaps,read_member,write_json

def export(runtime,source,graphics,out):
    runtime=Path(runtime);out=Path(out);report=configure(runtime,source)
    catalog=json.loads((out/'catalog.json').read_text());manifest=json.loads((out/'manifest.json').read_text())
    for mid in [46,137,138,183,184,281]:
        raw=(runtime/f'data/maps/{mid:05}.emf').read_bytes();world=parse_emf(raw,mid)
        world['relog']=list(world['spawn']);world['spawn_semantics']='Legacy relog coordinates only; online position comes from server snapshots.'
        world['server_blocked']=[[e['x'],e['y']] for e in world['tile_specs'] if e['spec'] in SERVER_BLOCKING_SPECS]
        record=catalog['maps'][str(mid)];record.update(npc_spawns=world['npcs'],sha256=hashlib.sha256(raw).hexdigest())
        if str(mid) in [str(n) for n in report['arenas']]:
            arena=report['arenas'][mid];coords=[int(s.strip()) for s in arena['spawns'].split(',')]
            world['arena']={'interval_seconds':int(arena['time']),'gates':[[coords[i],coords[i+1]] for i in range(0,len(coords),4)]}
            record['arena']=world['arena']
        (out/f'maps/{mid:05}.json').write_text(json.dumps(world,ensure_ascii=False,separators=(',',':'))+'\n')
    with zipfile.ZipFile(graphics) as z:
        pe=PEBitmaps(read_member(z,'gfx/gfx021.egf'))
        manifest['characters']['npcs']['115']=export_npc(115,'Princess',lambda gfx,gid:pe.image(gid),out)
    catalog['available_npc_graphics']=sorted(int(g) for g in manifest['characters']['npcs'])
    manifest['online_content']['npc_graphics']=catalog['available_npc_graphics']
    write_json(out/'catalog.json',catalog)
    manifest['online_content']['catalog_sha256']=hashlib.sha256((out/'catalog.json').read_bytes()).hexdigest()
    write_json(out/'manifest.json',manifest)
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--graphics',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args();print(json.dumps(export(a.runtime,a.source,a.graphics,a.output)))
