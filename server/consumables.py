"""Original Item_Use / Item_Reply packets; quantities and effects are native-owned."""
import time
import random
from eo_session import EOError, Reader, number
from eo_stats import ATTRIBUTES, DERIVED, update
from services import item_definitions, runtime_path

USABLE_TYPES = (3, 4, 6, 22, 23, 24, 25)

class ConsumablesMixin:
    def potion_queue(self):
        pending=getattr(self,'pending_potion',None)
        return pending.get('queue',[pending]) if pending else []

    def set_potion_queue(self,queue):
        self.pending_potion=dict(id=queue[0]['id'],until=queue[0]['until'],queue=queue) if queue else None
        self.using_item=queue[0]['id'] if queue else None

    def finish_potion(self,item_id):
        queue=list(self.potion_queue())
        for entry in queue:
            if entry['id']==item_id:
                queue.remove(entry);self.set_potion_queue(queue);return True
        return False

    def use_potion(self, item_id):
        if item_definitions().get(int(item_id),{}).get('type')!=3:raise EOError('Select a health or mana potion')
        return self.use_item(item_id,asynchronous=True)

    def use_item(self, item_id, asynchronous=False):
        item_id=int(item_id)
        item=item_definitions().get(item_id,{})
        kind=item.get('type',-1)
        if kind==3:self._mobile_action()
        else:self._standing()
        if kind not in USABLE_TYPES:raise EOError('This item cannot be used as a consumable')
        if self.item_amount(item_id)<=0:raise EOError('This item is no longer in your bag')
        me=self.state['self']
        if kind==3 and not ((item['hp']>0 and me['hp']<me['maxhp']) or (item['tp']>0 and me['tp']<me['maxtp'])):
            raise EOError('Your HP/TP is already full for this potion. Nothing was consumed.')
        if kind==4:
            path=runtime_path()/'data/maps'/('%05d.emf' % self.state['map_id'])
            with path.open('rb') as source:source.seek(0x2a);scroll_allowed=Reader(source.read(1)).num()
            if not scroll_allowed:raise EOError('Scrolls cannot be used on this map. Nothing was consumed.')
            if item['scroll_map'] and (me['map_id'],me['x'],me['y'])==(item['scroll_map'],item['scroll_x'],item['scroll_y']):
                raise EOError('You are already at this scroll destination. Nothing was consumed.')
        if kind==24 and me['haircolor']==item['graphic_value']:raise EOError('Your hair already has this color. Nothing was consumed.')
        if kind==25 and not any(item_definitions().get(i,{}).get('special')==5 for i in self.equipment.values()):raise EOError('You have no cursed equipment to cure. Nothing was consumed.')
        if kind==3 and asynchronous:
            queue=list(self.potion_queue())
            if len(queue)>=4:raise EOError('Wait for the queued potions')
            if sum(e['id']==item_id for e in queue)>=self.item_amount(item_id):raise EOError('All remaining potions are already queued')
            hp=min(me['maxhp'],me['hp']+sum(e.get('hp',0) for e in queue))
            tp=min(me['maxtp'],me['tp']+sum(e.get('tp',0) for e in queue))
            if not ((item['hp']>0 and hp<me['maxhp']) or (item['tp']>0 and tp<me['maxtp'])):raise EOError('Queued potions already cover your missing HP/TP')
            queue.append(dict(id=item_id,hp=item['hp'],tp=item['tp'],until=time.monotonic()+5))
            self.set_potion_queue(queue)
            self.send(14,10,number(item_id,2))
            return {'sent':True,'item_id':item_id}
        if self.potion_queue():raise EOError('Wait for your potions to finish before using another item')
        self.using_item=item_id
        try:
            self.send(14,10,number(item_id,2))
            # Session.wait completes a pending native Warp before returning the
            # scroll result, so the snapshot cannot re-enable input on the old map.
            try:self.wait(14,3,timeout=4)
            except EOError as exc:
                if getattr(self,'item_use_rejected',False):raise
                raise EOError('The server did not allow this item here. Check HP/TP or whether you are already at the scroll destination.') from exc
            if kind==25:self.paperdoll()
            return self.snapshot()
        finally:self.using_item=None;self.item_use_rejected=False

    def apply_item_packet(self,f,a,p):
        if (f,a)==(14,5):
            item_id=Reader(p).num(2)
            if self.finish_potion(item_id):
                self.dirty=True
                self.events.append(dict(kind='item_use_failed',item_id=item_id,message='The potion is no longer in your bag.'))
                return
            if getattr(self,'using_item',None)==item_id:
                self.item_use_rejected=True
                raise EOError('The server says this item is no longer in your bag')
        if (f,a)!=(14,3):return
        r=Reader(p);kind=r.num();item_id=r.num(2)
        if kind not in USABLE_TYPES:raise EOError('Unsupported item acknowledgement')
        remaining=r.num(4);weight=r.num();maximum=r.num()
        consumed=max(0,self.item_amount(item_id)-remaining)
        self._set_amount(item_id,remaining);self.weight=weight;self.max_weight=maximum
        values=dict(weight=weight,max_weight=maximum)
        event=dict(kind='item_used',item_id=item_id,item_type=kind,remaining=remaining)
        if kind==3:
            self.finish_potion(item_id);event['consumed']=consumed
            event['hp_gain']=r.num(4);values.update(hp=r.num(2),tp=r.num(2))
        elif kind==22:
            event['consumed']=consumed
            if consumed:
                potency=item_definitions().get(item_id,{}).get('beer_potency',0)
                seconds=(100+potency*10)/8.0
                self.drunk_until=time.monotonic()+seconds
                self.drunk_emote_at=0
                event.update(drunk_seconds=seconds,beer_potency=potency)
                self.poll_drunk()
        elif kind==24:
            color=r.num();self.state['self']['haircolor']=color;event['haircolor']=color
        elif kind==23:event['effect_id']=r.num(2)
        elif kind==25:
            for key in ('max_hp','max_tp',*ATTRIBUTES,*DERIVED):values[key]=r.num(2)
            definitions=item_definitions()
            for slot,item in list(self.equipment.items()):
                if definitions.get(item,{}).get('special')==5:self.equipment[slot]=0
            graphics=list(self.state['self'].get('equipment_graphics',[0]*9))
            for slot,index in [('boots',0),('armor',4),('head',6),('offhand',7),('weapon',8)]:graphics[index]=definitions.get(self.equipment.get(slot,0),{}).get('graphic_value',0)
            self.state['self']['equipment_graphics']=graphics
        elif kind==6:
            values['experience']=r.num(4);level=r.num()
            if level:values['level']=level;event['level_up']=level
            for key in ('stat_points','skill_points','max_hp','max_tp','max_sp'):values[key]=r.num(2)
        update(self,values);self.events.append(event);self.dirty=True

    def poll_drunk(self):
        until=getattr(self,'drunk_until',0)
        if not until:return
        now=time.monotonic()
        if now>=until:
            self.drunk_until=0
            self.events.append(dict(kind='drunk_ended',player_id=self.player_id));self.dirty=True
        elif now>=getattr(self,'drunk_emote_at',0):
            self.drunk_emote_at=now+random.randint(4,6)
            self.send(9,21,number(11,1))
            self.events.append(dict(kind='player_emote',player_id=self.player_id,emote=11));self.dirty=True
