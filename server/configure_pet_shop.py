"""Add one stationary Eggkeeper beside Aeven's existing market; preserve the map."""
import argparse,hashlib,json
from pathlib import Path
from eo_session import Reader,number
from pet_catalog import EGGKEEPER

def repair(raw):
    if raw[:3]!=b'EMF':raise ValueError('Expected Aeven EMF')
    r=Reader(raw);r.take(46);count=r.num();spawns=[]
    for _ in range(count):
        row=r.take(8);rd=Reader(row)
        x,y,ident=rd.num(),rd.num(),rd.num(2)
        if ident==EGGKEEPER['id']:
            expected=number(EGGKEEPER['x'],1)+number(EGGKEEPER['y'],1)+number(ident,2)+number(7,1)+number(180,2)+number(1,1)
            if row!=expected:raise ValueError('Eggkeeper placement changed')
            spawns.append(row)
        elif (x,y)==(EGGKEEPER['x'],EGGKEEPER['y']):raise ValueError('Eggkeeper tile is occupied by another spawn')
    if len(spawns)>1:raise ValueError('Duplicate Eggkeeper')
    if spawns:return raw
    if count>=252:raise ValueError('Map NPC capacity exceeded')
    from configure_sky_wonder import parse
    _,grids,_=parse(raw);point=(EGGKEEPER['x'],EGGKEEPER['y'])
    if any(point in grids[key] for key in ('specs','warps','objects')):raise ValueError('Eggkeeper tile is blocked or occupied')
    row=number(point[0],1)+number(point[1],1)+number(EGGKEEPER['id'],2)+number(7,1)+number(180,2)+number(1,1)
    result=bytearray(raw[:46]+number(count+1,1)+raw[47:r.pos]+row+raw[r.pos:])
    result[3:7]=number(int.from_bytes(hashlib.sha256(result[7:]).digest()[:4],'little')%253**4,4)
    return bytes(result)

def configure(runtime):
    p=Path(runtime)/'data/maps/00005.emf';raw=p.read_bytes();new=repair(raw)
    if new!=raw:
        pending=p.with_suffix('.pet-pending');pending.write_bytes(new);pending.chmod(p.stat().st_mode & 0o777);pending.replace(p)
    return dict(map_id=5,changed=raw!=new,sha256=hashlib.sha256(new).hexdigest(),database_opened=False)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',action='store_true',required=True);a=p.parse_args();print(json.dumps(configure(a.runtime),indent=2))
