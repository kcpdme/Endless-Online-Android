"""Restore classic cadence and full bow impact in a backed-up v15 runtime."""
import argparse,hashlib,json,os,re
from pathlib import Path
from combat_progression import BOWS,BASIC_ATTACK_SECONDS,CLIENT_ATTACK_SECONDS,ARCHER_ADJACENT_NPC_MULTIPLIER
from class_signatures import SIGNATURES


def configure(runtime):
    runtime=Path(runtime)
    paths=('data/balance-profile.json','config.local.ini','data/balance-v1-manifest.json')
    before={rel:(runtime/rel).read_bytes() for rel in paths}
    profile=json.loads(before[paths[0]])
    if profile.get('version')!=15:raise ValueError('Expected the installed v15 balance profile')
    for ident in BOWS:
        item=profile['items'][str(ident)]
        if item.get('type')!=10 or item.get('subtype')!=1:raise ValueError('Expected a known bow definition')
        item['attack_speed']=1.0
        item['shot_power']=1.0
        item.pop('close_attack_speed',None);item.pop('close_range',None)
    profile['attack_timing']=dict(server_seconds=BASIC_ATTACK_SECONDS,client_seconds=CLIENT_ATTACK_SECONDS,bow_speed_bonus=False,archer_adjacent_npc_damage_multiplier=ARCHER_ADJACENT_NPC_MULTIPLIER)
    if '5' in profile.get('classes',{}):profile['classes']['5']['signature']=SIGNATURES[5]
    config=before[paths[1]].decode()
    for ident in BOWS:
        # Remove obsolete keys, including their duplicate overrides, then write
        # one normal-rate/full-impact value. Reach and unrelated options survive.
        pattern=r'^BalanceItem\.'+str(ident)+r'\.(?:attack_speed|close_attack_speed|close_range|shot_power)\s*=.*(?:\n|$)'
        config=re.sub(pattern,'',config,flags=re.M)
        config=config.rstrip()+f'\nBalanceItem.{ident}.attack_speed = 1.0\nBalanceItem.{ident}.shot_power = 1.0\n'
    proposed={paths[0]:(json.dumps(profile,indent=2)+'\n').encode(),paths[1]:config.encode()}
    manifest=json.loads(before[paths[2]])
    for rel,data in proposed.items():
        if rel in manifest['installed']:manifest['installed'][rel]=hashlib.sha256(data).hexdigest()
    proposed[paths[2]]=(json.dumps(manifest,indent=2)+'\n').encode()
    changed=[rel for rel in paths if proposed[rel]!=before[rel]]
    try:
        for rel in changed:
            path=runtime/rel;pending=path.with_name(path.name+'.cadence-pending');stat=path.stat()
            pending.write_bytes(proposed[rel])
            # Operator migrations often run as root; mode 0600 alone does not
            # preserve the service's ability to read its private configuration.
            if (pending.stat().st_uid,pending.stat().st_gid)!=(stat.st_uid,stat.st_gid):os.chown(pending,stat.st_uid,stat.st_gid)
            pending.chmod(stat.st_mode&0o777);pending.replace(path)
    except BaseException:
        for rel in changed:(runtime/rel).write_bytes(before[rel])
        raise
    return dict(files_changed=changed,server_attack_seconds=BASIC_ATTACK_SECONDS,client_attack_seconds=CLIENT_ATTACK_SECONDS,bow_shot_power=1.0,database_opened=False,pub_files_changed=False)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--runtime',type=Path,required=True)
    parser.add_argument('--world-stopped',action='store_true',required=True);args=parser.parse_args()
    print(json.dumps(configure(args.runtime),indent=2))
