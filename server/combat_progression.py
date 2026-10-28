"""Public inputs shared by native config, item details and balance probes."""
TP_RECOVERY = {3: .008, 7: .004, 2: .003, 8: .003}
RECOVERY_SECONDS = 2
# Red starter Bow keeps its original name/art. Rapid bows trade impact for cadence.
BOWS = {
    297: dict(range_tiles=3, attack_speed=1.0, shot_power=1.0),
    511: dict(range_tiles=3, attack_speed=1.0, shot_power=1.0),
    543: dict(range_tiles=4, attack_speed=1.25, shot_power=.95),
    512: dict(range_tiles=4, attack_speed=1.25, shot_power=.95),
    316: dict(range_tiles=5, attack_speed=1.5, shot_power=.85),
    457: dict(range_tiles=7, attack_speed=2.0, shot_power=.70),
    496: dict(range_tiles=8, attack_speed=2.0, shot_power=.70),
}
ARROWS = {423: 0, 424: 2, 425: 2}
SHIELDS = {52: 4, 53: 5, 55: 4, 56: 3, 57: 6, 209: 5,
           378: 12, 379: 14, 380: 13, 416: 16, 417: 15, 432: 3, 453: 4}

def item_traits(ident):
    result=dict(BOWS.get(ident,{}))
    if ident in ARROWS:result['range_bonus']=ARROWS[ident]
    if ident in SHIELDS:result['warrior_shield_multiplier']=2
    return result

def equipped_combat(session):
    from balance_rules import profile
    items=profile().get('items',{});weapon=items.get(str(session.equipment.get('weapon',0)),{});arrows=items.get(str(session.equipment.get('offhand',0)),{})
    valid=session.stats.get('class_id')==5 and weapon.get('subtype')==1 and arrows.get('subtype')==2 and all(i.get('level_requirement',0)<=session.stats.get('level',0) for i in (weapon,arrows))
    speed=float(weapon.get('attack_speed',1)) if valid else 1.0
    return dict(attack_seconds=round(.52/speed,4),range_tiles=int(weapon.get('range_tiles',3))+int(arrows.get('range_bonus',0)) if valid else 1,shot_power=float(weapon.get('shot_power',1)) if valid else 1.0)
