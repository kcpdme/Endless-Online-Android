"""Original EO Bank, Locker, Paperdoll and Trade packet flows.

Only native acknowledgements change inventories. No account/database writes here.
"""
from functools import lru_cache
from pathlib import Path
import os
import socket
import time
from eo_session import EOError, Reader, number

NPC_SERVICE_DISTANCE = 11

SLOTS = ['boots','accessory','gloves','belt','armor','necklace','head','offhand','weapon','ring1','ring2','armlet1','armlet2','bracer1','bracer2']

@lru_cache(maxsize=1)
def runtime_path():
    from run import state_path
    candidates = [Path(os.environ['ASTER_VALE_RUNTIME'])] if os.environ.get('ASTER_VALE_RUNTIME') else []
    candidates += [state_path()/'runtime', Path(__file__).resolve().parents[2]/'runtime']
    for runtime in candidates:
        if (runtime/'data/pub/dat001.eif').exists():return runtime
    raise EOError('Native item definitions are unavailable; please contact the operator')

@lru_cache(maxsize=1)
def item_definitions():
    r=Reader((runtime_path()/'data/pub/dat001.eif').read_bytes())
    if r.take(3)!=b'EIF':raise EOError('Invalid native item definitions')
    r.take(4);count=r.num(2);r.num();result={}
    for item_id in range(1,count+1):
        name=r.take(r.num()).decode('latin1');f=r.take(58)
        if name.lower()=='eof':break
        result[item_id]={'special':Reader(f[4:5]).num(),'weight':Reader(f[55:56]).num(), 'type':Reader(f[2:3]).num(), 'hp':Reader(f[5:7]).num(2), 'tp':Reader(f[7:9]).num(2), 'graphic_value':Reader(f[32:35]).num(3), 'scroll_map':Reader(f[32:35]).num(3), 'scroll_x':Reader(f[35:36]).num(), 'scroll_y':Reader(f[36:37]).num()}
    return result

@lru_cache(maxsize=1)
def bank_settings():
    # Read only these public gameplay settings, following the native INCLUDE order.
    settings={'BankUpgradeBase':1000,'BankUpgradeStep':1000,'BaseBankSize':25,'BankSizeStep':5,'MaxBankUpgrades':7}
    runtime=runtime_path();seen=set()
    def read(path):
        path=path.resolve()
        if path in seen or not path.is_relative_to(runtime.resolve()) or not path.is_file():return
        seen.add(path)
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=');key=key.strip();value=value.split('#',1)[0].strip()
            if not sep:continue
            if key in ('INCLUDE','REQUIRE'):read(runtime/value)
            elif key in settings:settings[key]=int(value.replace(',',''))
    read(runtime/'config.ini');read(runtime/'config.local.ini')
    return settings

class ServicesMixin:
    def init_services(self):
        self.bank=None; self.locker=None; self.trade=None; self.trade_request=None;self.last_chat=0;self.online_roster=None;self.roster_requested=0

    def _wait_service(self, family, actions, timeout=2):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            self.sock.settimeout(max(.1,deadline-time.monotonic()))
            try: f,a,p=self.receive()
            except socket.timeout: raise EOError('The server declined this action. Check quantity, capacity and distance.')
            finally: self.sock.settimeout(8)
            if self.control_packet(f,a,p): continue
            self.apply_event(f,a,p)
            if (f,a)==(37,16): raise EOError('Your locker is full. Ask the banker for more space.')
            if f==family and a in actions: return p
        raise EOError('The server did not acknowledge this action')

    def _near(self, target, distance):
        self._standing()
        if not target or target['map_id']!=self.state['map_id']: raise EOError('Open this service again nearby')
        me=self.state['self']
        if abs(target['x']-me['x'])+abs(target['y']-me['y'])>distance: raise EOError('Move closer first')

    def _near_service(self, context):
        self._standing()
        if not context or context['map_id']!=self.state['map_id']:raise EOError('Open this service again within view')
        npc=next((n for n in self.state['npcs'] if n['index']==context['npc_index']),None)
        me=self.state['self']
        if not npc or abs(npc['x']-me['x'])+abs(npc['y']-me['y'])>NPC_SERVICE_DISTANCE:raise EOError('This NPC is no longer within view')

    def bank_open(self, npc_index):
        self._standing()
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc: raise EOError('This banker is no longer nearby')
        context=dict(npc_index=npc_index,map_id=self.state['map_id'],x=npc['x'],y=npc['y'])
        self._near_service(context)
        self.send(36,13,number(npc_index,2));r=Reader(self._wait_service(36,{13}))
        context.update(gold=r.num(4),token=r.num(3),upgrades=r.num())
        self.bank=context;self._bank_capacity();self.locker=None
        return self.snapshot()

    def bank_change(self, withdraw, amount):
        self._near_service(self.bank);amount=int(amount)
        maximum=self.bank['gold'] if withdraw else self.item_amount(1)
        if amount<=0 or amount>maximum or amount>=253**4: raise EOError('Choose an amount within your available Gold')
        self.send(36,9 if withdraw else 7,number(amount,4)+number(self.bank['token'],3))
        self._wait_service(36,{3});return self.snapshot()

    def _bank_capacity(self):
        settings=bank_settings();n=self.bank['upgrades']
        self.bank.update(capacity=settings['BaseBankSize']+n*settings['BankSizeStep'],upgrade_cost=settings['BankUpgradeBase']+n*settings['BankUpgradeStep'],can_upgrade=n<settings['MaxBankUpgrades'])

    def bank_upgrade(self):
        self._near_service(self.bank);self._bank_capacity()
        if not self.bank['can_upgrade']:raise EOError('Your locker is fully expanded')
        if self.item_amount(1)<self.bank['upgrade_cost']:raise EOError('You need more Gold to expand your locker')
        self.send(37,11);self._wait_service(37,{11});return self.snapshot()

    def locker_open(self,x,y):
        context=dict(x=int(x),y=int(y),map_id=self.state['map_id'])
        self._near(context,1)
        if not(0<=x<252 and 0<=y<252): raise EOError('Invalid locker position')
        self.send(37,13,number(x,1)+number(y,1));r=Reader(self._wait_service(37,{13}))
        if (r.num(),r.num())!=(x,y): raise EOError('Locker position changed')
        context['items']=self._locker_items(r);self.locker=context;self.bank=None
        return self.snapshot()

    def locker_change(self, withdraw, item_id, amount=1):
        self._near(self.locker,1);item_id=int(item_id);amount=int(amount)
        if item_id<=1 or item_id>=253**2: raise EOError('Store Gold with the banker; lockers hold items')
        if withdraw:
            if not any(i['id']==item_id for i in self.locker['items']): raise EOError('That item is no longer in the locker')
        elif amount<=0 or amount>self.item_amount(item_id) or amount>=253**3: raise EOError('Choose an amount within your bag quantity')
        payload=number(self.locker['x'],1)+number(self.locker['y'],1)+number(item_id,2)
        self.send(37,9 if withdraw else 7,payload+(b'' if withdraw else number(amount,3)))
        self._wait_service(37,{27 if withdraw else 3});return self.snapshot()

    @staticmethod
    def _locker_items(r):
        items=[]
        while len(r.rest())>=5: items.append(dict(id=r.num(2),amount=r.num(3)))
        return items

    def inspect_player(self,player_id):
        self._standing();self._peer(player_id)
        self.send(30,1,number(player_id,2));r=Reader(self._wait_service(30,{3}))
        data=dict(zip(('name','home','partner','title','guild','rank'),[r.text() for _ in range(6)]))
        data.update(player_id=r.num(2),class_id=r.num(),gender=r.num());r.num()
        if data['player_id']!=player_id: raise EOError('This player has left your view')
        data['equipment']={key:r.num(2) for key in SLOTS}
        return data

    def _peer(self,pid):
        peer=next((p for p in self.state['characters'] if p['player_id']==pid and pid!=self.player_id),None)
        me=self.state['self']
        if not peer or abs(peer['x']-me['x'])+abs(peer['y']-me['y'])>11: raise EOError('This player is no longer nearby')
        return peer

    def trade_action(self,action,player_id=0,item_id=0,amount=0,agree=True):
        if action in ('request','accept'):
            self._standing();self._peer(player_id);item_definitions()
            if action=='accept' and (not self.trade_request or self.trade_request['player_id']!=player_id or self.trade_request['expires']<time.monotonic()): raise EOError('This invitation has expired; ask for another')
            self.send(32,1 if action=='request' else 2,number(0 if action=='request' else 1,1)+number(player_id,2))
            if action=='accept': self._wait_service(32,{13})
            else: self.events.append(dict(kind='trade_sent',message='Trade invitation sent. Waiting for the other player.'))
        elif action=='decline': self.trade_request=None
        else:
            if not self.trade: raise EOError('There is no active trade')
            if action=='cancel':
                self.send(32,14,number(0,1));self.trade=None;self.trade_request=None
            elif action=='add':
                definitions=item_definitions()
                if item_id not in definitions or definitions[item_id]['special']==4: raise EOError('This item cannot be traded')
                own=self.trade['offers'].get(str(self.player_id),[])
                # Native Trade_Remove refuses >5 entries. Keep every offer removable.
                if len(own)>=5 and not any(i['id']==item_id for i in own): raise EOError('Offer up to five different items at a time')
                if amount<=0 or amount>self.item_amount(item_id) or amount>=253**4: raise EOError('Choose a quantity within your bag amount')
                self.send(32,7,number(item_id,2)+number(amount,4));self._wait_service(32,{3,17})
            elif action=='remove':
                if not any(i['id']==item_id for i in self.trade['offers'].get(str(self.player_id),[])): raise EOError('This item is not offered')
                self.send(32,4,number(item_id,2));self._wait_service(32,{3,17})
            elif action=='agree':
                if agree and not self.trade['offers'].get(str(self.player_id)): raise EOError('Add an item or Gold before accepting, as in the original server')
                self.send(32,5,number(int(agree),1));self._wait_service(32,{16,10})
            else: raise EOError('Unknown trade action')
        return self.snapshot()

    @staticmethod
    def _offers(r):
        offers={}
        while len(r.rest())>=2:
            pid=r.num(2);items=[]
            while len(r.rest())>=6 and r.rest()[0]!=255: items.append(dict(id=r.num(2),amount=r.num(4)))
            if r.rest()[:1]==b'\xff': r.take(1)
            offers[str(pid)]=items
        return offers

    def request_online_players(self):
        if not self.state:raise EOError('Enter the world before viewing online players')
        if self.warp or self.pending_moves:raise EOError('Finish this step before refreshing online players')
        now=time.monotonic()
        if now-self.roster_requested<5:
            if self.online_roster is not None:
                self.events.append(dict(kind='online_players',players=self.online_roster));self.dirty=True
            return dict(requested=False)
        self.send(22,1);self.roster_requested=now
        return dict(requested=True)

    @staticmethod
    def parse_online_players(payload):
        r=Reader(payload)
        if r.num()!=8:raise EOError('Unexpected native online list')
        count=r.num(2)
        if count>10000 or r.take(1)!=b'\xff':raise EOError('Invalid native online list')
        players=[]
        for _ in range(count):
            display_name=r.text();title=r.text();r.num();icon=r.num();class_id=r.num()
            guild=r.text().strip()
            players.append(dict(name=display_name.split(' ',1)[0],display_name=display_name,title=title,icon=icon,class_id=class_id,guild=guild))
        if r.rest():raise EOError('Unexpected native online list fields')
        return sorted(players,key=lambda p:p['name'].lower())

    def chat_send(self,channel,message,target=''):
        if not self.state: raise EOError('Enter the world before chatting')
        message=str(message).strip();target=str(target).strip().lower()
        if channel not in ('local','global','private'): raise EOError('Unknown chat channel')
        if not message or len(message)>128 or any(ord(c)<32 or ord(c)==255 for c in message): raise EOError('Use 1–128 printable characters')
        try: payload=message.encode('latin1')
        except UnicodeEncodeError: raise EOError('Classic EO chat supports Latin characters; use English for this message')
        now=time.monotonic()
        if now-self.last_chat<.7: raise EOError('Wait a moment between messages')
        # EO commands are Talk_Report (nearby), even when typed in another tab.
        # The native role/command permissions decide what can run. Never publish
        # command text into Global/Whisper or manufacture a nearby speech bubble.
        if message.startswith('$'):
            channel='local';target=''
            if int(self.stats.get('admin',0))>0:
                self.send(18,21,payload);self.last_chat=now
                return self.snapshot()
        if channel=='private':
            if not target.isalpha() or not 4<=len(target)<=16 or not target.isascii(): raise EOError('Enter a valid character name')
            payload=target.encode('ascii')+b'\xff'+payload
        self.send(18,{'local':21,'global':15,'private':20}[channel],payload);self.last_chat=now
        # The original server omits the sender from chat broadcasts. Echo locally,
        # as EndlessClient does; a native not-found/mute response remains visible.
        self.events.append(dict(kind='chat',channel=channel,name=self.state['self']['name'],message=message,target=target,outgoing=True,player_id=self.player_id))
        return self.snapshot()

    def apply_service_packet(self,f,a,p):
        r=Reader(p)
        if (f,a)==(255,255) and p[:1]==number(8,1):
            self.online_roster=self.parse_online_players(p)
            self.events.append(dict(kind='online_players',players=self.online_roster))
        elif f==18:
            event=dict(kind='chat',channel='system',name='Server')
            if a==8:
                pid=r.num(2);peer=next((c for c in self.state['characters'] if c['player_id']==pid),{})
                event.update(channel='local',player_id=pid,name=peer.get('name','Player'),message=r.rest().decode('latin1'))
            elif a in (15,20,17,22): event.update(channel={15:'global',20:'private',17:'system',22:'system'}[a],name=r.text(),message=r.text())
            elif a==23:event['message']=r.rest().decode('latin1')
            elif a==3:r.num(2);event['message']='Character not found: '+r.rest().decode('latin1')
            elif a==16:event['message']='The server has muted your character.'
            else:return
            self.events.append(event)
        elif (f,a)==(36,3) and self.bank:
            self._set_amount(1,r.num(4));self.bank['gold']=r.num(4)
        elif (f,a)==(37,11) and self.bank:
            self._set_amount(1,r.num(4));self.bank['upgrades']=r.num();self._bank_capacity()
        elif f==37 and a in (3,27) and self.locker:
            item_id=r.num(2);amount=r.num(3 if a==27 else 4)
            if a==27:self.inventory_add(item_id,amount)
            else:self._set_amount(item_id,amount)
            self._weight(r);self.locker['items']=self._locker_items(r)
        elif (f,a)==(32,1):
            r.num();pid=r.num(2)
            self.trade_request=dict(player_id=pid,name=r.rest().decode('latin1'),expires=time.monotonic()+30)
        elif (f,a)==(32,13):
            pid=r.num(2);name=r.text();r.num(2);r.text()
            self.trade=dict(player_id=pid,name=name,offers={},agreed=False,peer_agreed=False)
            self.trade_request=None;self.bank=None;self.locker=None;self.shop=None
        elif f==32 and a in (3,17,10):
            offers=self._offers(r)
            if a==10:
                definitions=item_definitions();weight_delta=0
                for pid,items in offers.items():
                    for item in items:
                        delta=(-1 if int(pid)==self.player_id else 1)*item['amount']
                        self._set_amount(item['id'],self.item_amount(item['id'])+delta)
                        weight_delta+=definitions.get(item['id'],{}).get('weight',0)*delta
                # Native admins with unlimitedweight report the 0 / 251 sentinel.
                self.weight=0 if self.max_weight==251 else max(0,min(250,self.weight+weight_delta));self.stats['weight']=self.weight
                self.trade=None;self.trade_request=None
                self.events.append(dict(kind='trade_complete',message='Trade complete. Your inventory has been updated.'))
            elif self.trade:self.trade.update(offers=offers,agreed=False,peer_agreed=False)
        elif (f,a)==(32,16) and self.trade:self.trade['agreed']=bool(r.num())
        elif (f,a)==(32,5) and self.trade:r.num(2);self.trade['peer_agreed']=bool(r.num())
        elif (f,a)==(32,14):
            self.trade=None;self.trade_request=None
            self.events.append(dict(kind='trade_cancelled',message='Trade cancelled. No items changed hands.'))
        else:return
        self.dirty=True
