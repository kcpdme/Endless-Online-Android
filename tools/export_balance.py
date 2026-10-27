#!/usr/bin/env python3
"""Sync balance values without replacing art, and export a standalone HTML catalog."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'server'))
from configure_balance import records, num
from balance_model import benchmarks
from balance_audit import audit


def export(runtime, content, report):
    profile = json.loads((runtime / 'data/balance-profile.json').read_text())
    catalog_path = content / 'catalog.json'
    catalog = json.loads(catalog_path.read_text())
    manifest_path = content / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    for section in ('items', 'spells', 'classes', 'npcs'):
        current = catalog[section]
        for ident, update in profile.get(section, {}).items():
            template = str(update.get('template_id', ident))
            merged = dict(current.get(ident, current.get(template, {})))
            merged.update(update)
            current[ident] = merged
    for row in records((runtime / 'data/pub/dtn001.enf').read_bytes(), b'ENF', 39)[:-1]:
        npc = catalog['npcs'][str(row['id'])]
        for key, offset, size in [('hp',11,3),('min_damage',16,2),('max_damage',18,2),('accuracy',20,2),('evade',22,2),('armor',24,2),('exp',36,3)]:
            npc[key] = num(row['fields'], offset, size)
    catalog['balance_version'] = profile['version']
    for section, name in [('items','dat001.eif'),('spells','dsl001.esf'),('classes','dat001.ecf'),('npcs','dtn001.enf')]:
        catalog['source']['files'][section]['sha256'] = hashlib.sha256((runtime/'data/pub'/name).read_bytes()).hexdigest()
    catalog_path.write_text(json.dumps(catalog, indent=2)+'\n')
    manifest['online_content']['catalog_sha256'] = hashlib.sha256(catalog_path.read_bytes()).hexdigest()
    manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')

    def table(headers, rows, ident=''):
        return '<div class="scroll"><table id="'+ident+'"><thead><tr>'+''.join('<th>'+html.escape(str(h))+'</th>' for h in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(value))+'</td>' for value in row)+'</tr>' for row in rows)+'</tbody></table></div>'
    classes = profile['classes']
    def class_name(ident): return classes.get(str(ident), {}).get('name', 'Any') if ident else 'Any'
    types = {10:'Weapon',11:'Shield / arrows',12:'Body / clothes',13:'Hat',14:'Boots',15:'Gloves',16:'Accessory',17:'Belt',18:'Necklace',19:'Ring',20:'Armlet',21:'Bracer'}
    equipment = [i for i in profile['items'].values() if 10 <= i['type'] <= 21]
    equipment.sort(key=lambda i:(i['type'], i['level_requirement'], i['id']))
    item_rows = [[i['id'],i['name'],types[i['type']],i['level_requirement'],', '.join(class_name(c) for c in i.get('allowed_classes', [])) or 'Any',('M' if i['gender'] else 'F') if i['type']==12 else 'Any',f"{i['min_damage']}–{i['max_damage']}",i.get('archetype','balanced'), 'Craft edge' if i.get('crafted') else 'Standard',i['armor'],i['accuracy'],i['evade'],i['hp'],i['tp'],*(i[a] for a in ('strength','intelligence','wisdom','agility','constitution','charisma'))] for i in equipment]
    spell_rows = [[i['id'],i['name'],i['level_requirement'],', '.join(class_name(c) if c!=-1 else 'Admin' for c in i['allowed_classes']) or 'Any',i['tp'],i['cast_time'],('Spirit / dismiss' if i.get('effect_kind')=='companion' else i['hp'] if i['type']==0 else f"{i['min_damage']}–{i['max_damage']}"),f"Radius {i['area_radius']}, max {i['area_targets']}" if i['area_radius'] else 'Single / party' if i['type']==0 else 'Single'] for i in profile['spells'].values()]
    model = benchmarks(profile)
    model_rows = [[r['level'],r['role'],profile['items'][str(r['weapon_id'])]['name'],profile['items'][str(r['body_id'])]['name'],r['max_hp'],r['max_tp'],r['armor'],r['basic_dps'],r['burst_dps'],r['companion_dps'],r['backstab_dps'],r['passive_hp_per_second'],r['spell_casts_from_full'],r['heal_self']] for r in model]
    recovery = [profile['items'][str(i)] for i in (2,3,4,5,375,376,377)]
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Aster Vale · level 1–50 balance</title>
<style>body{margin:0;background:#111922;color:#e5edf5;font:16px/1.6 system-ui}main{max-width:1440px;margin:auto;padding:32px}h1{font-size:36px;line-height:1.15}h2{margin-top:44px}p{max-width:950px;color:#bccbd9}a{color:#8ad4be}.scroll{overflow:auto;border:1px solid #344454;border-radius:8px;margin:20px 0}table{border-collapse:collapse;width:100%;font-size:14px;white-space:nowrap}td,th{padding:9px 12px;text-align:left;border-bottom:1px solid #293642}th{background:#223141;position:sticky;top:0}tr:nth-child(even){background:#172330}input{padding:12px;background:#223141;color:white;border:1px solid #597083;border-radius:6px;width:min(90%,500px)}.tag{color:#8ad4be}nav a{margin-right:20px}</style><main>
<div class="tag">Aster Vale · Balance profile 3</div><h1>A reason to play every class.<br>A worthwhile upgrade after Oron.</h1>
<p>This implementation concentrates the main equipment journey into levels 1–50. Existing level and EXP records stay intact. Levels above 50 remain possible. The original cubic EXP curve and the world's existing EXP rate are preserved.</p>
<nav><a href="#roles">Classes</a><a href="#coverage">Coverage audit</a><a href="#eggs">Pet eggs</a><a href="#progression">Progression</a><a href="#equipment">All equipment</a><a href="#spells">All spells</a><a href="#recovery">Potions</a></nav>
<h2 id="roles">Class roles and attributes</h2>'''
    page += table(['Class','Build and role','Unique ability'],[[classes[str(i)]['name'],classes[str(i)]['build_hint'],classes[str(i)].get('signature',{}).get('description','')] for i in range(2,8)])
    page += '<p>Warrior has the strongest HP/armour foundation. Rogue trades some durability for AGI accuracy and evasion. Archer gains distance through native bow attacks. Magician has strong TP-funded burst and bounded area damage. Priest has affordable Holy Light for solo play and the strongest healing. Summoner uses CHA/INT attacks and one real spirit companion. Only Priests cast healing spells. Potions remain common recovery for every class.</p>'
    page += '<h2>Class identity and safe class changes</h2><p>The server checks current class and level when equipping, training and casting, and again when a spell executes. Changing class returns incompatible weapons, arrows and clothes to your bag and recalculates their bonuses. Learned off-class skills remain owned, visibly locked until you return to their class. At the inventory hard cap a worn copy stays inert rather than being deleted. Bows and arrows belong to Archers; daggers and Hidden Blade specialise in Rogue; staves, vestments and spirit foci have their own class owners. Starter tools, ordinary accessories, costumes and selected hybrid armour remain common.</p><h2>What Summoner does</h2><p>Hatch an egg to permanently learn its summon. Summon Spirit Wolf at level 8 (18 TP; 2 TP every 2 seconds), Spirit Wurm at 25 (30 TP; upkeep 3), and Spirit Drake at 40 (45 TP; upkeep 4). One visible native companion follows you while you can pay its TP upkeep. It assists the monster you actively attack and stops five seconds after your last attack. Its damage scales with CHA, INT and level. Recasting replaces it; Dismiss Companion is free. Mana exhaustion, changing class, travel, death or logout removes it. Spirits are PvE assistants: they cannot tank, drop loot, fight in PK areas or farm unattended. Their damage uses the owner’s normal kill/reward attribution. The pet is part of Summoner’s combined damage budget.</p><h2>Equipment variety and crafting</h2><p>Heavy weapons trade accuracy for a harder hit; Rogue precision weapons add accuracy and evade; spears improve reach-themed attack stats; caster foci add TP. Warrior armour adds HP/CON, Rogue clothes evade, Archer clothes accuracy, and caster robes mana and their primary attribute. Recipe-only equipment gets a bounded crafting edge. The new level-25 Rogue Hidden Blade and level-8 Reinforced Hunting Bow are distinct crafted definitions; buying and crafting the same item ID produces the same stats. Cosmetic recolours remain equivalent.</p><h2 id="progression">Progression at 1, 8, 15, 25, 35 and 45</h2><p>Oron / Orona sits at level 25. Hero Plate and Draco provide level-35 alternatives. Baru at 45 improves every Oron combat bonus; its recipe consumes Oron and six Baru Flocks. Every class also gets a level-45 weapon and male/female body reward. Intermediate equipment is sold by existing shops; final recipes use earlier gear, Dragon Claws, Dragon Wings and Gold.</p><p>The table below is a deterministic comparison, not measured sustained DPS. It uses weapon, body, head, boots, gloves and two ring slots plus basic Archer arrows, a 60/25/15 primary/CON/secondary stat split, untrained skills, no criticals or kiting, target armour 0.4 × level and evasion 0.6 × level. Burst chooses basic attacks or a single-target spell while TP is available. Summoner includes an adjacent commanded spirit; this assumes active fighting and sufficient upkeep mana. Pathing and downtime reduce real pet output. Casts shows the offensive spell budget before recovery. Backstab DPS is conditional on remaining directly behind the target with a Rogue blade and excludes critical stacking. HP/s is standing Priest renewal. Front-facing burst stays separate from these advantages. Real enemies, movement, positioning and party healing change outcomes.</p>'
    page += table(['Level','Class','Weapon','Body','HP','TP','Armour','Basic DPS','Burst DPS','Spirit DPS','Rear-only DPS','Passive HP/s','Casts','Self heal'],model_rows)
    coverage=audit(profile)
    page += '<h2 id="coverage">Every class, every milestone</h2><p>Each cell shows obtainable definitions, with exclusive class definitions in brackets. Common starter accessories stay useful. Both character genders have usable clothes at every milestone. All benchmark equipment has a real shop, recipe or monster-drop route; a missing route fails the audit. These are available definitions, not a promise that every reward is equally easy to acquire.</p>'
    page += table(['Level','Class','Weapons','Bodies','Head','Boots','Gloves','Rings','Skills'],[[r['level'],r['class_name'],*[f"{r['slots'][slot]['total']} ({r['slots'][slot]['exclusive']})" for slot in ('weapon','body','head','boots','gloves','ring')],r['skills']] for r in coverage['coverage']])
    page += '<h2 id="eggs">Monster eggs and permanent spirit bonds</h2><p>The supplied EODelta source has configurable item hatching, but its sample configuration reuses ordinary potions and its sample item catalog has no named egg definitions. This implementation uses the current native companion system, three explicit new egg items and original SVG egg icons. Hatch once to learn permanently; call the pet through its skill and pay the usual TP. Only a Summoner at the required level can hatch. Duplicate, under-level and off-class attempts preserve the egg. Existing learned summons remain owned. The Aeven Staff Smith also crafts eggs from monster materials, so progression has a reliable route.</p>'
    page += table(['Egg','Level','Monster','Base drop chance','Learned skill'],[[e['name'],e['level'],catalog['npcs'].get(str(e['npc_id']),{}).get('name',e['npc_id']),str(e['chance'])+'%',profile['spells'][str(e['spell_id'])]['name']] for e in profile.get('eggs',{}).values()])
    page += '<p>Drop chances are source-table values; the world’s drop multiplier and weighted drop mode determine the effective result. No other original drops are removed. Wolf egg: five Wolfman Furs, five Snake Teeth, 100 Gold. Wurm egg: six Wurm Heads, three Worm Segments, 200 Gold. Drake egg: two Dragon Claws, two Dragon Wings, 200 Gold. Hatching does not spawn a free extra pet or remove TP upkeep.</p>'
    page += '<h2 id="equipment">All '+str(len(equipment))+' equipment definitions</h2><p>Requirements and bonuses below are the installed native values. Male/female partners have equal combat budgets. Cosmetic peers intentionally share stats. Operator-only and legacy special items remain identifiable by their original names; they are excluded from the player progression model.</p><input id="filter" aria-label="Filter equipment" placeholder="Search equipment, class or slot…">'
    page += table(['ID','Name','Slot','Level','Class','Gender','Damage','Style','Source','Armour','Accuracy','Evade','HP','TP','STR','INT','WIS','AGI','CON','CHA'],item_rows,'items')
    page += '<h2 id="spells">All spells and skill progression</h2><p>Attack values are base power before the class attack multiplier, training and enemy defence. Healing adds class-specific attribute scaling. Training is capped at 10 and adds two power per rank. Radius-1 attacks use 80% power; radius-2 attacks use 60%, hit at most the listed targets and charge TP once. Chant values are native 0.48-second ticks; practical casting includes release/recovery time.</p>'
    page += table(['ID','Spell','Learn level','Class','TP','Chant ticks','Base power / heal','Targets'],spell_rows)
    page += '<h2 id="recovery">Recovery and existing characters</h2>'
    page += table(['Item','HP','TP'],[[i['name'],i['hp'],i['tp']] for i in recovery])
    page += '<p>Choose a class at the Wise Man. Use free rebuilding at a class skillmaster to refund invested attribute and training points while keeping learned spells. Skills from a different class remain owned but cannot be used. Newly ineligible worn gear moves to its owner’s bag during migration. Nothing is deleted. Future KCPD108 redemptions grant 40 Big Health Potions, 1,000 Gold and a Dagger; previous redemption records remain intact.</p><p>Validation covers 36 native class/level builds, real spells, healing, area costs, class selection, rebuilding, ownership migration and the actual Godot client. The accompanying validation report records completed checks. This is the first implemented balance pass; sustained farming and party performance should guide later tuning.</p></main><script>document.querySelector("#filter").addEventListener("input",e=>{const q=e.target.value.toLowerCase();document.querySelectorAll("#items tbody tr").forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q))})</script></html>'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(page)
    report.with_suffix('.json').write_text(json.dumps(dict(version=profile['version'],equipment=equipment,spells=profile['spells'],eggs=profile.get('eggs',{}),coverage=coverage['coverage'],benchmarks=model),indent=2)+'\n')
    return dict(equipment=len(equipment),items=len(profile['items']),spells=len(profile['spells']),report=str(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime',type=Path,required=True)
    parser.add_argument('--content',type=Path,default=ROOT/'client/content')
    parser.add_argument('--report',type=Path,default=ROOT/'outputs/balance-revamp/balance-guide.html')
    args = parser.parse_args()
    print(json.dumps(export(args.runtime,args.content,args.report)))
