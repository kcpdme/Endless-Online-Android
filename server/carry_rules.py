"""Exact carried weight and early UI errors; native handlers enforce every rule again."""
from native_settings import settings
from services import item_definitions
from eo_session import EOError

def enabled():
    return str(settings({'CarryCapacityRules':'no'})['CarryCapacityRules']).lower() in ('yes','true','1')

def actual_weight(session):
    items=item_definitions()
    return sum(items.get(int(i['id']),{}).get('weight',0)*max(0,int(i['amount'])) for i in session.inventory)+sum(items.get(int(i),{}).get('weight',0) for i in session.equipment.values())

def state(session):
    capacity=int(session.stats.get('max_weight',getattr(session,'max_weight',70)))
    weight=actual_weight(session) if enabled() else int(getattr(session,'weight',0))
    return dict(weight=weight,max_weight=capacity,overweight=enabled() and weight>capacity,carry_rules=enabled())

def check(session):
    if enabled():
        w=state(session)
        if w['overweight']:raise EOError(f"Overweight ({w['weight']}/{w['max_weight']}): drop items or deposit them in a locker before walking or trading.")

def trade_fits(session):
    if not enabled() or not session.trade:return
    items=item_definitions();offers=session.trade.get('offers',{})
    outgoing=offers.get(str(session.player_id),[]);incoming=offers.get(str(session.trade['player_id']),[])
    weight=actual_weight(session)+sum(items.get(i['id'],{}).get('weight',0)*i['amount'] for i in incoming)-sum(items.get(i['id'],{}).get('weight',0)*i['amount'] for i in outgoing)
    if weight>state(session)['max_weight']:raise EOError('This trade would exceed your carrying capacity. Remove items or cancel.')
