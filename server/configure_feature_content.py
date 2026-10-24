"""Install authored missing quests and restore Baru services in a stopped runtime.

Preserves every existing PUB entry, map layer/portal and all account data. Run
against a backed-up, stopped world; source data files are never edited in place.
"""
import argparse,hashlib,json,re,shutil
from pathlib import Path
from eo_session import Reader,number

ROOT=Path(__file__).resolve().parent

def pub_entries(data,signature,size):
    r=Reader(data)
    if r.take(3)!=signature:raise ValueError('Wrong PUB format')
    r.take(4);count=r.num(2);r.num();entries=[]
    for ident in range(1,count+1):
        start=r.pos;name=r.take(r.num()).decode('latin1');fields=r.take(size)
        entries.append(dict(id=ident,name=name,fields=fields,raw=data[start:r.pos]))
    if r.rest() or entries[-1]['name'].lower()!='eof':raise ValueError('PUB must end with EOF')
    return entries

def append_pub(data,signature,size,definitions):
    entries=pub_entries(data,signature,size)
    for ident,name,fields in definitions:
        raw=number(len(name.encode('latin1')),1)+name.encode('latin1')+fields
        if ident<len(entries):
            if entries[ident-1]['raw']!=raw:raise ValueError('Refusing to overwrite occupied PUB ID '+str(ident))
        elif ident==len(entries):entries.insert(-1,dict(id=ident,name=name,fields=fields,raw=raw))
        else:raise ValueError('PUB IDs must be consecutive')
    body=b''.join(e['raw'] for e in entries)
    revision=int.from_bytes(hashlib.sha256(body).digest()[:4],'little')%253**4
    return signature+number(revision,4)+number(len(entries),2)+data[9:10]+body

def spawn(data,ident,target):
    count=Reader(data[46:47]).num();r=Reader(data);r.take(47);occupied=set()
    for _ in range(count):
        x,y,npc=r.num(),r.num(),r.num(2);r.take(4);occupied.add((x,y))
        if npc==ident:return data,dict(id=ident,x=x,y=y)
    r.take(r.num()*4);r.take(r.num()*12);specs={};warps=set()
    for _ in range(r.num()):
        y=r.num()
        for _ in range(r.num()):x=r.num();specs[x,y]=r.num()
    for _ in range(r.num()):
        y=r.num()
        for _ in range(r.num()):x=r.num();r.take(7);warps.add((x,y))
    width=Reader(data[37:38]).num()+1;height=Reader(data[38:39]).num()+1
    points=[(x,y) for x in range(max(1,target[0]-8),min(width-1,target[0]+9)) for y in range(max(1,target[1]-8),min(height-1,target[1]+9)) if (x,y) not in occupied|warps and specs.get((x,y),-1) not in tuple(range(10))+(16,18,34,35,36)]
    if not points:raise ValueError('No safe NPC position')
    x,y=min(points,key=lambda p:abs(p[0]-target[0])+abs(p[1]-target[1]))
    if count>=250:raise ValueError('NPC spawn table full')
    record=number(x,1)+number(y,1)+number(ident,2)+number(7,1)+number(180,2)+number(1,1)
    end=47+count*8;raw=bytearray(data[:46]+number(count+1,1)+data[47:end]+record+data[end:])
    raw[3:7]=number(int.from_bytes(hashlib.sha256(raw[7:]).digest()[:4],'little')%253**4,4)
    return bytes(raw),dict(id=ident,x=x,y=y)

def configure(runtime):
    runtime=Path(runtime);npc_path=runtime/'data/pub/dtn001.enf';item_path=runtime/'data/pub/dat001.eif'
    original=npc_path.read_bytes();entries=pub_entries(original,b'ENF',39);definitions=[]
    for ident,name,template,typ,vendor in [(303,'Baru Shepherd (daily)',167,15,56),(304,'Baru Tailor',26,6,900),(305,'Royal Envoy',57,15,52)]:
        fields=bytearray(entries[template-1]['fields']);fields[7:9]=number(typ,2);fields[9:11]=number(vendor,2)
        if ident==304:fields[:2]=number(34,2)
        definitions.append((ident,name,bytes(fields)))
    npc_path.write_bytes(append_pub(original,b'ENF',39,definitions))
    from admin_weapon import patch_weapon
    original,_=patch_weapon(item_path.read_bytes());entries=pub_entries(original,b'EIF',58)
    # Restore the supplied Baru Flock at a new ID: 491 is the admin blade.
    fields=bytearray(entries[248]['fields']);fields[:2]=number(471,2);fields[2:3]=number(0,1);fields[4:5]=number(4,1);fields[55:56]=number(0,1)
    item_path.write_bytes(append_pub(original,b'EIF',58,[(492,'Baru Flock',bytes(fields))]))
    installed=[]
    for source in sorted((ROOT/'content/quests').glob('*.eqf')):
        target=runtime/'data/quests'/source.name
        if target.exists() and target.read_bytes()!=source.read_bytes():raise ValueError('Quest ID is occupied: '+source.name)
        shutil.copy2(source,target);installed.append(int(source.stem))
    # Repair the original orphaned daily quest's mismatching removal/reward,
    # retaining its original state names for any saved quest contexts.
    path=runtime/'data/quests/00056.eqf';text=path.read_text(encoding='latin1')
    old=re.compile(r'action\s+RemoveItem\(\s*254\s*,\s*10\s*\)',re.I)
    if old.search(text):text=old.sub('action RemoveItem(337, 5);\n    action RemoveItem(338, 5);\n    action GiveItem(492, 1);',text)
    if not re.search(r'GiveItem\(\s*492\s*,\s*1\s*\)',text,re.I):raise ValueError('Unrecognized Baru quest source')
    path.write_bytes(text.encode('latin1'))
    spawns=[]
    for mid,ident,point in [(34,303,(20,21)),(5,304,(37,46)),(281,305,(5,8))]:
        path=runtime/('data/maps/%05d.emf'%mid);data,entry=spawn(path.read_bytes(),ident,point)
        if path.is_symlink():path.unlink()
        path.write_bytes(data);spawns.append(dict(map_id=mid,**entry))
    shop=runtime/'data/aster-vale-shops.ini'
    if not shop.exists():shop=runtime/'data/shops.ini'
    text=shop.read_text();version=re.search(r'^Version\s*=\s*(\d+)',text,re.M);vendor=900 if version and int(version[1])>=2 else 304
    recipe=f'{vendor}.name = Baru Tailor\n{vendor}.craft = 430,492,5,1,10000,0,0,0,0, 431,492,5,1,10000,0,0,0,0\n'
    if f'{vendor}.craft' not in text:shop.write_text(text.rstrip()+'\n\n# Aster Vale restored Baru tailoring.\n'+recipe)
    elif recipe.strip() not in text:raise ValueError('Tailor service ID is occupied')
    speech=runtime/'data/speech.ini';text=speech.read_text()
    for ident,line in [(303,'Cool supplies are always welcome.'),(305,'The court welcomes travelers who lend a hand.')]:
        if f'{ident}.speech.1' not in text:text+=f'\n{ident}.frequency = 30\n{ident}.chance = 25%\n{ident}.speech.1 = {line}\n'
    speech.write_text(text)
    return dict(authored_quest_ids=installed,restored_daily_quest=56,baru_flock_id=492,admin_weapon_491_preserved=True,new_service_spawns=spawns)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',action='store_true',required=True);a=p.parse_args();print(json.dumps(configure(a.runtime),indent=2))
