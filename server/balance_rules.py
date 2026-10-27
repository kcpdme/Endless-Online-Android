"""Read-only public balance metadata and early client validation.

Native handlers repeat the class and level checks. This layer provides useful
errors and live catalog values; it never grants stats, spells or equipment.
"""
from functools import lru_cache
import json
from services import runtime_path
from native_settings import settings
from eo_session import EOError

@lru_cache(maxsize=1)
def profile():
    if str(settings({'BalanceRevamp':'no'})['BalanceRevamp']).lower() not in ('yes','true','1'):return {}
    path=runtime_path()/'data/balance-profile.json'
    if not path.is_file():raise EOError('The world balance profile is unavailable')
    return json.loads(path.read_text())

def check_spell(session, ident):
    rules=profile()
    if not rules or int(session.stats.get('admin',0))>0:return
    spell=rules['spells'].get(str(ident))
    if not spell or int(session.stats.get('level',0))<spell['level_requirement']:raise EOError('This skill requires a higher level')
    classes=spell.get('allowed_classes',[]);clas=int(session.stats.get('class_id',0))
    base=rules['classes'].get(str(clas),{}).get('base',0)
    if classes and clas not in classes and base not in classes:raise EOError('This skill belongs to another class')

def area_spell(ident):
    rules=profile()
    return bool(rules.get('spells',{}).get(str(ident),{}).get('area_radius',0)) if rules else ident in (14,21)


def check_equipment(session, ident):
    rules=profile()
    if not rules.get('class_identity'):return
    item=rules['items'].get(str(ident))
    if not item:raise EOError('Unknown equipment')
    clas=int(session.stats.get('class_id',0));base=rules['classes'].get(str(clas),{}).get('base',0)
    allowed=item.get('allowed_classes',[])
    if allowed and clas not in allowed and base not in allowed:raise EOError('This equipment belongs to another class')
    if int(session.stats.get('level',0))<item['level_requirement']:raise EOError('This equipment requires a higher level')


def check_hatch(session, ident):
    rules=profile();egg=rules.get('eggs',{}).get(str(ident))
    if not egg:return
    if int(session.stats.get('class_id',0))!=7:raise EOError('Only Summoners can hatch spirit eggs. The egg is kept.')
    if int(session.stats.get('level',0))<egg['level']:raise EOError('Reach level %d before hatching this egg. The egg is kept.'%egg['level'])
    if any(s['id']==egg['spell_id'] for s in session.spells):raise EOError('You already know this spirit summon. The egg is kept.')

def check_spell_loadout(session, ident):
    spell=profile().get('spells',{}).get(str(ident),{})
    if not spell.get('requires_bow') or int(session.stats.get('admin',0))>0:return
    items=profile()['items'];bow=items.get(str(session.equipment.get('weapon',0)),{});arrows=items.get(str(session.equipment.get('offhand',0)),{})
    if bow.get('type')!=10 or bow.get('subtype')!=1 or arrows.get('type')!=11 or arrows.get('subtype')!=2:raise EOError('Equip a bow and arrows before using an Archer shot.')
