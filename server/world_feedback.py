"""Native drains, PK hits, camera effects and ambient NPC speech."""
from eo_session import EOError, Reader
from eo_stats import update

class WorldFeedbackMixin:
    def apply_world_feedback(self,f,a,p):
        if not self.state:return
        r=Reader(p);event=None;values={};extra=[]
        if (f,a)==(31,31):
            if len(p)<6 or (len(p)-6)%5:raise EOError('Malformed HP drain')
            damage,hp,maximum=r.num(2),r.num(2),r.num(2)
            values=dict(hp=hp,max_hp=maximum)
            event=dict(kind='player_damage',source='drain',player_id=self.player_id,damage=damage,hp=hp,dead=False)
            while r.rest():extra.append(dict(kind='peer_damage',source='drain',player_id=r.num(2),hp_percent=r.num(),damage=r.num(2),dead=False))
        elif (f,a)==(31,16) and len(p)==7 and p[:1]==b'\x02': # encoded numeric 1
            r.num();damage,tp,maximum=r.num(2),r.num(2),r.num(2)
            values=dict(tp=tp,max_tp=maximum);event=dict(kind='mana_drain',damage=damage,tp=tp)
        elif f==23 and a in (3,17):
            if len(p)!=(12 if a==17 else 10):raise EOError('Malformed PK damage')
            attacker,victim,damage,direction,percent,dead=r.num(2),r.num(2),r.num(3),r.num(),r.num(),bool(r.num())
            attacker=attacker or self.player_id
            event=dict(kind='player_damage' if victim==self.player_id else 'peer_damage',source='pk',player_id=victim,attacker_id=attacker,damage=damage,direction=direction,hp_percent=percent,dead=dead)
            if a==17:
                event['spell_id']=r.num(2)
                if attacker==self.player_id:self.casting=None
            if victim==self.player_id and dead:values=dict(hp=0,dead=True)
            if victim==self.player_id and dead:self.pending_moves.clear();self.position_seq=self.last_input_seq
        elif (f,a)==(31,10):
            if len(p)!=2:raise EOError('Malformed map effect')
            effect,strength=r.num(),r.num()
            if effect==1:event=dict(kind='quake',strength=min(8,strength))
        elif (f,a)==(26,8) and p[:2]==b'\xff\xff':
            r.take(2);index,length=r.num(),r.num();message=r.take(length).decode('latin1')
            if r.rest():raise EOError('Malformed NPC speech')
            npc=next((n for n in self.state['npcs'] if n['index']==index),None)
            if npc:event=dict(kind='npc_speech',npc_index=index,npc_id=npc['id'],message=message)
        if event:
            if values:update(self,values)
            self.events[-1].update(event);self.events.extend(extra);self.dirty=True
