"""Set native NPC rewards relative to original PUB/drop-table values.

Apply with the world stopped, after backing up config.local.ini. Native mode3
requires etheos-drop-rate.patch so DropRate is honored by its weighted table.
"""
import argparse,json,re
from pathlib import Path

def configure(runtime):
    path=Path(runtime)/'config.local.ini';text=path.read_text()
    for key,value in {'ExpRate':'1000%','DropRate':'200%'}.items():
        pattern=r'^'+key+r'\s*=.*$';line=f'{key} = {value}'
        text=re.sub(pattern,line,text,flags=re.MULTILINE) if re.search(pattern,text,re.MULTILINE) else text.rstrip()+'\n'+line+'\n'
    path.write_text(text)
    return dict(npc_exp_multiplier=10,npc_item_drop_chance_multiplier=2,drop_quantities_changed=False,quest_rewards_changed=False,restart_required=True)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True)
    print(json.dumps(configure(p.parse_args().runtime)))
