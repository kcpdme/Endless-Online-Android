"""Targeted v15 upgrade; preserves encounters, rewards, shops and character data."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from balance_profile import VERSION, CLASSES
from class_signatures import SIGNATURES
from configure_balance import build_spells, records, encode_pub, put
from pet_catalog import TIERS, COMPANIONS, EGGS, HATCHED_EGGS


def configure(runtime):
    runtime = Path(runtime)
    binary = (runtime/'etheos').read_bytes()
    if any(marker not in binary for marker in (b'ClassRunRules', b'PercentPetUpkeep')):
        raise ValueError('Install the v15 native binary before enabling these rules')
    def read(name): return (runtime/name).read_bytes()
    def dump(value): return (json.dumps(value, indent=2)+'\n').encode()
    profile = json.loads(read('data/balance-profile.json'))
    if profile['version'] not in (14, VERSION): raise ValueError('Expected the installed v14 or v15 profile')
    manifest = json.loads(read('data/balance-v1-manifest.json'))
    source = runtime/'data/balance-v1-baseline/data/pub/dsl001.esf'
    spells_raw, spells = build_spells(source.read_bytes())
    items_raw = read('data/pub/dat001.eif')
    items = records(items_raw, b'EIF', 58)
    for ident in (*EGGS, *HATCHED_EGGS):
        put(items[ident-1]['fields'],57,0)
        profile['items'][str(ident)]['size'] = 0
    formula = read('data/formulas.ini').decode('latin1')
    formula, count = re.subn(r'^class\.0\.defence\s*=.*$', 'class.0.defence = '+CLASSES[6]['defence'], formula, flags=re.M)
    if count != 1: raise ValueError('Expected one Warrior family defence formula')
    profile.update(version=VERSION, spells=spells, companions=COMPANIONS, pet_tiers=TIERS,
                   running_rules=dict(normal_multiplier=1.25,rogue_multiplier=1.5,tp_rate_per_second=.015,drain_while_idle=True))
    for ident, signature in SIGNATURES.items(): profile['classes'][str(ident)]['signature'] = signature
    profile['classes']['8']['signature'] = SIGNATURES[2]
    profile['classes']['6']['build_hint'] = CLASSES[6]['hint']
    config = read('config.local.ini').decode()
    values = {'ClassRunRules':'yes','PercentPetUpkeep':'yes'}
    for ident, spell in spells.items():
        for key, value in [('level',spell['level_requirement']),('classes',','.join(map(str,spell['allowed_classes']))),('radius',spell['area_radius']),('targets',spell['area_targets'])]:
            values[f'BalanceSpell.{ident}.{key}'] = str(value)
    for ident, pet in COMPANIONS.items(): values[f'BalancePetSpell.{ident}.upkeep_rate'] = str(pet['upkeep_rate'])
    for key, value in values.items():
        pattern = r'^'+re.escape(key)+r'\s*=.*$'
        config = re.sub(pattern,key+' = '+value,config,flags=re.M) if re.search(pattern,config,re.M) else config.rstrip()+'\n'+key+' = '+value+'\n'
    proposed = {'data/pub/dsl001.esf':spells_raw,'data/pub/dat001.eif':encode_pub(items_raw,items),
                'data/formulas.ini':formula.encode('latin1'),'data/balance-profile.json':dump(profile),'config.local.ini':config.encode()}
    for name, raw in proposed.items():
        if name in manifest['installed']: manifest['installed'][name] = hashlib.sha256(raw).hexdigest()
    manifest['version'] = VERSION
    proposed['data/balance-v1-manifest.json'] = dump(manifest)
    before = {name:read(name) for name in proposed}
    changed = [name for name, raw in proposed.items() if raw != before[name]]
    try:
        for name in changed:
            path=runtime/name;tmp=path.with_suffix(path.suffix+'.v15-pending');tmp.write_bytes(proposed[name]);tmp.chmod(0o600 if name=='config.local.ini' else 0o644);tmp.replace(path)
    except BaseException:
        for name in changed:(runtime/name).write_bytes(before[name])
        raise
    return dict(version=VERSION,files_changed=changed,database_opened=False,
                shops_rewards_encounters_unchanged=True,
                sha256={name:hashlib.sha256(proposed[name]).hexdigest() for name in proposed})


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime',type=Path,required=True)
    parser.add_argument('--world-stopped',action='store_true',required=True)
    args=parser.parse_args();print(json.dumps(configure(args.runtime),indent=2))
