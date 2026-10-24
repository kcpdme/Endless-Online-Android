"""Restore pinned classic Gold/shop facts without opening any account database.

Run on a backed-up, stopped world with etheos-classic-gold.patch installed.
Drop rates return to 100%; the EXP setting is preserved. Gold has its own rate.
"""
import argparse, hashlib, json, re
from pathlib import Path
from configure_feature_content import pub_entries
from eo_session import Reader

DATA=Path(__file__).resolve().parent/'content/classic-economy.json'
FEES=dict(InnSleepCostBase='0',InnSleepCostPerHP='1',InnSleepCostPerTP='1',
    BankUpgradeBase='1000',BankUpgradeStep='1000',BarberBase='0',BarberStep='200',
    MarriagePrice='500',DivorcePrice='10000',GuildPrice='50000',RecruitCost='1000',
    GuildMinDeposit='1000',JukeboxPrice='25',GoldDropRate='100%',DropRate='100%')

def ini(text):
    result={}
    for line in text.splitlines():
        key,sep,value=line.partition('=')
        if sep and not key.lstrip().startswith('#'):result[key.strip()]=value.split('#')[0].strip()
    return result

def packed(values):return ','.join(format(v,'.12g') for v in values)

def configure(runtime):
    runtime=Path(runtime);facts=json.loads(DATA.read_text());config_path=runtime/'config.local.ini'
    local=config_path.read_text();cfg=ini(local)
    if cfg.get('DropRateMode','3')!='3':raise ValueError('Classic Gold requires native DropRateMode 3')
    shop_path=runtime/cfg.get('ShopsFile','data/aster-vale-shops.ini')
    drop_path=runtime/cfg.get('DropsFile','data/aster-vale-drops.ini')
    shop_rows=ini(shop_path.read_text());drop_rows=ini(drop_path.read_text())
    version=int(shop_rows.get('Version','1'));npcs=pub_entries((runtime/'data/pub/dtn001.enf').read_bytes(),b'ENF',39)
    items=pub_entries((runtime/'data/pub/dat001.eif').read_bytes(),b'EIF',58)
    assert items[490]['name']=="Skylar's Admin Blade" and items[491]['name']=='Baru Flock'
    def item_id(value):return 492 if value==491 else value # classic Flock ID is occupied by the admin blade
    restored=[];changed=[]
    for shop in facts['shops']:
        for npc_id in shop['npc_ids']:
            entry=npcs[npc_id-1];fields=entry['fields']
            if Reader(fields[7:9]).num(2)!=6:raise ValueError('Classic shop NPC type changed: '+str(npc_id))
            ident=Reader(fields[9:11]).num(2) if version>=2 else npc_id
            rows={str(ident)+'.name':shop['name']}
            rows[str(ident)+'.trade']=packed([v for row in shop['trade'] for v in [item_id(row['id']),row['buy'],row['sell']]])
            craft=[]
            for row in shop['craft']:
                ingredients=[[item_id(k),v] for k,v in row['ingredients']]
                craft.extend([item_id(row['id']),*[v for pair in ingredients+[[0,0]]*(4-len(ingredients)) for v in pair]])
            rows[str(ident)+'.craft']=packed(craft)
            for key,value in rows.items():
                if shop_rows.get(key,'')!=value:changed.append(key)
                shop_rows[key]=value
            restored.append(npc_id)
    # Every combat NPC is covered, including explicit empty classic tables.
    # Public displayed chances already include classic proportional caps.
    expected={r['id'] for r in npcs[:-1] if Reader(r['fields'][7:9]).num(2) in (1,2)}
    observed={row['npc_id'] for row in facts['npc_drops']}
    if expected!=observed:raise ValueError('Classic drop snapshot does not cover every combat NPC')
    drops={}
    for entry in facts['npc_drops']:
        rows=[]
        for row in entry['drops']:
            ident=item_id(row['id'])
            if not 0<ident<len(items) or ident==491:raise ValueError('Invalid or admin-only classic drop')
            rows.append([ident,row['minimum'],row['maximum'],row['chance']])
        drops[entry['npc_id']]=rows
    removed_reserved=sum(bool(re.search(r'(?:^|,)\s*491\s*,',value)) for key,value in drop_rows.items() if key.isdigit())
    for key,value in FEES.items():
        pattern=r'^'+key+r'\s*=.*$';line=key+' = '+value
        local=re.sub(pattern,line,local,flags=re.M) if re.search(pattern,local,re.M) else local.rstrip()+'\n'+line+'\n'
    # Prepare every output before writing any file. The caller owns backups.
    shop_text='# Classic prices/recipes: pinned Apollo EO Classic database.\n'+'\n'.join(k+' = '+v for k,v in shop_rows.items())+'\n'
    drop_text='# Classic monster drop amounts/chances: pinned Apollo EO Classic database.\n'+'\n'.join(str(k)+' = '+', '.join(packed(row) for row in rows) for k,rows in sorted(drops.items()))+'\n'
    shop_path.write_text(shop_text);drop_path.write_text(drop_text);config_path.write_text(local)
    return dict(shops_restored=len(restored),shop_npc_ids=restored,changed_shop_fields=changed,
        gold_tables_restored=len(facts['gold']),monster_tables_restored=len(drops),drop_rate='100%',reserved_legacy_drops_removed=removed_reserved,
        classic_inn_formula='missing_hp + missing_tp',bank_upgrade_formula='1000 + upgrades * 1000',
        database_opened=False,sha256={str(p.relative_to(runtime)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [shop_path,drop_path,config_path]})

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',action='store_true',required=True);a=p.parse_args()
    print(json.dumps(configure(a.runtime),indent=2))
