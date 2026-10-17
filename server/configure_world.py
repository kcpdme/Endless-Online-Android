"""Configure native ground cleanup and weightless potions/scrolls.

Run with the world stopped, after backing up config.local.ini and dat001.eif.
The native world must restart to register its despawn timer and reload PUBs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from eo_session import Reader, number


def weightless_consumable(kind, name):
    name=name.casefold()
    return kind in (4,23,25) or any(word in name for word in ('potion','scroll')) or (kind==3 and any(word in name for word in ('elixer','elixir')))


def patch_item_weights(data):
    r=Reader(data)
    if r.take(3)!=b'EIF':raise ValueError('Not an EIF item file')
    r.take(4);count=r.num(2);r.num();result=bytearray(data);changed=[]
    for item_id in range(1,count+1):
        name=r.take(r.num()).decode('latin1');start=r.pos
        fields=r.take(58)
        if name.casefold()=='eof':break
        if weightless_consumable(Reader(fields[2:3]).num(),name) and Reader(fields[55:56]).num()!=0:
            result[start+55]=number(0,1)[0];changed.append(item_id)
    if r.rest():raise ValueError('Unconsumed EIF bytes')
    if changed:
        # Update the original PUB revision so classic clients also refresh it.
        revision=int.from_bytes(hashlib.sha256(result[7:]).digest()[:4],'little')%(253**4)
        result[3:7]=number(revision,4)
    return bytes(result),changed


def configure(runtime):
    runtime=Path(runtime);config=runtime/'config.local.ini';text=config.read_text()
    for key,value in dict(ItemDespawn='yes',ItemDespawnCheck='1m',ItemDespawnRate='10m').items():
        pattern=r'^'+key+r'\s*=.*$';line=f'{key} = {value}'
        text=re.sub(pattern,line,text,flags=re.MULTILINE) if re.search(pattern,text,re.MULTILINE) else text.rstrip()+'\n'+line+'\n'
    pub=runtime/'data/pub/dat001.eif';updated,changed=patch_item_weights(pub.read_bytes())
    pub.write_bytes(updated);config.write_text(text)
    return dict(cleanup_minutes_after_protection=10,cleanup_check_seconds=60,weightless_item_ids_changed=changed,database_modified=False,restart_required=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True)
    print(json.dumps(configure(p.parse_args().runtime)))
