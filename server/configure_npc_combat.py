"""Restore the combat differences verified against the supplied official v28 PUB.

Keep later quest-giver roles where both versions are protected. Run with the
world stopped and backed up; restart native world and gateway PUB caches.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from eo_session import Reader, number

ORIGINAL_ENF_SHA256 = '263f0259b07a960ab9ca72d33ba9ac3bdbab212cb2f1f2dd885baa0bef990ad7'
COMBAT_TYPES = (1, 2)
# ID: (name, graphic, original type, accepted supplied-server type).
RESTORE = {123: ('King', 94, 1, 15), 227: ('Vitaman', 151, 1, 2)}


def records(data):
    r = Reader(data)
    if r.take(3) != b'ENF':
        raise ValueError('Not an ENF NPC file')
    r.take(4); count = r.num(2); r.num(); result = {}
    for ident in range(1, count + 1):
        name = r.take(r.num()).decode('latin1'); start = r.pos; f = r.take(39)
        if name.casefold() == 'eof':
            break
        result[ident] = dict(id=ident, name=name, start=start,
                            graphic=Reader(f[:2]).num(2), type=Reader(f[7:9]).num(2),
                            hp=Reader(f[11:14]).num(3))
    if r.rest():
        raise ValueError('Unconsumed ENF bytes')
    return result


def patch(data):
    definitions = records(data); updated = bytearray(data); changes = []
    for ident, (name, graphic, original_type, supplied_type) in RESTORE.items():
        npc = definitions.get(ident)
        if not npc or (npc['name'], npc['graphic']) != (name, graphic):
            raise ValueError(f'Unexpected NPC identity at {ident}')
        if npc['type'] not in (original_type, supplied_type):
            raise ValueError(f'Unexpected NPC role at {ident}')
        if npc['type'] != original_type:
            updated[npc['start'] + 7:npc['start'] + 9] = number(original_type, 2)
            changes.append(dict(id=ident, name=name, before=npc['type'], after=original_type))
    if changes:
        revision = int.from_bytes(hashlib.sha256(updated[7:]).digest()[:4], 'little') % (253 ** 4)
        updated[3:7] = number(revision, 4)
    return bytes(updated), changes


def quest_targets(directory, definitions):
    targets = []
    for path in sorted(Path(directory).glob('*.eqf')):
        text = path.read_text(encoding='latin1')
        text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
        for match in re.finditer(r'\bKilledNpcs\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)', text, re.I):
            ident, amount = map(int, match.groups()); npc = definitions.get(ident)
            if not npc or npc['type'] not in COMBAT_TYPES:
                raise ValueError(f'{path.name} requires killing protected/unknown NPC {ident}')
            targets.append(dict(quest=path.stem, npc_id=ident, name=npc['name'], count=amount))
    return targets


def configure(runtime):
    runtime = Path(runtime)
    for rel in ('data', 'data/pub'):
        if (runtime / rel).is_symlink():
            raise ValueError('Materialize private data directory before modifying: ' + rel)
    path = runtime / 'data/pub/dtn001.enf'; before = path.read_bytes()
    updated, changes = patch(before)
    targets = quest_targets(runtime / 'data/quests', records(updated))
    # Individual fixture PUB files may link to production. Replace, never follow.
    if path.is_symlink():
        path.unlink()
    if changes or not path.exists():
        path.write_bytes(updated)
    return dict(changes=changes, original_enf_sha256=ORIGINAL_ENF_SHA256,
                before_sha256=hashlib.sha256(before).hexdigest(),
                after_sha256=hashlib.sha256(updated).hexdigest(),
                quest_kill_rules=targets, quest_kill_rules_valid=True,
                npc_count=len(records(updated)), database_modified=False,
                world_and_gateway_restart_required=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    print(json.dumps(configure(parser.parse_args().runtime), indent=2))
