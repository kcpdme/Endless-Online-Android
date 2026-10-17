#!/usr/bin/env python3
"""Event-driven EO state. Standard Walk_Reply confirms a step; Refresh corrects rejected steps.

The world server remains authoritative. A move receipt only acknowledges transport,
never invents acceptance. Old blocking operations remain available to v0.6 clients.
"""
from collections import deque
from copy import deepcopy
import socket
import time
from eo_session import Session, Reader, EOError, number


from economy import EconomyMixin
from services import ServicesMixin
from consumables import ConsumablesMixin
from skills import SkillsMixin
from rewards import RewardsMixin


class LiveSession(RewardsMixin, SkillsMixin, ConsumablesMixin, ServicesMixin, EconomyMixin, Session):
    def __init__(self,*args):
        self.init_services();self.init_skills()
        self.pending_moves=deque();self.position_seq=0;self.last_input_seq=0
        self.pending_pickups={};self.drop_guards={}
        self.metrics=dict(moves=0,walk_acks=0,refreshes=0,corrections=0,collects=0,pickups=0)
        self.dirty=False;self.position_update=False;self.correction=False;self.expect_walk_refresh=False;self.sent_state=None
        super().__init__(*args)
        self.sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)

    def move(self,direction,seq,map_id,x,y,open_door=False):
        direction=int(direction);seq=int(seq);x=int(x);y=int(y)
        if direction not in range(4) or not self.state or not self.state.get('self'):raise EOError('Enter the world before moving')
        if self.warp:raise EOError('Wait for the map transition')
        if self.trade:raise EOError('Close the trade before moving')
        if self.stats.get('dead'):return {'sent':False,'input_seq':seq,'dead':True}
        if seq<=self.last_input_seq:raise EOError('Movement sequence is stale')
        if len(self.pending_moves)>=4:raise EOError('Wait for outstanding movement')
        if int(map_id)!=self.state['map_id']:raise EOError('Movement map changed')
        if not(0<=x<=251 and 0<=y<=251):raise EOError('Movement destination is outside protocol bounds')
        # Bound the queue; the native server enforces its 400 ms cadence. Network jitter
        # may deliver valid, evenly spaced client inputs in a burst. Never sleep here.
        self.skillmaster=None
        now=time.monotonic();self.shop=None;self.bank=None;self.locker=None
        if open_door:self.send(34,13,number(x,1)+number(y,1))
        # Match original etheos: NPC occupancy is checked by the client before
        # prediction. Rechecking a moving NPC here rejects an already-predicted
        # step using a newer world state, creating an extra rollback absent in EO.
        move=dict(seq=seq,x=x,y=y,direction=direction)
        self.timestamp+=42
        self.send(6,8,number(direction,1)+number(self.timestamp,3)+number(x,1)+number(y,1))
        self.pending_moves.append(move)
        self.last_walk=now;self.last_input_seq=seq;self.metrics['moves']+=1
        return {'sent':True,'input_seq':seq}

    def collect(self,uid):
        self._standing();uid=int(uid)
        if uid in self.pending_pickups:return {'sent':False,'pending':True,'uid':uid}
        if self.pending_pickups:raise EOError('Wait for the current pickup acknowledgement')
        item=next((i for i in self.state['items'] if i['uid']==uid),None)
        if not item:raise EOError('This drop is no longer on the ground')
        me=self.state['self']
        if abs(item['x']-me['x'])+abs(item['y']-me['y'])>2:raise EOError('Move closer to the drop')
        owner,until=self.drop_guards.get(uid,(0,0))
        if owner and owner!=self.player_id and until>time.monotonic():
            raise EOError('This drop is reserved for another player for %d seconds' % (int(until-time.monotonic())+1))
        self.send(14,27,number(uid,2));self.pending_pickups[uid]=time.monotonic()+2
        self.metrics['collects']+=1
        return {'sent':True,'uid':uid}

    def poll_actions(self):
        self.poll_spells()
        queue=self.potion_queue()
        expired=[e for e in queue if time.monotonic()>=e['until']]
        if expired:
            self.set_potion_queue([e for e in queue if e not in expired]);self.dirty=True
            for e in expired:self.events.append(dict(kind='item_use_failed',item_id=e['id'],message='Potion was not acknowledged. Check your HP/TP and bag.'))
        now=time.monotonic()
        for uid,until in list(self.pending_pickups.items()):
            if until<=now:
                del self.pending_pickups[uid]
                self.events.append(dict(kind='pickup_failed',uid=uid,message='Cannot pick up: check bag weight or wait for drop protection to expire.'))
                self.dirty=True

    def face(self,direction):
        direction=int(direction)
        if direction not in range(4):raise EOError('Invalid facing direction')
        if not self.state or self.warp or self.stats.get('dead') or self.trade or getattr(self,'casting',None):return {'sent':False}
        self.send(7,8,number(direction,1));self.state['self']['direction']=direction
        return {'sent':True,'direction':direction}

    def strike(self,direction):
        direction=int(direction)
        if direction not in range(4) or not self.state:raise EOError('Enter the world before attacking')
        if self.trade:raise EOError('Close the trade before attacking')
        if self.warp or self.stats.get('dead'):return {'sent':False,'dead':True}
        # Native TCP/action queue preserves Walk -> Attack order; a delayed walk
        # acknowledgement must not add another round trip before an attack.
        # Original Attack_Use accepts 48+ timestamp ticks; >=60 forces old facing.
        # Send the desired direction directly, avoiding Face's additional 120 ms queue slot.
        self.cancel_spell()
        self.timestamp+=50
        self.send(11,10,number(direction,1)+number(self.timestamp,3))
        self.state['self']['direction']=direction
        return {'sent':True,'attack_seconds':0.52}

    def spend_stat(self,stat_id):
        stat_id=int(stat_id)
        if stat_id not in range(1,7) or self.stats.get('stat_points',0)<=0:raise EOError('No available stat point')
        if self.pending_moves or self.warp or self.stats.get('dead'):raise EOError('Wait until you are standing safely')
        self.send(16,7,number(1,1)+number(stat_id,2));self.wait(16,8,timeout=3)
        return self.snapshot()

    def _resolve(self,correction=False,consume=True):
        if consume and self.pending_moves:
            move=self.pending_moves.popleft();self.position_seq=move['seq']
            if not correction:
                # Walk_Reply confirms the native one-tile direction, never client-supplied coordinates.
                me=self.state['self'];dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][move['direction']]
                me.update(x=me['x']+dx,y=me['y']+dy,direction=move['direction'])
                self.expect_walk_refresh=(me['x'],me['y'])!=(move['x'],move['y'])
                # Native EO relies on clients to discard entities that leave the view diamond.
                # Match the pinned world's SeeDistance=11; stale NPCs must not become invisible walls.
                for collection in ('characters','npcs','items'):
                    self.state[collection]=[row for row in self.state[collection] if abs(row['x']-me['x'])+abs(row['y']-me['y'])<=11]
        self.position_update=True;self.correction=correction;self.dirty=True

    def control_packet(self,f,a,p):
        was_dead=self.stats.get('dead',False)
        handled=super().control_packet(f,a,p)
        if handled and (f,a)==(19,5):
            if self.pending_moves:self.position_seq=self.pending_moves[-1]['seq']
            self.casting=None;self.skillmaster=None
            self.shop=None;self.bank=None;self.locker=None;self.trade=None;self.trade_request=None;self.pending_pickups.clear();self.drop_guards.clear()
            self.pending_moves.clear();self.expect_walk_refresh=False;self.position_update=True;self.correction=True;self.dirty=True
            if was_dead:self.events[-1]['reason']='death_respawn'
            self.stats['dead']=False
            from eo_stats import sync_position_stats
            sync_position_stats(self)
        return handled

    @staticmethod
    def _character(r):
        name=r.text();pid=r.num(2);mid=r.num(2);x=r.num(2);y=r.num(2);direction=r.num();r.take(1)
        r.take(3);level=r.num();gender=r.num();hair=r.num();color=r.num();race=r.num()
        maxhp=r.num(2);hp=r.num(2);maxtp=r.num(2);tp=r.num(2);equipment=[r.num(2) for _ in range(9)]
        sitting=r.num();r.num();r.take(1)
        return dict(name=name,player_id=pid,map_id=mid,x=x,y=y,direction=direction,level=level,gender=gender,
                    hairstyle=hair,haircolor=color,race=race,maxhp=maxhp,hp=hp,maxtp=maxtp,tp=tp,equipment_graphics=equipment,sitting=sitting)

    def _upsert(self,collection,key,row):
        rows=self.state[collection]
        old=next((entry for entry in rows if entry[key]==row[key]),None)
        if old:old.update(row)
        else:rows.append(row)
        self.dirty=True

    def apply_event(self,f,a,p):
        super().apply_event(f,a,p)
        self.apply_service_packet(f,a,p)
        self.apply_item_packet(f,a,p)
        self.apply_reward_packet(f,a,p)
        if self.state:self.apply_skill_packet(f,a,p)
        if not self.state:return
        event=self.events[-1]
        if event.get('kind') in ('npc_damage','npc_killed'):
            npc=next((n for n in self.state['npcs'] if n['index']==event['npc_index']),{})
            if npc:event.update(npc_id=npc['id'],x=npc['x'],y=npc['y'],npc_direction=npc.get('direction',0))
        r=Reader(p)
        if (f,a)==(25,3):
            old_position=(self.state['self']['x'],self.state['self']['y']) if self.state.get('self') else None
            state=self.parse_snapshot(r)
            changed=old_position!=(state['self']['x'],state['self']['y'])
            correction=bool(self.pending_moves) or self.expect_walk_refresh or changed
            self.metrics['refreshes']+=1
            if correction:self.metrics['corrections']+=1
            for key in ('inventory','spells','character_id','player_id','online'):
                if key in self.state:state[key]=self.state[key]
            self.state=state
            # A successful step with mismatching client coordinates sends Walk_Reply
            # followed immediately by Refresh. That second packet must not ack another input.
            consume=not self.expect_walk_refresh;self.expect_walk_refresh=False
            self._resolve(correction=correction,consume=consume)
        elif (f,a)==(6,3):
            # The real server sends this only after Map::Walk succeeds (new ground items follow).
            self.metrics['walk_acks']+=1
            self._resolve()
            if p[:2]==b'\xff\xff':
                r.take(2)
                while len(r.rest())>=9:
                    self._upsert('items','uid',dict(uid=r.num(2),id=r.num(2),x=r.num(),y=r.num(),amount=r.num(3)))
        elif (f,a)==(6,8):
            pid=r.num(2);direction=r.num();x=r.num();y=r.num()
            row=next((c for c in self.state['characters'] if c['player_id']==pid),None)
            if row:row.update(x=x,y=y,direction=direction);self.dirty=True
        elif (f,a)==(22,5) and p[:1]==b'\xff':
            r.take(1);row=self._character(r)
            if row['player_id']!=self.player_id:self._upsert('characters','player_id',row)
        elif (f,a)==(23,4):
            pid=r.num(2);self.state['characters']=[c for c in self.state['characters'] if c['player_id']!=pid];self.dirty=True
        elif (f,a)==(23,5):
            # Avatar_Agree uses BAHWS, unlike snapshot B000A0HSW. Observers
            # must update equipment immediately after another player changes it.
            pid=r.num(2);slot=r.num();r.num()
            row=next((c for c in self.state['characters'] if c['player_id']==pid),None)
            if row:
                if slot==1 and len(r.rest())>=10:
                    graphics=list(row.get('equipment_graphics',[0]*9))
                    for index in (0,4,6,8,7):graphics[index]=r.num(2)
                    row['equipment_graphics']=graphics
                elif slot==2 and len(r.rest())>=2:row.update(hairstyle=r.num(),haircolor=r.num())
                elif slot==3 and r.rest():row['haircolor']=r.num()
                self.dirty=True
        elif (f,a)==(11,8):
            pid=r.num(2);direction=r.num()
            row=next((c for c in self.state['characters'] if c['player_id']==pid),None)
            if row:row['direction']=direction
            self.dirty=True
        elif (f,a)==(29,3):
            count=r.num();r.take(1)
            for _ in range(count):self._upsert('characters','player_id',self._character(r))
            while len(r.rest())>=6 and r.rest()[0]!=255:
                self._upsert('npcs','index',dict(index=r.num(),id=r.num(2),x=r.num(),y=r.num(),direction=r.num()))
        elif (f,a)==(26,8):
            while len(r.rest())>=4 and r.rest()[0]!=255:
                index=r.num();x=r.num();y=r.num();direction=r.num()
                npc=next((n for n in self.state['npcs'] if n['index']==index),None)
                if x>=252 or y>=252:self.state['npcs']=[n for n in self.state['npcs'] if n['index']!=index]
                elif npc:npc.update(x=x,y=y,direction=direction)
                self.dirty=True
            if self.events[-1].get('kind') in ('player_damage','npc_attack'):
                self.dirty=True
                if self.events[-1].get('kind')=='player_damage' and self.events[-1]['dead']:
                    self.position_seq=self.last_input_seq;self.pending_moves.clear()
        elif (f,a)==(26,25):
            # Original NPC_Junk carries an ENF type, not a spawn index.
            ident=r.num(2)
            removed=[n['index'] for n in self.state['npcs'] if n['id']==ident]
            self.state['npcs']=[n for n in self.state['npcs'] if n['id']!=ident]
            self.events.append(dict(kind='npc_despawn',npc_id=ident,indexes=removed))
            cast=getattr(self,'casting',None)
            if cast and cast['target_kind']=='npc' and cast['target_id'] in removed:self.cancel_spell()
            self.dirty=True
        elif (f,a)==(26,16) and len(p)==5:
            r.take(3);index=r.num(2);self.state['npcs']=[n for n in self.state['npcs'] if n['index']!=index];self.dirty=True
        elif f in (26,44) and a in (2,16) and self.events[-1].get('kind')=='npc_killed':
            event=self.events[-1];self.state['npcs']=[n for n in self.state['npcs'] if n['index']!=event['npc_index']]
            drop=event['drop']
            if drop['uid'] and drop['amount']:
                self._upsert('items','uid',dict(drop))
                self.drop_guards[drop['uid']]=(event['player_id'],time.monotonic()+30)
            self.dirty=True
            cast=getattr(self,'casting',None)
            if cast and cast['target_kind']=='npc' and cast['target_id']==event['npc_index']:self.cancel_spell()
        elif (f,a) in ((31,16),(31,17)) and self.events[-1].get('kind') in ('player_damage','peer_damage'):
            self.dirty=True
            if self.events[-1].get('dead') and self.events[-1]['kind']=='player_damage':
                self.position_seq=self.last_input_seq;self.pending_moves.clear()
        elif (f,a)==(14,7):
            item_id=r.num(2);uid=r.num(2);amount=r.num(3)
            self._upsert('items','uid',dict(uid=uid,id=item_id,amount=amount,x=r.num(),y=r.num()))
        elif (f,a)==(14,4):
            uid=r.num(2);self.state['items']=[i for i in self.state['items'] if i['uid']!=uid];self.dirty=True
        elif (f,a)==(14,24):
            item_id=r.num(2);amount=r.num(3);r.num(4);uid=r.num(2);x=r.num();y=r.num()
            self._upsert('items','uid',dict(uid=uid,id=item_id,amount=amount,x=x,y=y))
            self._weight(r)
        elif (f,a)==(14,27):
            uid=r.num(2);r.num(2);taken=r.num(3)
            self.pending_pickups.pop(uid,None);self.drop_guards.pop(uid,None);self.metrics['pickups']+=1
            for item in self.state['items']:
                if item['uid']==uid:item['amount']=max(0,item['amount']-taken)
            self.state['items']=[i for i in self.state['items'] if i['amount']>0];self.dirty=True
        elif (f,a)==(7,8):
            pid=r.num(2);direction=r.num()
            row=next((c for c in self.state['characters'] if c['player_id']==pid),None)
            if row:row['direction']=direction;self.dirty=True
        elif self.events[-1].get('kind') in ('npc_damage','equip','unequip','door_locked','drop','item_junk','recover','stat_changed','npc_attack','peer_attack'):
            self.dirty=True

    def snapshot(self):
        data=super().snapshot()
        data['shop']=self.shop
        data.update(casting=({k:v for k,v in self.casting.items() if k in ('spell_id','target_kind','target_id','seconds')} if getattr(self,'casting',None) else None),skillmaster=getattr(self,'skillmaster',None),bank=self.bank,locker=self.locker,trade=self.trade,trade_request=self.trade_request)
        data.update(position_update=self.position_update,position_seq=self.position_seq,correction=self.correction)
        self.dirty=False;self.position_update=False;self.correction=False
        self.sent_state=deepcopy(data)
        return data

    def world_update(self):
        before=self.sent_state
        data=self.snapshot()
        if not before or before['map_id']!=data['map_id'] or any(e.get('kind')=='map_transition' for e in data['events']):return data
        # Compact entity changes, like native EO: never resend the full visible world per step.
        update={k:data[k] for k in ('map_id','position_update','position_seq','correction','events')}
        for key in ('bank','locker','trade','trade_request','casting','skillmaster'):
            if data.get(key)!=before.get(key):update[key]=data.get(key)
        if data['player']!=before['player'] or data['position_update']:update['player']=data['player']
        for collection,key in [('players','player_id'),('npcs','index'),('items','uid')]:
            old={r[key]:r for r in before[collection]};new={r[key]:r for r in data[collection]}
            changed=[row for id,row in new.items() if row!=old.get(id)]
            removed=list(old.keys()-new.keys())
            if changed:update[collection+'_upsert']=changed
            if removed:update[collection+'_remove']=removed
        return update
