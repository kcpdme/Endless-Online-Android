#!/usr/bin/env python3
"""Native EO v28 client session for real etheos integration and a local development adapter.

Contracts derived from pinned etheos handlers and MIT eolib-dotnet codec documentation.
No credentials or raw account/login payloads are logged.
"""
import secrets, socket, time
from handshake import encode as number, decode as read_number, read_exact

def multiples(data, multi):
    data=bytearray(data);start=0
    for end in range(len(data)+1):
        if end<len(data) and data[end]%multi==0:continue
        data[start:end]=data[start:end][::-1];start=end+1
    return bytes(data)
def flip(data):return bytes(b if b in (0,128) else b^128 for b in data)
def interleave(data):
    out=bytearray(len(data));order=list(range(0,len(data),2))+list(range((len(data)-1 if len(data)%2==0 else len(data)-2),-1,-2))
    for pos,value in zip(order,data):out[pos]=value
    return bytes(out)
def deinterleave(data):return data[::2]+data[1::2][::-1]
def encrypt(data,multi):return flip(interleave(multiples(data,multi)))
def decrypt(data,multi):return multiples(deinterleave(flip(data)),multi)
def string(value):
    data=str(value).encode('ascii')
    if b'\xff' in data or b'\0' in data:raise ValueError('Unsupported EO string')
    return data+b'\xff'
class Reader:
    def __init__(self,data):self.data=data;self.pos=0
    def take(self,n):
        result=self.data[self.pos:self.pos+n]
        if len(result)!=n:raise RuntimeError('Truncated EO payload')
        self.pos+=n;return result
    def num(self,n=1):return read_number(self.take(n))
    def text(self):
        end=self.data.index(255,self.pos);data=self.data[self.pos:end];self.pos=end+1;return data.decode('latin1')
    def rest(self):return self.data[self.pos:]
class EOError(RuntimeError):pass
class Session:
    def __init__(self,host='127.0.0.1',port=8078):
        self.sock=socket.create_connection((host,port),timeout=8);self.sock.settimeout(8)
        self.encode_multi=0;self.decode_multi=0;self.seq_start=0;self.counter=1;self.character_id=None;self.state=None;self.characters=[];self.events=[]
        self.timestamp=1000;self.last_walk=0;self.last_attack=0
        challenge=12345;payload=b'\xff\xff'+number(challenge,3)+b''.join(number(n,1) for n in [0,0,28,0,0])+str(secrets.randbelow(1000000000)+1).encode('ascii')
        self.sock.sendall(number(len(payload),2)+payload)
        init=self.receive_raw()
        if len(init)!=12 or init[:3]!=b'\xff\xff\x02':raise EOError('Server rejected EO initialization')
        self.seq_start=init[3]*7+init[4]-13;self.decode_multi=init[5];self.encode_multi=init[6];self.player_id=read_number(init[7:9])
        if read_number(init[9:12])!=266403:raise EOError('EO challenge failed')
        self.send(1,2,number(self.encode_multi,2)+number(self.decode_multi,2)+number(self.player_id,2))
    def close(self):
        if self.sock:self.sock.close();self.sock=None
    def receive_raw(self):return read_exact(self.sock,read_number(read_exact(self.sock,2)))
    def send(self,family,action,payload=b''):
        seq=self.seq_start+self.counter;self.counter=(self.counter+1)%10
        body=bytes([action,family])+number(seq,2 if seq>=253 else 1)+payload
        body=encrypt(body,self.encode_multi)
        self.sock.sendall(number(len(body),2)+body)
    def receive(self):
        raw=self.receive_raw();data=raw if raw[:2]==b'\xff\xff' else decrypt(raw,self.decode_multi)
        if len(data)<2:raise EOError('EO frame lacks packet identifier')
        return data[1],data[0],data[2:]
    def wait(self,family,action,timeout=8):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            self.sock.settimeout(max(0.1,deadline-time.monotonic()))
            try:f,a,p=self.receive()
            except socket.timeout:raise EOError(f'No server acknowledgement for EO {family}/{action}; action may have been rejected')
            finally:self.sock.settimeout(8)
            if (f,a)==(1,8):
                r=Reader(p);self.seq_start=r.num(2)-r.num();self.send(1,240,b'k');continue
            self.apply_event(f,a,p)
            if (f,a)==(family,action):return p
        raise EOError(f'Timed out waiting for EO {family}/{action}')
    def register(self,username,password):
        self.send(2,1,username.encode('ascii'));reply=self.wait(2,3)
        if not reply.endswith(b'OK') or len(reply)!=5:raise EOError('Account unavailable or rejected')
        r=Reader(reply);create_id=r.num(2);self.seq_start=r.num()
        self.send(2,6,number(create_id,2)+b'\xff'+b''.join(string(v) for v in [username,password,'Development Player','Local Development','dev@example.invalid','AsterValeDev','424242']))
        r=Reader(self.wait(2,3,timeout=15))
        if r.num(2)!=3:raise EOError('Account registration failed')
        return {'registered':True}
    def login(self,username,password):
        self.send(4,1,string(username)+string(password));data=self.wait(4,3,timeout=15);r=Reader(data);code=r.num(2)
        if code!=3:raise EOError(f'Login rejected (code {code})')
        self.characters=self.parse_characters(r);return {'characters':self.characters}
    def parse_characters(self,r):
        count=r.num();r.take(2);result=[]
        for _ in range(count):
            name=r.text();id=r.num(4);level=r.num();gender=r.num();hair=r.num();color=r.num();race=r.num();admin=r.num();equipment=[r.num(2) for _ in range(5)];r.take(1)
            result.append(dict(id=id,name=name,level=level,gender=gender,hairstyle=hair,haircolor=color,race=race,admin=admin,equipment_graphics=equipment))
        return result
    def create_character(self,name,gender=1,hairstyle=1,haircolor=0,race=0):
        self.send(3,1,string('NEW'));r=Reader(self.wait(3,3));op_id=r.num(2)
        self.send(3,6,b''.join(number(n,2) for n in [op_id,gender,hairstyle,haircolor,race])+b'\xff'+string(name))
        r=Reader(self.wait(3,3));code=r.num(2)
        if code!=5:raise EOError(f'Character creation rejected (code {code})')
        self.characters=self.parse_characters(r);return {'characters':self.characters}
    def enter(self,character_id):
        self.character_id=int(character_id);self.send(5,1,number(self.character_id,4));r=Reader(self.wait(5,3))
        if r.num(2)!=1:raise EOError('Welcome not granted')
        self.player_id=r.num(2);r.num(4);self.map_id=r.num(2)
        self.send(5,15,number(self.player_id,3)+number(self.character_id,4));r=Reader(self.wait(5,3))
        if r.num(2)!=2:raise EOError('Welcome not completed')
        r.take(1)
        for _ in range(9):r.text()
        self.weight=r.num();self.max_weight=r.num();self.inventory=[]
        while r.data[r.pos]!=255:self.inventory.append({'id':r.num(2),'amount':r.num(4)})
        r.take(1)
        self.spells=[]
        while r.data[r.pos]!=255:self.spells.append({'id':r.num(2),'level':r.num(2)})
        r.take(1);self.state=self.parse_snapshot(r)
        self.state.update({'inventory':self.inventory,'spells':self.spells,'online':True,'character_id':self.character_id,'player_id':self.player_id})
        self.paperdoll()
        return self.state
    def parse_snapshot(self,r):
        count=r.num();r.take(1);characters=[]
        for _ in range(count):
            name=r.text();pid=r.num(2);map_id=r.num(2);x=r.num(2);y=r.num(2);direction=r.num();r.take(1);guild=r.take(3).decode('latin1');level=r.num();gender=r.num();hair=r.num();color=r.num();race=r.num();maxhp=r.num(2);hp=r.num(2);maxtp=r.num(2);tp=r.num(2);equipment=[r.num(2) for _ in range(9)];sitting=r.num();invisible=r.num();r.take(1)
            characters.append(dict(name=name,player_id=pid,map_id=map_id,x=x,y=y,direction=direction,level=level,gender=gender,hairstyle=hair,haircolor=color,race=race,maxhp=maxhp,hp=hp,maxtp=maxtp,tp=tp,equipment_graphics=equipment,sitting=sitting))
        npcs=[]
        while r.pos<len(r.data) and r.data[r.pos]!=255:
            npcs.append({'index':r.num(),'id':r.num(2),'x':r.num(),'y':r.num(),'direction':r.num()})
        r.take(1);items=[]
        while r.pos<len(r.data):items.append({'uid':r.num(2),'id':r.num(2),'x':r.num(),'y':r.num(),'amount':r.num(3)})
        me=next((c for c in characters if c['player_id']==self.player_id),None)
        return {'map_id':me['map_id'] if me else self.map_id,'self':me,'characters':characters,'npcs':npcs,'items':items}
    def refresh(self):
        self.send(25,1);state=self.parse_snapshot(Reader(self.wait(25,3)))
        if self.state:state.update({k:self.state[k] for k in ['inventory','spells','character_id','player_id','online'] if k in self.state})
        self.state=state;return state
    def walk(self,direction):
        direction=int(direction)
        if direction not in range(4):raise EOError('EO movement must be one cardinal tile (0 down,1 left,2 up,3 right)')
        if not self.state or not self.state.get('self'):raise EOError('Enter a character before movement')
        wait=0.43-(time.monotonic()-self.last_walk)
        if wait>0:time.sleep(wait)
        self.timestamp+=40;me=self.state['self'];dx,dy=[(0,1),(-1,0),(0,-1),(1,0)][direction]
        self.send(6,8,number(direction,1)+number(self.timestamp,3)+number(me['x']+dx,1)+number(me['y']+dy,1));self.last_walk=time.monotonic()
        time.sleep(0.07);return self.refresh()
    def attack(self,direction=None):
        if direction is None:direction=self.state['self']['direction']
        direction=int(direction)
        if direction not in range(4):raise EOError('Invalid attack direction')
        wait=0.9-(time.monotonic()-self.last_attack)
        if wait>0:time.sleep(wait)
        self.send(7,8,number(direction,1));time.sleep(0.14)
        self.timestamp+=60;self.send(11,10,number(direction,1)+number(self.timestamp,3));self.last_attack=time.monotonic();time.sleep(0.1)
        state=self.refresh();state['attack_sent']=True;return state
    def paperdoll(self):
        self.send(30,1,number(self.player_id,2));r=Reader(self.wait(30,3))
        for _ in range(6):r.text()
        r.take(5)
        slots=['boots','accessory','gloves','belt','armor','necklace','head','offhand','weapon','ring1','ring2','armlet1','armlet2','bracer1','bracer2']
        self.equipment={key:r.num(2) for key in slots}
        return self.equipment
    def pickup(self,uid):
        self.send(14,27,number(int(uid),2));self.wait(14,27,timeout=2);return self.refresh()
    def equip(self,item_id,remove=False,subloc=0):
        self.send(30,4 if remove else 7,number(int(item_id),2)+number(int(subloc),1))
        self.wait(30,4 if remove else 5,timeout=2);self.paperdoll();return self.refresh()
    def apply_event(self,f,a,p):
        event={'family':f,'action':a,'bytes':len(p)}
        if (f,a)==(14,24):
            r=Reader(p);item=r.num(2);amount=r.num(3);remaining=r.num(4);uid=r.num(2)
            self.inventory=[i for i in self.inventory if i['id']!=item]
            if remaining:self.inventory.append({'id':item,'amount':remaining})
            event.update(kind='drop',uid=uid,item_id=item,amount=amount)
        elif (f,a)==(14,27):
            r=Reader(p);uid=r.num(2);item=r.num(2);amount=r.num(3);self.inventory_add(item,amount)
            event.update(kind='pickup',uid=uid,item_id=item,amount=amount)
        elif f==30 and a in (4,5):
            r=Reader(p);r.take(14);item=r.num(2)
            if a==5:
                remaining=r.num(3);self.inventory=[i for i in self.inventory if i['id']!=item]
                if remaining:self.inventory.append({'id':item,'amount':remaining})
            else:self.inventory_add(item,1)
            event.update(kind='unequip' if a==4 else 'equip',item_id=item)
        elif f==26 and ((a==3 and len(p)>=11) or (a in (2,16) and len(p)>=18)):
            r=Reader(p);pid=r.num(2);direction=r.num();index=r.num(2)
            if a==3:event.update(kind='npc_damage',player_id=pid,npc_index=index,damage=r.num(3),hp_percent=r.num(2))
            else:
                uid=r.num(2);item=r.num(2);x=r.num();y=r.num();amount=r.num(4);damage=r.num(3)
                event.update(kind='npc_killed',player_id=pid,npc_index=index,damage=damage,drop={'uid':uid,'id':item,'x':x,'y':y,'amount':amount})
        self.events.append(event);self.events=self.events[-100:]
    def inventory_add(self,item,amount):
        for row in self.inventory:
            if row['id']==item:row['amount']+=amount;return
        self.inventory.append({'id':item,'amount':amount})
    def snapshot(self):
        if not self.state:raise EOError('No active world session')
        def player(row):
            row=dict(row);row['id']=row['player_id'];row['max_hp']=row['maxhp'];row['max_tp']=row['maxtp'];return row
        me=player(self.state['self']) if self.state.get('self') else None
        if me:me.update(character_id=self.character_id,inventory=self.inventory,equipment=getattr(self,'equipment',{}))
        events=self.events;self.events=[]
        return {'online':True,'player':me,'players':[player(c) for c in self.state['characters']],
                'npcs':self.state['npcs'],'items':self.state['items'],'events':events,'map_id':self.state['map_id']}

    def pump(self):
        f,a,p=self.receive()
        if (f,a)==(1,8):
            r=Reader(p);self.seq_start=r.num(2)-r.num();self.send(1,240,b'k')
        else:self.apply_event(f,a,p)

    def drop(self,item_id,amount=1):
        self.send(14,24,number(int(item_id),2)+number(int(amount),3)+b'\xff\xff')
        r=Reader(self.wait(14,24,timeout=2));r.take(9);uid=r.num(2)
        self.refresh();return uid
