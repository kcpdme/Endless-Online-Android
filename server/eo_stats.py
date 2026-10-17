"""Authoritative EO v28 stats/combat decoding, derived from pinned etheos builders.
Welcome and equipment use different INT/WIS orders; never infer totals from item text.
"""
from eo_session import Reader

ATTRIBUTES=('strength','intelligence','wisdom','agility','constitution','charisma')
DERIVED=('min_damage','max_damage','accuracy','evade','armor')

def update(session,values):
    session.stats.update(values)
    if session.state and session.state.get('self'):
        me=session.state['self']
        for source,target in [('hp','hp'),('tp','tp'),('max_hp','maxhp'),('max_tp','maxtp'),('level','level')]:
            if source in values:me[target]=values[source]

def sync_position_stats(session):
    if session.state and session.state.get('self'):
        me=session.state['self']
        session.stats.update({key:me[source] for key,source in [('hp','hp'),('tp','tp'),('max_hp','maxhp'),('max_tp','maxtp'),('level','level')]})

def apply_packet(session,f,a,p):
    r=Reader(p);values={};event=session.events[-1]
    if (f,a)==(5,3) and len(p)>45:
        if r.num(2)!=1:return
        r.take(8+7+24) # player2 + character4 + map2; map identity7; four PUB identities6 each
        name=r.text();title=r.text();guild=r.text();rank=r.text();clas=r.num();r.take(3);admin=r.num();level=r.num()
        values=dict(name=name,title=title,guild=guild,guild_rank=rank,class_id=clas,admin=admin,level=level,experience=r.num(4),usage=r.num(4),dead=False)
        for key in ('hp','max_hp','tp','max_tp','max_sp','stat_points','skill_points','karma',*DERIVED,'strength','wisdom','intelligence','agility','constitution','charisma'):values[key]=r.num(2)
    elif f==30 and a in (4,5):
        r.take(16)
        if a==5:r.take(3)
        r.take(1)
        for key in ('max_hp','max_tp',*ATTRIBUTES,*DERIVED):values[key]=r.num(2)
    elif (f,a)==(16,8):
        for key in ('stat_points',*ATTRIBUTES,'max_hp','max_tp','max_sp','max_weight',*DERIVED):values[key]=r.num(2)
        event.update(kind='stat_changed')
    elif (f,a)==(42,8):
        values=dict(hp=r.num(2),tp=r.num(2));event.update(kind='recover')
    elif (f,a)==(26,8) and p[:1]==b'\xff' and len(p)>=14 and p[1:2]!=b'\xff':
        r.take(1);index=r.num();dead=r.num()==2;direction=r.num();pid=r.num(2);damage=r.num(3);percent=r.num(3);r.take(2)
        event.update(kind='npc_attack',npc_index=index,player_id=pid,damage=damage,hp_percent=percent,dead=dead,direction=direction)
        if pid==session.player_id and len(r.rest())>=4:
            hp=r.num(2);tp=r.num(2)
            values=dict(hp=0 if dead else hp,tp=tp,dead=dead)
            event.update(kind='player_damage',npc_index=index,player_id=pid,damage=damage,hp=values['hp'],hp_percent=percent,dead=dead,direction=direction)
    elif (f,a)==(31,16) and len(p)==7 and r.num()==2:
        damage=r.num(2);hp=r.num(2);maxhp=r.num(2)
        values=dict(hp=hp,max_hp=maxhp,dead=hp==0)
        event.update(kind='player_damage',source='spike',player_id=session.player_id,damage=damage,hp=hp,dead=hp==0)
    elif (f,a)==(31,17) and len(p)==7:
        pid=r.num(2);percent=r.num();dead=bool(r.num());damage=r.num(3)
        event.update(kind='peer_damage',source='spike',player_id=pid,damage=damage,hp_percent=percent,dead=dead)
    elif (f,a)==(11,8):
        event.update(kind='peer_attack',player_id=r.num(2),direction=r.num())
    elif f==26 and a in (2,16) and len(p)>=22:
        # Kill payload18, recipient EXP4, then optional level-up totals11.
        r.take(18);values['experience']=r.num(4)
        if a==2 and len(r.rest())>=11:
            values['level']=r.num()
            for key in ('stat_points','skill_points','max_hp','max_tp','max_sp'):values[key]=r.num(2)
            event['level_up']=values['level']
    if values:update(session,values)
