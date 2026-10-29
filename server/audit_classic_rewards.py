"""Read-only comparison of native rewards against pinned classic facts and original ENF EXP."""
import argparse,json,re
from pathlib import Path
from configure_balance import records,num
from configure_classic_economy import DATA,ini
from pet_catalog import EGGS

def audit(runtime):
    runtime=Path(runtime);cfg={}
    def read(path,stack=()):
        path=path.resolve()
        if path in stack or not path.is_relative_to(runtime.resolve()) or not path.exists():return
        for line in path.read_text().splitlines():
            if line.lstrip().startswith('#'):continue
            key,sep,value=line.partition('=')
            if not sep:continue
            key=key.strip();value=value.split('#',1)[0].strip()
            if key in ('INCLUDE','INCLUDE_NOWARN','REQUIRE'):read(runtime/value,stack+(path,))
            else:cfg[key]=value
    read(runtime/'config.ini');cfg.update(ini((runtime/'config.local.ini').read_text()))
    def rate(key):
        raw=cfg.get(key,'100%');return float(raw.rstrip('%'))/(100 if raw.endswith('%') else 1)
    facts=json.loads(DATA.read_text());tables=ini((runtime/cfg.get('DropsFile','data/aster-vale-drops.ini')).read_text());issues=[];entries=0
    for npc in facts['npc_drops']:
        parts=[float(v.strip()) for v in tables.get(str(npc['npc_id']),'').split(',') if v.strip()]
        if len(parts)%4:raise ValueError('Malformed native drop table')
        actual=[tuple(parts[i:i+4]) for i in range(0,len(parts),4) if int(parts[i]) not in EGGS]
        expected=[(492 if row['id']==491 else row['id'],row['minimum'],row['maximum'],row['chance']) for row in npc['drops']]
        if actual!=expected:issues.append('Classic drop table differs: NPC '+str(npc['npc_id']))
        entries+=len(expected)
    old=records((runtime/'data/balance-v1-baseline/data/pub/dtn001.enf').read_bytes(),b'ENF',39)[:-1]
    current=records((runtime/'data/pub/dtn001.enf').read_bytes(),b'ENF',39)
    for before,after in zip(old,current):
        if num(before['fields'],36,3)!=num(after['fields'],36,3):issues.append('Original EXP differs: NPC '+str(before['id']))
    for key in ('ExpRate','DropRate','GoldDropRate'):
        if rate(key)!=1:issues.append(key+' is not x1')
    if cfg.get('DropRateMode')!='3':issues.append('Native drop selection mode is not classic mode3')
    if cfg.get('BonusSpiritEggDrops','no').lower() not in ('yes','true','1'):issues.append('Egg rolls can replace classic loot for Summoners')
    return dict(result='passed' if not issues else 'failed',classic_npc_drop_tables=len(facts['npc_drops']),classic_drop_entries=entries,original_npc_exp_definitions=len(old),exp_multiplier=rate('ExpRate'),item_drop_multiplier=rate('DropRate'),gold_drop_multiplier=rate('GoldDropRate'),goat_horn_chance_percent=10,goat_exp=num(current[6]['fields'],36,3),eggs_are_separate_bonus=cfg.get('BonusSpiritEggDrops','no').lower() in ('yes','true','1'),issues=issues,database_opened=False,files_modified=False)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);a=p.parse_args();result=audit(a.runtime);print(json.dumps(result,indent=2));raise SystemExit(0 if result['result']=='passed' else 1)
