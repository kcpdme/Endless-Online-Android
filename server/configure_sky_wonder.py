"""Restore the walking cloud bridge; preserve Halowdale, beach and admin routes.

Run only against a backed-up, stopped runtime. All three maps are validated
before writing; repeat application is byte-identical. No database is opened.
"""
import argparse,hashlib,json
from pathlib import Path
from eo_session import Reader,number

MAPS=(23,71,73)
LAYERS=('ground','objects','overlay','walls_down','walls_right','roof','wall_top','shadow','overlay2')
ENTRANCES={(13,2):(73,19,11,0,0),(14,2):(73,19,12,0,0)}
AVENUE_LANDING=(14,5)
BRIDGE_LANDING=(11,11)
SKY_EXIT={(26,64),(27,64),(28,64),(26,65),(29,65),(26,66),(29,66),(26,67),(27,67),(28,67),(29,67)}
SIGN_TITLE='Sky Haven'
SIGN_BODY='Sky Wonder - cloud bridge. Follow this road through the stone gateway, then cross the bridge. The other roads lead to Halowdale, the beach and Aeven.'

def encoded_text(text,width=None):
    # Invert the original map-string decoder, including its alternating transform.
    out=[];flip=(len(text) if width is None else width)%2==1
    for value in text.encode('ascii'):
        def decoded(c):
            if flip:
                if 0x22<=c<=0x4f:return 0x71-c
                if 0x50<=c<=0x7e:return 0xcd-c
            elif 0x22<=c<=0x7e:return 0x9f-c
            return c
        match=next((c for c in range(32,127) if decoded(c)==value),None)
        if match is None:raise ValueError('Unsupported map text character')
        out.append(match);flip=not flip
    return bytes(reversed(out))

def warp(value):
    mid,x,y,level,door=value
    return number(mid,2)+number(x,1)+number(y,1)+number(level,1)+number(door,2)

def parse(data):
    if data[:3]!=b'EMF':raise ValueError('Expected EMF map')
    r=Reader(data);r.take(46);r.take(r.num()*8);r.take(r.num()*4);r.take(r.num()*12)
    prefix=data[:r.pos];grids={}
    for kind,size in [('specs',1),('warps',7)]+[(name,2) for name in LAYERS]:
        cells={}
        for _ in range(r.num()):
            y=r.num()
            for _ in range(r.num()):
                x=r.num();key=(x,y)
                if key in cells:raise ValueError('Duplicate map cell')
                cells[key]=r.take(size)
        grids[kind]=cells
    signs={}
    if r.rest():
        for _ in range(r.num()):
            x,y=r.num(),r.num();size=r.num(2);signs[x,y]=(r.take(size-1),r.num())
    if r.rest():raise ValueError('Unrecognized EMF trailing bytes')
    return prefix,grids,signs

def grid(cells):
    rows=sorted({y for x,y in cells});out=number(len(rows),1)
    for y in rows:
        xs=sorted(x for x,yy in cells if yy==y)
        out+=number(y,1)+number(len(xs),1)+b''.join(number(x,1)+cells[x,y] for x in xs)
    return out

def ensure(cells,key,old,new):
    current=cells.get(key)
    if current not in (old,new):raise ValueError('Reviewed map cell changed: '+str(key))
    cells[key]=new

def repair(mid,data):
    prefix,g,signs=parse(data);prefix=bytearray(prefix)
    if mid==23:
        if (Reader(data[37:39]).num(),Reader(data[38:39]).num())!=(28,40):raise ValueError('Avenue dimensions changed')
        for key,dest in ENTRANCES.items():
            if key in g['specs']:raise ValueError('Avenue portal became solid')
            ensure(g['warps'],key,None,warp(dest))
        # Original stone bridge posts and road-sign art make the new gate visible.
        for key,graphic in [((12,2),236),((15,2),236),((12,4),137)]:
            ensure(g['objects'],key,None,number(graphic,2));ensure(g['specs'],key,None,number(0,1))
        ensure(signs,(12,4),None,(encoded_text(SIGN_TITLE+SIGN_BODY),len(SIGN_TITLE)))
    elif mid==73:
        old_name=data[7:31]
        new_name=encoded_text('Sky Wonder Path',24).rjust(24,b'\xff')
        if old_name not in (b'\xff'*24,new_name):raise ValueError('Sky path identity changed')
        prefix[7:31]=new_name
        for key in [(20,11),(20,12)]:ensure(g['warps'],key,warp((23,2,14,0,0)),warp((23,*AVENUE_LANDING,0,0)))
        for key in [(11,11),(19,11),(19,12)]:
            if key in g['specs'] or key in g['warps']:raise ValueError('Bridge landing changed')
    elif mid==71:
        existing={key for key,value in g['warps'].items() if Reader(value).num(2) in (23,73)}
        if existing!=SKY_EXIT:raise ValueError('Sky Wonder return gate changed')
        for key in SKY_EXIT:ensure(g['warps'],key,warp((23,2,14,0,0)),warp((73,*BRIDGE_LANDING,0,0)))
    else:raise ValueError('Unreviewed map')
    result=prefix+b''.join(grid(cells) for cells in g.values())+number(len(signs),1)
    for (x,y),(text,title_length) in sorted(signs.items(),key=lambda s:(s[0][1],s[0][0])):
        result+=number(x,1)+number(y,1)+number(len(text)+1,2)+text+number(title_length,1)
    # Do not rewrite semantically unchanged repeat inputs, including revision.
    if result[7:]==data[7:]:return data
    result[3:7]=number(int.from_bytes(hashlib.sha256(result[7:]).digest()[:4],'little')%253**4,4)
    return bytes(result)

def configure(runtime):
    paths={mid:Path(runtime)/f'data/maps/{mid:05}.emf' for mid in MAPS}
    original={mid:p.read_bytes() for mid,p in paths.items()}
    updated={mid:repair(mid,raw) for mid,raw in original.items()}
    written=[]
    try:
        for mid,p in paths.items():
            if updated[mid]==original[mid]:continue
            pending=p.with_suffix('.sky-pending');pending.write_bytes(updated[mid]);pending.chmod(p.stat().st_mode & 0o777);pending.replace(p);written.append(mid)
    except BaseException:
        for mid in written:paths[mid].write_bytes(original[mid])
        raise
    return dict(maps_changed=written,maps={str(mid):hashlib.sha256(raw).hexdigest() for mid,raw in updated.items()},database_opened=False,admin_teleport_unchanged=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',action='store_true',required=True);a=p.parse_args();print(json.dumps(configure(a.runtime),indent=2))
