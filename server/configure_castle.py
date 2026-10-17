"""Restore supplied arena rules and add the absent original Princess definition.

Run with the world stopped and backed up. Preserves all map art/warps/quests.
Princess151 is a passive combatant in the original PUB, not a service NPC.
"""
import argparse,hashlib,json,re
from pathlib import Path
from eo_session import Reader,number
ARENAS=(46,137,138,183,184)

def restore_princess(data):
    if data[:3]!=b'EMF' or len(data)<47:raise ValueError('Invalid castle map')
    count=Reader(data[46:47]).num();r=Reader(data[47:47+count*8]);found=False
    for _ in range(count):
        r.num();r.num();found |= r.num(2)==151;r.take(4)
    if found:return data,False
    if count>=250:raise ValueError('Too many castle spawns')
    # The source has no Princess spawn. Place her beside the current throne,
    # with ordinary passive-monster AI and a three-minute respawn.
    spawn=number(10,1)+number(5,1)+number(151,2)+number(3,1)+number(180,2)+number(1,1)
    end=47+count*8;raw=bytearray(data[:46]+number(count+1,1)+data[47:end]+spawn+data[end:])
    raw[3:7]=number(int.from_bytes(hashlib.sha256(raw[7:]).digest()[:4],'little')%(253**4),4)
    return bytes(raw),True

def configure(runtime,source):
    runtime=Path(runtime);source=Path(source);text=source.read_text(encoding='utf-8-sig')
    for rel in ('data','data/maps'):
        if (runtime/rel).is_symlink():raise ValueError('Materialize private runtime directory before modifying: '+rel)
    values={}
    for mid in ARENAS:
        fields={}
        for key in ('enabled','time','block','spawns'):
            m=re.search(r'^'+str(mid)+r'\.'+key+r'\s*=\s*([^#\r\n]+)',text,re.M)
            if not m:raise ValueError(f'Missing original arena {mid}.{key}')
            fields[key]=m.group(1).strip()
        coords=[int(v.strip()) for v in fields['spawns'].split(',')]
        if len(coords)%4 or not coords:raise ValueError('Invalid arena spawns')
        raw=(runtime/f'data/maps/{mid:05}.emf').read_bytes();width=Reader(raw[37:38]).num()+1;height=Reader(raw[38:39]).num()+1
        if any(not 0<=n<(width if i%2==0 else height) for i,n in enumerate(coords)):raise ValueError('Arena coordinates out of bounds')
        values[mid]=fields
    target=runtime/'data/aster-vale-arenas.ini'
    if target.is_symlink():target.unlink()
    target.write_text('# Original supplied arena timing and gate/destination coordinates.\n'+''.join(f'{mid}.{key} = {value}\n' for mid,fields in values.items() for key,value in fields.items()))
    local=runtime/'config.local.ini'
    if local.is_symlink():raise ValueError('Materialize private config before modifying')
    config=local.read_text();line='ArenasFile = ./data/aster-vale-arenas.ini'
    config=re.sub(r'^ArenasFile\s*=.*$',line,config,flags=re.M) if re.search(r'^ArenasFile\s*=',config,re.M) else config.rstrip()+'\n'+line+'\n'
    local.write_text(config)
    path=runtime/'data/maps/00281.emf';updated,added=restore_princess(path.read_bytes())
    # Private runtimes can contain individual symlinked map files. Detach before writing.
    if path.is_symlink():path.unlink()
    path.write_bytes(updated)
    return dict(arenas=values,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),princess_added=added,princess_id=151,princess_map=281,princess_spawn_center=[10,5],princess_original_combat_type=1,castle_map_sha256=hashlib.sha256(updated).hexdigest(),restart_required=True)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--source',type=Path,required=True);a=p.parse_args();print(json.dumps(configure(a.runtime,a.source)))
