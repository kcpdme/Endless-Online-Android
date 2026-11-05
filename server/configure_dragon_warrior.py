"""Add Dragon armor recipes to a backed-up v15 runtime without changing drops/stats."""
import argparse, hashlib, json, os
from pathlib import Path
from dragon_warrior import ARMOR_RECIPES, NPC_ID, add_recipes


def digest(data):
    return hashlib.sha256(data).hexdigest()


def configure(runtime):
    runtime = Path(runtime)
    paths = ('data/aster-vale-shops.ini', 'data/balance-profile.json', 'data/balance-v1-manifest.json')
    before = {rel:(runtime/rel).read_bytes() for rel in paths}
    manifest = json.loads(before[paths[2]])
    for rel in paths[:2]:
        if manifest['installed'].get(rel) != digest(before[rel]):
            raise ValueError('Installed content changed: '+rel)
    profile = json.loads(before[paths[1]])
    if profile.get('version') != 15:
        raise ValueError('Expected the installed v15 balance profile')
    for ident, name, gender in ((458, 'Draco', 1), (459, 'Dracota', 0)):
        item = profile['items'][str(ident)]
        if (item.get('name'), item.get('gender'), item.get('type')) != (name, gender, 12) or 225 not in item.get('acquisition', {}).get('drop', []):
            raise ValueError('Expected original Dragon armor identities and drop source')
        vendors = item['acquisition'].setdefault('craft', [])
        if NPC_ID not in vendors:
            vendors.append(NPC_ID)
        # These recipes award the existing dropped armor, with no crafted-stat bonus.
    proposed = {
        paths[0]:add_recipes(before[paths[0]].decode('latin1')).encode('latin1'),
        paths[1]:(json.dumps(profile, indent=2)+'\n').encode(),
    }
    for rel, data in proposed.items():
        manifest['installed'][rel] = digest(data)
    proposed[paths[2]] = (json.dumps(manifest, indent=2)+'\n').encode()
    changed = [rel for rel in paths if proposed[rel] != before[rel]]
    try:
        for rel in changed:
            path = runtime/rel; pending = path.with_name(path.name+'.dragon-pending'); stat = path.stat()
            pending.write_bytes(proposed[rel])
            if (pending.stat().st_uid, pending.stat().st_gid) != (stat.st_uid, stat.st_gid):
                os.chown(pending, stat.st_uid, stat.st_gid)
            pending.chmod(stat.st_mode & 0o777)
            pending.replace(path)
    except BaseException:
        for rel in changed:
            (runtime/rel).write_bytes(before[rel])
            (runtime/rel).with_name(Path(rel).name+'.dragon-pending').unlink(missing_ok=True)
        raise
    return dict(files_changed=changed, npc_id=NPC_ID, recipes=ARMOR_RECIPES, drops_changed=False, pub_files_changed=False, database_opened=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, required=True)
    args = p.parse_args()
    print(json.dumps(configure(args.runtime), indent=2))
