"""Audit classic NPC combat roles and refresh Android's matching PUB catalog."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from configure_npc_combat import configure, records, ORIGINAL_ENF_SHA256, COMBAT_TYPES
from export_catalog import parse_npcs
from import_eo import read_member, write_json


def export(runtime, original_client, out):
    runtime, out = Path(runtime), Path(out)
    with zipfile.ZipFile(original_client) as archive:
        source = read_member(archive, 'pub/dtn001.enf')
    if hashlib.sha256(source).hexdigest() != ORIGINAL_ENF_SHA256:
        raise ValueError('Reference is not the verified official v28 NPC PUB')
    original = records(source)
    before = (runtime / 'data/pub/dtn001.enf').read_bytes()
    from configure_npc_combat import patch, quest_targets
    updated, _ = patch(before); current = records(updated)
    shared = sorted(original.keys() & current.keys()); mismatches = []
    protected_roles = []
    for ident in shared:
        a, b = original[ident], current[ident]
        if (a['type'] in COMBAT_TYPES or b['type'] in COMBAT_TYPES) and a['type'] != b['type']:
            mismatches.append(ident)
        elif a['type'] != b['type']:
            protected_roles.append(dict(id=ident, name=b['name'], original_type=a['type'], current_type=b['type']))
    if mismatches:
        raise ValueError('Combat roles differ from original: ' + str(mismatches))
    quest_targets(runtime / 'data/quests', current)
    report = configure(runtime)
    catalog = json.loads((out / 'catalog.json').read_text())
    manifest = json.loads((out / 'manifest.json').read_text())
    catalog['npcs'] = parse_npcs(updated)
    catalog['source']['files']['npcs']['sha256'] = hashlib.sha256(updated).hexdigest()
    write_json(out / 'catalog.json', catalog)
    manifest['online_content']['catalog_sha256'] = hashlib.sha256((out / 'catalog.json').read_bytes()).hexdigest()
    write_json(out / 'manifest.json', manifest)
    return dict(**report, original_record_count=len(original), shared_record_count=len(shared),
                combat_role_mismatches=mismatches, protected_quest_role_upgrades=protected_roles,
                later_npc_ids_preserved=sorted(current.keys() - original.keys()),
                reference_scope='Official v28 client has 255 definitions. Later 47 server definitions retained; no older counterpart exists in this reference.',
                sources=['Supplied EOzipped028.zip/pub/dtn001.enf',
                         'https://github.com/ethanmoffat/EndlessClient/blob/master/EOLib/Domain/Spells/SpellCastValidationActions.cs',
                         'https://apollo-games.com/eoclassic/npc.php?npc=122'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--original-client', type=Path, required=True)
    p.add_argument('--output', type=Path, default=Path('client/content'))
    a = p.parse_args()
    print(json.dumps(export(a.runtime, a.original_client, a.output), indent=2))
