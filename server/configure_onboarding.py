"""Restore the supplied classic island start, craft and level-gated boat journey.

Run against a stopped, backed-up world. No database or original map is rewritten.
The reward-free native journey quest records the new player's changing home;
existing mainland characters keep their current home and possessions.
"""
import argparse,json,re
from pathlib import Path
from configure_starters import patched_config
from configure_sky_wonder import parse
from eo_session import Reader

QUEST = '''// Aster Vale routing glue for the supplied classic Tutorial Island maps.
// No item, Gold or EXP grants. Existing mainland characters retain their home.
Main
{
    questname "Journey to Aeven"
    version 1
}
state Begin
{
    rule EnterMap(192) goto Island
    rule Always() goto Existing
}
state Island
{
    desc "Train on Tutorial Island; take the boat at level 4"
    action SetHome("tutorialisland");
    action ShowHint("Tutorial Island: get your first outfit from the house chest. Craft a dagger at Cyndi's with 2 Goat Horns. Train to level 4, then board the boat at the island dock.");
    rule EnterMap(1) goto Mainland
    rule EnterMap(5) goto Aeven
}
state Mainland
{
    desc "Reach level 5, then enter Aeven north of the sheep fields"
    action SetHome("mainlandarrival");
    action ShowHint("Welcome to the mainland. Follow the road north through the sheep fields. Aeven's gate requires level 5.");
    rule EnterMap(5) goto Aeven
}
state Aeven
{
    action SetHome("aeven");
    action ShowHint("You have reached Aeven. Visit the Wise Man to choose your class.");
    action End();
}
state Existing
{
    action End();
}
'''
HOMES={'tutorialisland':('Tutorial Island','192, 7,6'), 'mainlandarrival':('Mainland Arrival','1, 7,21')}

def destination(raw):
    r=Reader(raw);return (r.num(2),r.num(),r.num(),r.num(),r.num(2))

def configure(runtime):
    runtime=Path(runtime)
    cfg=runtime/'config.local.ini';text=cfg.read_text()
    m=re.search(r'^HomeFile\s*=\s*([^#\r\n]+)',text,re.M)
    if not m:raise ValueError('A configured native home file is required')
    home_path=runtime/m[1].strip()
    if home_path.is_symlink():raise ValueError('Materialize the home file before writing')
    home=home_path.resolve()
    if not home.is_relative_to(runtime.resolve()):raise ValueError('Home file must stay inside the runtime')
    for p in [cfg,home,runtime/'data',runtime/'data/quests']:
        if p.is_symlink():raise ValueError('Materialize runtime paths before restoring onboarding')
    home_text=home.read_text()
    if not re.search(r'^aeven\.location\s*=\s*5\s*,\s*40\s*,\s*40\s*$',home_text,re.M):raise ValueError('Existing Aeven home changed')
    maps={mid:parse((runtime/f'data/maps/{mid:05}.emf').read_bytes()) for mid in (1,2,190,192,193,194,195)}
    if (7,6) in maps[192][1]['specs']:raise ValueError('Original birth tile is blocked')
    if destination(maps[195][1]['warps'].get((21,6),b''))!=(1,7,21,4,1):raise ValueError('Original level-4 boat crossing changed')
    if destination(maps[2][1]['warps'].get((13,0),b''))!=(5,39,85,5,0):raise ValueError('Original level-5 Aeven gate changed')
    shops=(runtime/'data/aster-vale-shops.ini').read_text()
    craft=re.search(r'^100\.craft\s*=\s*(.*)$',shops,re.M)
    if not craft or list(map(int,craft[1].replace(' ','').split(',')))[:9]!=[21,258,2,0,0,0,0,0,0]:raise ValueError('Cyndi must retain the two-Goat-Horn dagger recipe')
    for ident,(name,where) in HOMES.items():
        for key,value in [('name',name),('location',where)]:
            line=f'{ident}.{key} = {value}';old=re.search(r'^'+re.escape(ident+'.'+key)+r'\s*=\s*(.*)$',home_text,re.M)
            if old and old[1].strip()!=value:raise ValueError('Reserved onboarding home changed: '+ident)
            if not old:home_text=home_text.rstrip()+'\n'+line+'\n'
    quest=runtime/'data/quests/00000.eqf'
    if quest.exists() and quest.read_text()!=QUEST:raise ValueError('Quest 0 already has different authored content; refusing to overwrite it')
    proposed={cfg:patched_config(text).encode(),home:home_text.encode(),quest:QUEST.encode()}
    before={p:p.read_bytes() if p.exists() else None for p in proposed}
    try:
        for p,data in proposed.items():p.write_bytes(data)
        cfg.chmod(0o600)
    except BaseException:
        for p,data in before.items():
            if data is None:p.unlink(missing_ok=True)
            else:p.write_bytes(data)
        raise
    return dict(start=[192,7,6],initial_inventory=[],initial_equipment=[],initial_spells=[],outfit_source='Original house chest',dagger_recipe=dict(shop='Cyndi',item_id=21,goat_horns=2),boat=dict(map_id=195,tile=[21,6],required_level=4,arrival=[1,7,21]),aeven_required_level=5,death_home_progression=['Tutorial Island until departure','Mainland arrival until entering Aeven','Aeven'],map_bytes_changed=False,database_modified=False,restart_required=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',action='store_true',required=True)
    print(json.dumps(configure(p.parse_args().runtime),indent=2))
