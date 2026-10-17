"""Restore supplied original innkeepers/questions/beds using current native home syntax.

Keeps the existing default Aeven spawn and level tiers; no character DB writes.
The supplied legacy format names sleep coordinates separately; modern etheos
expects home.sleep = map,x,y and vendor IDs under Version2.
"""
from pathlib import Path
import hashlib,re

def install(runtime,source):
    runtime,source=Path(runtime),Path(source)
    if source.is_dir():source=source/'home.ini'
    raw=source.read_bytes();rows={}
    for line in raw.decode('utf-8-sig').splitlines():
        if line.lstrip().startswith('#'):continue
        key,sep,value=line.partition('=')
        if sep:rows[key.strip()]=value.split('#',1)[0].strip()
    # Read the original ENF vendor IDs, rather than inventing NPC behavior IDs.
    from eo_session import Reader
    r=Reader((runtime/'data/pub/dtn001.enf').read_bytes());r.take(7);count=r.num(2);r.num();vendors={}
    for ident in range(1,count+1):
        r.take(r.num());f=r.take(39)
        if Reader(f[7:9]).num(2)==7:vendors[ident]=Reader(f[9:11]).num(2)
    target=runtime/'data/aster-vale-home.ini';current=target.read_text()
    names=sorted(k.rsplit('.',1)[0] for k in rows if k.endswith('.innkeeper'))
    keep=[l for l in current.splitlines() if l.strip() and l!='# Original supplied innkeepers and native sleep locations.' and not any(l.strip().startswith(name+'.') for name in names) and not re.match(r'^Version\s*=',l)]
    result=['# Original supplied innkeepers and native sleep locations.','Version = 2',*keep]
    records=[]
    # Preserve the intentional current Aeven respawn used before inn support.
    old_aeven=re.search(r'^aeven.location\s*=\s*(.+)$',current,re.M)
    for name in names:
        npc=int(rows[name+'.innkeeper']);assert npc in vendors
        loc=rows[name+'.location']
        if name=='aeven' and old_aeven:loc=old_aeven.group(1)
        sleep=[int(rows[name+'.innsleep'+k]) for k in ('m','x','y')]
        # Header dimensions prove that imported sleep targets exist and are in bounds.
        data=(runtime/f'data/maps/{sleep[0]:05}.emf').read_bytes()
        from eo_session import read_number
        assert 0<=sleep[1]<=read_number(data[37:38]) and 0<=sleep[2]<=read_number(data[38:39])
        result += ['',f'{name}.name = {rows[name+".name"]}',f'{name}.location = {loc}',f'{name}.innkeeper = {vendors[npc]}',f'{name}.sleep = '+', '.join(map(str,sleep))]
        for index in range(1,4):
            for kind in ('question','answer'):result.append(f'{name}.{kind}{index} = {rows[f"{name}.{kind}{index}"]}')
        records.append(dict(home=name,npc_id=npc,vendor_id=vendors[npc],sleep=sleep))
    target.write_text('\n'.join(result).strip()+'\n')
    return dict(source_sha256=hashlib.sha256(raw).hexdigest(),output_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),inns=records,default_aeven_spawn_preserved=bool(old_aeven))
