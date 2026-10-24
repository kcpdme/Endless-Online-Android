"""Repair verified solid exit tiles without changing artwork, gates or accounts.

Apply only to a backed-up, stopped world. The three Estaq west exits have
valid warp records but Wall specs, preventing the native walk handler from
ever reaching those records. Remove only those contradictory specs.
"""
import argparse
import hashlib
import json
from pathlib import Path
from eo_session import Reader, number

EXITS = {(0,40):(40,42,20), (0,41):(40,42,21), (0,42):(40,42,22)}

def repair(data):
    if data[:3] != b'EMF': raise ValueError('Expected EMF map')
    r=Reader(data);r.take(46)
    r.take(r.num()*8);r.take(r.num()*4);r.take(r.num()*12)
    start=r.pos;rows=[];removed=[]
    for _ in range(r.num()):
        y=r.num();cells=[]
        for _ in range(r.num()):
            x,spec=r.num(),r.num()
            if (x,y) in EXITS:
                if spec != 0: raise ValueError('Reviewed exit spec changed')
                removed.append([x,y])
            else: cells.append(number(x,1)+number(spec,1))
        if cells: rows.append(number(y,1)+number(len(cells),1)+b''.join(cells))
    end=r.pos;found={}
    for _ in range(r.num()):
        y=r.num()
        for _ in range(r.num()):
            x=r.num();mid,dx,dy,level,door=r.num(2),r.num(),r.num(),r.num(),r.num(2)
            if (x,y) in EXITS: found[x,y]=(mid,dx,dy,level,door)
    if found != {p:(*dest,0,0) for p,dest in EXITS.items()}:
        raise ValueError('Reviewed Estaq exit destinations changed')
    if not removed: return data,[]
    result=bytearray(data[:start]+number(len(rows),1)+b''.join(rows)+data[end:])
    result[3:7]=number(int.from_bytes(hashlib.sha256(result[7:]).digest()[:4],'little')%253**4,4)
    return bytes(result),removed

def configure(runtime):
    path=Path(runtime)/'data/maps/00048.emf';old=path.read_bytes();new,removed=repair(old)
    if new != old:
        if path.is_symlink(): path.unlink()
        path.write_bytes(new)
    return dict(map_id=48,exits_repaired=removed,sha256=hashlib.sha256(new).hexdigest(),database_opened=False)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',action='store_true',required=True);a=p.parse_args()
    print(json.dumps(configure(a.runtime),indent=2))
