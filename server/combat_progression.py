"""Public inputs shared by native config, item details and balance probes."""
TP_RECOVERY = {3: .008, 7: .004, 2: .003, 8: .003}
RECOVERY_SECONDS = 2
# Red starter Bow keeps its original name/art. Rapid bows trade impact for cadence.
BOWS = {
    297: dict(range_tiles=3, attack_speed=1.0, shot_power=1.0),
    511: dict(range_tiles=3, attack_speed=1.0, shot_power=1.0),
    543: dict(range_tiles=4, attack_speed=1.1, shot_power=.95),
    512: dict(range_tiles=4, attack_speed=1.1, shot_power=.95),
    316: dict(range_tiles=5, attack_speed=1.2, shot_power=.85),
    457: dict(range_tiles=7, attack_speed=1.5, close_attack_speed=2.0, close_range=2, shot_power=.70),
    496: dict(range_tiles=8, attack_speed=1.5, close_attack_speed=2.0, close_range=2, shot_power=.70),
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
    return dict(attack_seconds=round(.52/speed,4),close_attack_seconds=round(.52/float(weapon.get('close_attack_speed',speed)),4) if valid else .52,close_range=int(weapon.get('close_range',0)) if valid else 0,range_tiles=int(weapon.get('range_tiles',3))+int(arrows.get('range_bonus',0)) if valid else 1,shot_power=float(weapon.get('shot_power',1)) if valid else 1.0)

# Native queue enforces this cadence; metadata only drives prediction/rendering.
# Weak entries disappear with disconnected sessions and never expose account data.
from weakref import WeakValueDictionary
_CONNECTED = WeakValueDictionary()

def mobility_enabled():
    from native_settings import settings
    return str(settings({'ClassMobility':'no'})['ClassMobility']).lower() in ('yes','true','1')

def movement_seconds(session):
    return round(.42/float(getattr(session,'running_multiplier',1.0)),4) if getattr(session,'running_enabled',False) else .42

def publish_movement(session, data):
    _CONNECTED[session.player_id] = session
    data['player']['combat']['move_seconds'] = movement_seconds(session)
    from balance_rules import profile
    data['player']['combat'].update(running=bool(getattr(session,'running_enabled',False)),running_supported=bool(profile().get('running_rules')),run_tp_rate=.015)
    for row in data['players']:
        peer = _CONNECTED.get(row['player_id'])
        row['move_seconds'] = movement_seconds(peer) if peer and peer.state and (peer.state.get('self') or {}).get('name') == row.get('name') else row.get('move_seconds',.42)
