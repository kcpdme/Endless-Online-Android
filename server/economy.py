"""Original etheos Shop packets; only acknowledged transactions change inventory."""
from collections import Counter
from eo_session import EOError, Reader, number
from services import NPC_SERVICE_DISTANCE

class EconomyMixin:
    shop = None

    def _standing(self):
        if getattr(self,"casting",None):raise EOError("Wait for your skill to finish")
        if getattr(self,'trade',None):raise EOError('Close the trade before using inventory or storage')
        if not self.state or self.warp or self.stats.get('dead') or self.pending_moves:
            raise EOError('Stop moving before interacting')

    def drop_item(self, item_id, amount=1):
        from services import item_definitions
        self._standing();item_id=int(item_id);amount=int(amount)
        if amount <= 0 or amount > 16194276 or amount > self.item_amount(item_id):raise EOError('Choose a quantity you have in your bag')
        if item_definitions().get(item_id,{}).get('special')==4:raise EOError('This item cannot be dropped')
        self.send(14,24,number(item_id,2)+number(amount,3)+b'\xff\xff')
        payload=self._wait_service(14,{24})
        r=Reader(payload)
        if r.num(2)!=item_id or r.num(3)<=0:raise EOError('Unexpected drop acknowledgement; reconnect')
        return self.snapshot()

    def _near_shop(self):
        self._standing()
        if not self.shop or self.shop['map_id'] != self.state['map_id']:
            raise EOError('Talk to the shopkeeper first')
        npc = next((n for n in self.state['npcs'] if n['index'] == self.shop['npc_index']), None)
        me = self.state['self']
        if not npc or abs(npc['x']-me['x'])+abs(npc['y']-me['y']) > NPC_SERVICE_DISTANCE:
            self.shop = None
            raise EOError('Move closer to the shopkeeper')

    def item_amount(self, item_id):
        return sum(i['amount'] for i in self.inventory if i['id'] == item_id)

    def _set_amount(self, item_id, amount):
        self.inventory = [i for i in self.inventory if i['id'] != item_id]
        if amount > 0:self.inventory.append(dict(id=item_id, amount=amount))

    def _weight(self, r):
        self.weight=r.num();self.max_weight=r.num()
        self.stats.update(weight=self.weight, max_weight=self.max_weight)

    def shop_open(self, npc_index):
        self._standing();self.shop = None
        npc = next((n for n in self.state['npcs'] if n['index'] == int(npc_index)), None)
        me = self.state['self']
        if not npc or abs(npc['x']-me['x'])+abs(npc['y']-me['y']) > NPC_SERVICE_DISTANCE:
            raise EOError('Move closer to the shopkeeper')
        self.send(13,13,number(int(npc_index),2))
        try:r = Reader(self.wait(13,13,timeout=2))
        except EOError:raise EOError('This NPC has no shop available')
        shop = dict(npc_id=r.num(2), name=r.text(), npc_index=int(npc_index), map_id=self.state['map_id'], trade=[], craft=[])
        while r.rest() and r.rest()[0] != 255:
            shop['trade'].append(dict(id=r.num(2), buy=r.num(3), sell=r.num(3), max_buy=r.num()))
        r.take(1)
        while r.rest() and r.rest()[0] != 255:
            item_id=r.num(2);ingredients=[]
            for _ in range(4):
                ingredient=r.num(2);amount=r.num()
                if ingredient and amount:ingredients.append(dict(id=ingredient, amount=amount))
            shop['craft'].append(dict(id=item_id, ingredients=ingredients))
        self.shop=shop
        return self.snapshot()

    def shop_trade(self, operation, item_id, amount=1):
        self._near_shop();item_id=int(item_id);amount=int(amount)
        offer=next((i for i in self.shop['trade'] if i['id']==item_id),None)
        if operation in ('buy','sell'):
            if not offer or offer[operation] <= 0:raise EOError('This item is not traded here')
            if amount <= 0:raise EOError('Choose a positive quantity')
            if operation=='buy':
                if amount > offer['max_buy']:raise EOError('This shop allows at most %d at a time' % offer['max_buy'])
                if self.item_amount(1) < offer['buy']*amount:raise EOError('You need more gold')
                if self.stats.get('weight',0) >= self.stats.get('max_weight',250):raise EOError('Your bag is too heavy')
            elif amount > self.item_amount(item_id):raise EOError('You do not have that many in your bag')
            action=11 if operation=='buy' else 12
            self.send(13,action,number(item_id,2)+number(amount,4))
            r=Reader(self.wait(13,action,timeout=2))
            remaining=r.num(4);ack_item=r.num(2);value=r.num(4)
            if ack_item != item_id:raise EOError('Unexpected shop acknowledgement; reconnect')
            if operation=='buy':self._set_amount(1,remaining);self.inventory_add(item_id,value)
            else:self._set_amount(item_id,remaining);self._set_amount(1,value)
            self._weight(r)
        elif operation=='craft':
            recipe=next((i for i in self.shop['craft'] if i['id']==item_id),None)
            if not recipe:raise EOError('This recipe is not available here')
            needed=Counter()
            for i in recipe['ingredients']:needed[i['id']]+=i['amount']
            if any(self.item_amount(i)<qty for i,qty in needed.items()):raise EOError('You need all the recipe ingredients')
            self.send(13,6,number(item_id,2));r=Reader(self.wait(13,6,timeout=2))
            if r.num(2)!=item_id:raise EOError('Unexpected crafting acknowledgement; reconnect')
            self._weight(r)
            while len(r.rest())>=6:self._set_amount(r.num(2),r.num(4))
            self.inventory_add(item_id,1)
        else:raise EOError('Unknown shop action')
        self.events.append(dict(kind='shop_transaction',operation=operation,item_id=item_id,amount=amount if operation!='craft' else 1))
        return self.snapshot()

    def pickup(self, uid):
        self._standing();uid=int(uid)
        item=next((i for i in self.state['items'] if i['uid']==uid),None)
        if not item:raise EOError('This drop is no longer on the ground')
        me=self.state['self']
        if abs(item['x']-me['x'])+abs(item['y']-me['y'])>2:raise EOError('Move closer to the drop')
        self.send(14,27,number(uid,2))
        try:self.wait(14,27,timeout=2)
        except EOError:
            raise EOError('Cannot pick up: the drop may be protected, your bag may be too heavy, or someone already took it')
        # Native Item_Get carries the inventory delta and weight. No world refresh needed.
        return self.snapshot()
