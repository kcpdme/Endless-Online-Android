"""Original Chest Open/Add/Take and native inventory acknowledgements."""
from eo_session import EOError, Reader, number
from services import item_definitions

class ChestsMixin:
    chest = None
    chest_rejection = None

    @staticmethod
    def _chest_items(reader):
        if len(reader.rest()) % 5:raise EOError('Malformed native chest contents')
        items=[]
        while reader.rest():
            item,amount=reader.num(2),reader.num(3)
            if item>0 and amount>0:items.append(dict(id=item,amount=amount))
        return items

    def _wait_chest(self, action):
        self.chest_rejection=None
        payload=self._wait_service(33,{action,14})
        if self.chest_rejection:raise EOError(self.chest_rejection)
        return payload

    def chest_open(self,x,y):
        x,y=int(x),int(y)
        if not self.state or not (0<=x<=251 and 0<=y<=251):raise EOError('Invalid chest position')
        self.chest=None
        context=dict(x=x,y=y,map_id=self.state['map_id'])
        self._near(context,1)
        self.chest=context
        try:
            self.send(33,13,number(x,1)+number(y,1));self._wait_chest(13)
            if not self.chest or 'items' not in self.chest:raise EOError('Open the chest again nearby')
        except Exception:
            self.chest=None
            raise
        self.shop=None;self.bank=None;self.locker=None
        return self.snapshot()

    def chest_change(self,withdraw,item_id,amount=1):
        self._near(self.chest,1);item_id,amount=int(item_id),int(amount)
        if not self.chest or 'items' not in self.chest:raise EOError('Open this chest first')
        if not 0<item_id<253**2:raise EOError('Invalid chest item')
        if withdraw:
            if not any(i['id']==item_id for i in self.chest['items']):raise EOError('That item is no longer in the chest')
        else:
            if amount<=0 or amount>=253**3 or amount>self.item_amount(item_id):raise EOError('Choose a quantity within your bag amount')
            if item_definitions().get(item_id,{}).get('special')==4:raise EOError('This item cannot be put in a chest')
        payload=number(self.chest['x'],1)+number(self.chest['y'],1)+number(item_id,2)
        self.send(33,9 if withdraw else 7,payload+(b'' if withdraw else number(amount,3)))
        self._wait_chest(27 if withdraw else 3)
        return self.snapshot()

    def chest_close(self):
        # Original dialog closure sends no native Chest_Close packet.
        self.chest=None
        return self.snapshot()

    def apply_chest_packet(self,f,a,p):
        if f!=33:return
        r=Reader(p)
        if a==14:
            self.chest=None
            self.chest_rejection='This chest is broken.' if len(p)<2 else 'This chest is locked. Bring the matching key.'
        elif self.chest and self.chest['map_id']==self.state['map_id']:
            me=self.state['self']
            if abs(me['x']-self.chest['x'])+abs(me['y']-self.chest['y'])>1:
                self.chest=None
                return
            if a==13:
                if (r.num(),r.num())!=(self.chest['x'],self.chest['y']):raise EOError('Chest position changed')
                self.chest['items']=self._chest_items(r)
            elif a in (3,27):
                item_id=r.num(2);amount=r.num(3 if a==27 else 4)
                weight,max_weight=r.num(),r.num();items=self._chest_items(r)
                if a==27:self.inventory_add(item_id,amount)
                else:self._set_amount(item_id,amount)
                self.weight=weight;self.max_weight=max_weight;self.stats.update(weight=weight,max_weight=max_weight)
                self.chest['items']=items
            elif a==5:self.chest['items']=self._chest_items(r)
            else:return
        else:return
        self.dirty=True
