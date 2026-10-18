"""Original ESF skills, chant/target packets and native skill-master transactions.

The gateway schedules the release without sleeping: NPC movement, damage and walk
acknowledgements continue to be pumped throughout even the longest chant.
"""
from functools import lru_cache
import time
from eo_session import EOError, Reader, number
from eo_stats import update
from services import runtime_path

@lru_cache(maxsize=1)
def spell_definitions():
    r=Reader((runtime_path()/'data/pub/dsl001.esf').read_bytes())
    if r.take(3)!=b'ESF':raise EOError('Invalid native spell definitions')
    r.take(4);count=r.num(2);r.num();result={}
    for ident in range(1,count+1):
        n,s=r.num(),r.num();name=r.take(n).decode('latin1');shout=r.take(s).decode('latin1');f=r.take(51)
        if name.lower()=='eof':break
        result[ident]=dict(id=ident,name=name,shout=shout,tp=Reader(f[4:6]).num(2),cast_time=Reader(f[8:9]).num(),type=Reader(f[11:12]).num(),restrict=Reader(f[17:18]).num(),target=Reader(f[18:19]).num())
    return result

@lru_cache(maxsize=1)
def npc_types():
    r=Reader((runtime_path()/'data/pub/dtn001.enf').read_bytes());r.take(7);count=r.num(2);r.num();result={}
    for ident in range(1,count+1):
        r.take(r.num());f=r.take(39);result[ident]=Reader(f[7:9]).num(2)
    return result

ICE_BLAST_IDS = frozenset((14, 21))
AREA_FAMILY = 231

class SkillsMixin:
    def init_skills(self):
        self.casting=None;self.skillmaster=None

    def cast_spell(self,spell_id,target_kind,target_id=0):
        self._mobile_action();spell_id=int(spell_id);target_id=int(target_id)
        # Native SpellCooldownTime owns recovery; do not add another preparation lock.
        if self.casting:raise EOError('Wait for your skill to finish')
        if not any(s['id']==spell_id for s in getattr(self,'spells',[])):raise EOError('You have not learned this skill')
        spell=spell_definitions().get(spell_id)
        if not spell or spell['type'] not in (0,1):raise EOError('This native skill has no supported effect')
        if self.state['self'].get('tp',0)<spell['tp']:raise EOError('Not enough TP')
        target=self.state['self']
        if spell_id in ICE_BLAST_IDS:
            if target_kind not in ('area','self'):raise EOError('Ice Blast casts around you; no opponent selection is needed')
            target_kind='area';target_id=0
        elif spell['target']==1 and spell['restrict']==1:
            if target_kind!='self':raise EOError('This skill targets yourself')
            target_id=self.player_id
        elif spell['target']==0 and target_kind=='npc' and spell['restrict']!=1:
            target=next((n for n in self.state['npcs'] if n['index']==target_id),None)
            if not target or npc_types().get(target['id']) not in (1,2):raise EOError('Select a living monster')
        elif spell['target']==0 and target_kind=='player' and spell['restrict']==1:
            target=next((c for c in [self.state['self']]+self.state['characters'] if c['player_id']==target_id),None)
            if not target:raise EOError('That player is no longer nearby')
        else:raise EOError('This skill needs a different target; group skills require party support')
        me=self.state['self']
        if abs(target['x']-me['x'])+abs(target['y']-me['y'])>11:raise EOError('The target is too far away')
        if target_kind=='self' and spell['type']==0 and me.get('hp',0)>=me.get('maxhp',1):raise EOError('Your health is already full. Nothing was cast.')
        self.timestamp+=1
        duration=spell['cast_time']*.48
        self.casting=dict(spell_id=spell_id,target_kind=target_kind,target_id=target_id,seconds=duration,
                          release_at=time.monotonic()+duration,timeout_at=time.monotonic()+duration+5,
                          timestamp=self.timestamp,released=False,target_x=target['x'],target_y=target['y'],target_npc_id=target.get('id',0))
        self.send(12,1,number(spell_id,2)+number(self.timestamp,3))
        self.events.append(dict(kind='spell_chant',player_id=self.player_id,spell_id=spell_id,seconds=duration))
        self.dirty=True
        return {'sent':True,'seconds':duration}

    def cancel_spell(self):
        cast=getattr(self,'casting',None)
        if cast:
            # Native Target_Other's invalid target branch calls CancelSpell.
            self.send(12,31,number(0,1)+number(0,1)+number(0,2)+number(cast['spell_id'],2)+number(0,2)+number(self.timestamp,3))
            self.events.append(dict(kind='spell_cancelled',player_id=self.player_id))
            self.casting=None;self.dirty=True
        return {'sent':True}

    def poll_spells(self):
        cast=getattr(self,'casting',None)
        if not cast:return
        now=time.monotonic()
        if not cast['released'] and now>=cast['release_at']:
            if cast['target_kind']=='npc':
                target=next((n for n in self.state['npcs'] if n['index']==cast['target_id']),None)
                if not target:
                    self.cancel_spell();self.events.append(dict(kind='spell_failed',message='The target is no longer here.'));return
                if abs(target['x']-self.state['self']['x'])+abs(target['y']-self.state['self']['y'])>11:
                    self.cancel_spell();self.events.append(dict(kind='spell_failed',message='The target is out of range.'));return
            if self.state['self'].get('tp',0)<spell_definitions()[cast['spell_id']]['tp']:
                self.cancel_spell();self.events.append(dict(kind='spell_failed',message='Not enough TP.'));return
            # Timestamp units are 10 ms, independent of transport/polling jitter.
            ticks=spell_definitions()[cast['spell_id']]['cast_time']*48
            release_timestamp=cast['timestamp']+ticks
            self.timestamp=max(self.timestamp,release_timestamp)
            if cast['target_kind'] in ('self','area'):self.send(12,30,number(1,1)+number(cast['spell_id'],2)+number(release_timestamp,3))
            else:self.send(12,31,number(2 if cast['target_kind']=='npc' else 1,1)+number(1,1)+number(1,2)+number(cast['spell_id'],2)+number(cast['target_id'],2)+number(release_timestamp,3))
            cast['released']=True
        elif now>=cast['timeout_at']:
            self.cancel_spell()
            self.events.append(dict(kind='spell_failed',message='The server did not confirm this skill. Try again.'))

    def skillmaster_open(self,npc_index):
        self._standing();npc_index=int(npc_index)
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc or npc_types().get(npc['id'])!=14:raise EOError('Select a nearby skill master')
        context=dict(npc_index=npc_index,map_id=self.state['map_id'],x=npc['x'],y=npc['y'])
        self._near_service(context);self.send(16,13,number(npc_index,2));r=Reader(self._wait_service(16,{13}))
        context.update(id=r.num(2),name=r.text(),offers=[])
        while len(r.rest())>=28:
            offer=dict(id=r.num(2),level=r.num(),class_id=r.num(),cost=r.num(4),prerequisites=[r.num(2) for _ in range(4)])
            for key in ('strength','wisdom','intelligence','agility','constitution','charisma'):offer[key]=r.num(2)
            context['offers'].append(offer)
        self.skillmaster=context;return self.snapshot()

    def skill_change(self,action,spell_id):
        self._standing();spell_id=int(spell_id)
        known=any(s['id']==spell_id for s in getattr(self,'spells',[]))
        if action=='level':
            if known and next(s['level'] for s in self.spells if s['id']==spell_id)>=100:raise EOError('This skill is already at the native maximum level')
            if not known or self.stats.get('skill_points',0)<=0:raise EOError('No available skill point for this skill')
            self.send(16,7,number(2,1)+number(spell_id,2));self._wait_service(16,{2})
        else:
            self._near_service(getattr(self,'skillmaster',None))
            if action=='learn':
                if known:raise EOError('You already know this skill')
                if not any(o['id']==spell_id for o in self.skillmaster['offers']):raise EOError('This master does not teach that skill')
            elif action=='forget':
                if not known:raise EOError('You do not know this skill')
            else:raise EOError('Invalid skill action')
            self.send(16,9 if action=='learn' else 4,number(self.skillmaster['id'],4)+number(spell_id,2))
            result=self._wait_service(16,{9 if action=='learn' else 4,3})
            if getattr(self,'skill_error',False):self.skill_error=False;raise EOError('Check this skill’s class, level, attributes, prerequisites and Gold requirements')
        return self.snapshot()

    def apply_skill_packet(self,f,a,p):
        r=Reader(p);event=self.events[-1];values={}
        if (f,a)==(AREA_FAMILY,3):
            pid=r.num(2);ident=r.num(2);x=r.num();y=r.num();tp=r.num(2);hits=r.num()
            if ident not in ICE_BLAST_IDS or hits>5 or r.rest():raise EOError('Invalid native area spell acknowledgement')
            event.update(kind='spell_area',player_id=pid,spell_id=ident,x=x,y=y,targets=hits,width=5,height=5)
            if pid==self.player_id:
                values['tp']=tp;self.casting=None;event['own_cast']=True
        elif (f,a)==(12,1):
            pid=r.num(2);ident=r.num(2);spell=spell_definitions().get(ident,{})
            event.update(kind='spell_chant',player_id=pid,spell_id=ident,seconds=spell.get('cast_time',1)*.48)
        elif f==44 and a in (3,2,16):
            ident=r.num(2);pid=r.num(2);direction=r.num();index=r.num(2)
            pending=getattr(self,'casting',None) or {}
            npc=next((n for n in self.state['npcs'] if n['index']==index),{})
            if not npc and pending.get('target_id')==index:npc=dict(x=pending.get('target_x',0),y=pending.get('target_y',0),id=pending.get('target_npc_id',0))
            event.update(kind='npc_damage' if a==3 else 'npc_killed',player_id=pid,npc_index=index,spell_id=ident,npc_id=npc.get('id',0),x=npc.get('x',0),y=npc.get('y',0))
            if a==3:event.update(damage=r.num(3),hp_percent=r.num(2))
            else:
                drop=dict(uid=r.num(2),id=r.num(2),x=r.num(),y=r.num(),amount=r.num(4));event.update(drop=drop,damage=r.num(3),x=drop['x'],y=drop['y'])
            tp=r.num(2);cast=getattr(self,'casting',None)
            # Kill PID is the loot winner, not necessarily the caster. A matching
            # private pending cast identifies our TP; an observer never adopts it.
            own=(a==3 and pid==self.player_id) or (a!=3 and cast and cast['released'] and cast['spell_id']==ident and cast['target_kind']=='npc' and cast['target_id']==index)
            if own:values['tp']=tp;self.casting=None;event['own_cast']=True
            if a!=3 and len(r.rest())>=4:
                values['experience']=r.num(4)
                if 'experience' in self.stats:event['exp_gain']=max(0,values['experience']-self.stats['experience'])
                if a==2 and len(r.rest())>=11:
                    values['level']=r.num();event['level_up']=values['level']
                    for key in ('stat_points','skill_points','max_hp','max_tp','max_sp'):values[key]=r.num(2)
        elif (f,a)==(12,30):
            pid=r.num(2);ident=r.num(2);gain=r.num(4);percent=r.num()
            event.update(kind='spell_heal',player_id=pid,target_id=pid,spell_id=ident,hp_gain=gain,hp_percent=percent)
            if pid==self.player_id and len(r.rest())>=4:
                values.update(hp=r.num(2),tp=r.num(2));event['hp_gain']=max(0,values['hp']-self.state['self'].get('hp',values['hp']));self.casting=None
        elif (f,a)==(12,31):
            victim=r.num(2);pid=r.num(2);r.num();ident=r.num(2);gain=r.num(4);percent=r.num()
            event.update(kind='spell_heal',player_id=pid,target_id=victim,spell_id=ident,hp_gain=gain,hp_percent=percent)
            if victim==self.player_id and len(r.rest())>=2:values['hp']=r.num(2)
            if pid==self.player_id:self.casting=None
        elif f==16 and a in (9,4,2):
            if not hasattr(self,'spells'):self.spells=[]
            old_level=next((s['level'] for s in self.spells if s['id']==Reader(p[2:4]).num(2)),0) if a==2 else 0
            if a==2:
                values['skill_points']=r.num(2);ident=r.num(2);level=r.num(2)
            else:ident=r.num(2);level=0
            self.spells=[s for s in self.spells if s['id']!=ident]
            if a!=4:self.spells.append(dict(id=ident,level=level))
            if a==9:self._set_amount(1,r.num(4))
            event.update(kind='skill_changed',spell_id=ident,action='trained' if a==2 else 'learned' if a==9 else 'forgotten',level=level,old_level=old_level)
        elif (f,a)==(16,3):self.skill_error=True
        else:return
        if values:update(self,values)
        self.dirty=True
