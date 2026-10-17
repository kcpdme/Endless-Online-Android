"""Original Citizen/Innkeeper sleep quote, payment, full recovery and sleep warp."""
from eo_session import EOError, Reader, number
from eo_stats import update
from skills import npc_types

class InnsMixin:
    inn=None

    def inn_open(self,npc_index):
        self._standing();npc_index=int(npc_index)
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc or npc_types().get(npc['id'])!=7:raise EOError('Select a nearby innkeeper')
        context=dict(npc_index=npc_index,npc_id=npc['id'],map_id=self.state['map_id'],x=npc['x'],y=npc['y'])
        self._near_service(context);self.inn=context
        try:
            self.send(49,13,number(npc_index,2));self._wait_service(49,{13})
            if not self.inn or 'vendor_id' not in self.inn:raise EOError('This inn has no registration data')
        except Exception:self.inn=None;raise
        self.quest_context=None;self.quest_dialog=None
        self.shop=None;self.bank=None;self.locker=None;self.chest=None;self.skillmaster=None
        return self.snapshot()

    def inn_quote(self):
        self._near_service(self.inn)
        me=self.state['self']
        if me.get('hp',0)>=me.get('maxhp',0) and me.get('tp',0)>=me.get('maxtp',0):raise EOError('Your HP and TP are already full')
        self.send(49,1,number(self.inn['session_id'],2)+number(self.inn['vendor_id'],2));self._wait_service(49,{1})
        return self.snapshot()

    def inn_sleep(self):
        self._near_service(self.inn)
        if 'cost' not in self.inn:raise EOError('Ask the innkeeper for the sleep price first')
        if self.item_amount(1)<self.inn['cost']:raise EOError('You do not have enough Gold to sleep here')
        # Native recalculates the price and owns payment/recovery/warp.
        self.send(49,2,number(self.inn['session_id'],2)+number(self.inn['vendor_id'],2));self._wait_service(49,{2})
        self.inn=None
        return self.snapshot()

    def inn_close(self):
        self.inn=None;return self.snapshot()

    def apply_inn_packet(self,f,a,p):
        if f!=49:return
        r=Reader(p)
        if a==2:
            # This native acknowledgement proves Gold was spent and HP/TP restored.
            gold=r.num(4);self._set_amount(1,gold)
            update(self,dict(hp=self.state['self']['maxhp'],tp=self.state['self']['maxtp']))
            self.events[-1].update(kind='inn_recovered',gold=gold)
            self.inn=None
        elif self.inn:
            if a==13:
                vendor=r.num(3);citizen_vendor=r.num();session=r.num(2)
                if r.take(1)!=b'\xff':raise EOError('Malformed innkeeper dialogue')
                questions=[r.text(),r.text(),r.rest().decode('latin1')]
                self.inn.update(vendor_id=vendor,citizen_vendor_id=citizen_vendor,session_id=session,questions=questions)
            elif a==1:self.inn['cost']=r.num(4)
            else:return
        else:return
        self.dirty=True
