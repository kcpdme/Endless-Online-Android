#!/usr/bin/env python3
"""Conservative, logged syntax normalization for the pinned sample quest sources."""
import hashlib, pathlib, re

# Exact malformed strings observed in the pinned archive, corrected only in generated copies.
QUOTE_FIXES = {
    2: [('"Here, take it);', '"Here, take it");')],
    23: [('"Go to periperi for a reward!)', '"Go to periperi for a reward!")')],
    25: [('"Go to susan for a reward!)', '"Go to susan for a reward!")')],
}

DISABLED = {}

def prepare(directory):
    records=[]
    for path in sorted(pathlib.Path(directory).glob('*.txt')):
        if not path.stem.isdigit():continue
        original=path.read_bytes(); text=original.decode('latin1');changes=[];quest_id=int(path.stem)
        # etheos implements these existing functions, but its grammar requires the action keyword.
        def action(match):
            changes.append({'kind':'add_action_keyword','function':match.group(2),'line':text[:match.start()].count('\n')+1})
            return match.group(1)+'action '+match.group(2)+'('
        text=re.sub(r'^([ \t]*)(Reset|End|ShowHint)\(',action,text,flags=re.M|re.I)
        for old,new in QUOTE_FIXES.get(quest_id,[]):
            if old in text:
                changes.append({'kind':'close_unterminated_string','before':old,'after':new})
                text=text.replace(old,new)
        # These functions exist only in the server action table, never in its rule table.
        def action_kind(match):
            changes.append({'kind':'correct_action_keyword','function':match.group(2),'line':text[:match.start()].count('\n')+1})
            return match.group(1)+'action '+match.group(2)+'('
        text=re.sub(r'^([ \t]*)rule[ \t]+(Reset|RemoveItem)\(',action_kind,text,flags=re.M|re.I)
        # Internal state identifiers are not player text. Rename declarations and matching goto targets together.
        state_names=set(re.findall(r'^[ \t]*state[ \t]+([A-Za-z_][A-Za-z_0-9-]*)',text,flags=re.M|re.I))
        for name in sorted(state_names):
            if '-' not in name:continue
            replacement=name.replace('-','_')
            if replacement.lower() in {n.lower() for n in state_names}:raise RuntimeError(f'State rename collision in {path.name}')
            pattern=r'(\b(?:state|goto)[ \t]+)'+re.escape(name)+r'(?=[ \t\r\n{};]|$)'
            text,count=re.subn(pattern,lambda m:m.group(1)+replacement,text,flags=re.I)
            changes.append({'kind':'normalize_state_identifier','before':name,'after':replacement,'references':count})
        # Maze Master uses GoReset on every other cancellation branch. Its sole
        # dangling Reset goto is the same cancellation, not a missing reward state.
        if quest_id == 17:
            text,count=re.subn(r'(TalkedToNpc\(\s*17\s*\)\s+goto\s+)Reset\b',r'\1GoReset',text,flags=re.I)
            if count:changes.append({'kind':'repair_dangling_cancel_state','before':'Reset','after':'GoReset','references':count})
        if quest_id == 46 and not re.search(r'^\s*state\s+Begin\s*\{',text,flags=re.I|re.M):
            # Original Limbo script starts at Begin1. Keep it for saved progress,
            # and supply the native entry point expected by Quest_Use.
            text+='\nstate Begin\n{\n    action SetState("Begin1");\n}\n'
            changes.append({'kind':'add_missing_entry_state','entry':'Begin','original_start':'Begin1'})
        target=path.with_suffix('.eqf')
        if quest_id in DISABLED:
            if target.exists():target.unlink()
            disabled=path.parent.parent/'quests_disabled';disabled.mkdir(exist_ok=True)
            target=disabled/target.name
        target.write_bytes(text.encode('latin1'))
        records.append({'id':quest_id,'source':path.name,'target':str(target.relative_to(path.parent.parent)),
                        'enabled':quest_id not in DISABLED,'disabled_reason':DISABLED.get(quest_id),'source_sha256':hashlib.sha256(original).hexdigest(),
                        'generated_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'patches':changes})
    return records
