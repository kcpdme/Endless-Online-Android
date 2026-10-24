"""Native inn sleep and citizenship: questions, registration, removal and home lookup."""
from functools import lru_cache
from eo_session import EOError, Reader, number, string
from eo_stats import update
from skills import npc_types
from services import runtime_path

@lru_cache(maxsize=1)
def inn_homes():
    """Only public town/location metadata leaves the server; answers stay native."""
    runtime=runtime_path().resolve();settings={'HomeFile':'./data/home.ini'};seen=set()
    def read(path):
        path=path.resolve()
        if path in seen or not path.is_relative_to(runtime) or not path.is_file():return
        seen.add(path)
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=');key=key.strip();value=value.split('#',1)[0].strip()
            if not sep or key.startswith('#'):continue
            if key in ('INCLUDE','REQUIRE'):read(runtime/value)
            elif key=='HomeFile':settings[key]=value
    read(runtime/'config.ini');read(runtime/'config.local.ini')
    path=(runtime/settings['HomeFile']).resolve()
    if not path.is_relative_to(runtime):raise EOError('Inn home configuration is unavailable')
    rows={}
    for line in path.read_text().splitlines():
        key,sep,value=line.partition('=')
        if sep and not key.lstrip().startswith('#'):rows[key.strip()]=value.split('#',1)[0].strip()
    result={}
    for key,value in rows.items():
        if not key.endswith('.innkeeper'):continue
        home=key.rsplit('.',1)[0];location=[int(v.strip()) for v in rows[home+'.location'].split(',')]
        result[int(value)]=dict(id=home,name=rows.get(home+'.name',home),map_id=location[0],x=location[1],y=location[2])
    return result

class InnsMixin:
    inn=None

    def _inn_sync_home(self):
        # Self Paperdoll is a native ordering barrier and reports the effective home.
        self.send(30,1,number(self.player_id,2));r=Reader(self._wait_service(30,{3}))
        fields=[r.text() for _ in range(6)]
        if r.num(2)!=self.player_id:raise EOError('Home response was for another player')
        home=next((h for h in inn_homes().values() if h['name']==fields[1]),dict(name=fields[1]))
        self.stats['home']=fields[1]
        if self.inn:self.inn['current_home']=dict(home)
        return home

    def inn_open(self,npc_index):
        self._standing();npc_index=int(npc_index)
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc or npc_types().get(npc['id'])!=7:raise EOError('Select a nearby innkeeper')
        context=dict(npc_index=npc_index,npc_id=npc['id'],map_id=self.state['map_id'],x=npc['x'],y=npc['y'])
        self._near_service(context);self.inn=context
        try:
            self.send(49,13,number(npc_index,2));self._wait_service(49,{13})
            if not self.inn or 'vendor_id' not in self.inn:raise EOError('This inn has no registration data')
            self.inn['home']=dict(inn_homes().get(self.inn['vendor_id'],{}))
            self._inn_sync_home()
        except Exception:self.inn=None;raise
        self.quest_context=None;self.quest_dialog=None
        self.shop=None;self.bank=None;self.locker=None;self.chest=None;self.skillmaster=None;self.guild=None;self.barber=None
        return self.snapshot()

    def inn_register(self,answers):
        self._near_service(self.inn)
        if not isinstance(answers,list) or len(answers)!=3 or any(not isinstance(a,str) for a in answers):raise EOError('Answer all three citizenship questions')
        answers=[a.strip() for a in answers]
        if any(not a or len(a)>80 or any(ord(c)<32 or ord(c)>126 for c in a) for a in answers):raise EOError('Use a short answer in each citizenship field')
        if len(self.inn.get('questions',[]))!=3:raise EOError('Open the innkeeper registration again')
        payload=number(self.inn['session_id'],2)+b'\xff'+number(self.inn['vendor_id'],2)+b'\xff'+string(answers[0])+string(answers[1])+answers[2].encode('ascii')
        self.send(49,3,payload)
        try:self._wait_service(49,{3})
        except EOError as exc:raise EOError('Registration was not accepted. If you already have citizenship, give it up at your current inn first.') from exc
        if self.inn.get('registration',{}).get('accepted'):
            self._inn_sync_home()
            self.inn['notice']='Citizenship registered. Your death respawn is now '+self.inn['current_home']['name']+'.'
        return self.snapshot()

    def inn_remove(self):
        self._near_service(self.inn)
        self.send(49,4,number(self.inn['vendor_id'],2));self._wait_service(49,{4})
        if self.inn.get('removed'):
            self._inn_sync_home()
            self.inn['notice']='Citizenship given up. Your death respawn is now '+self.inn['current_home']['name']+'.'
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
            elif a==3:
                wrong=r.num()
                if r.rest() or wrong not in range(4):raise EOError('Invalid native citizenship reply')
                self.inn['registration']=dict(accepted=wrong==0,wrong_answers=wrong)
                self.inn['notice']=('Citizenship registered.' if wrong==0 else f'{wrong} answer'+(' is' if wrong==1 else 's are')+' incorrect. Please try again.')
                self.events[-1].update(kind='inn_registration',accepted=wrong==0,wrong_answers=wrong)
            elif a==4:
                removed=r.num()
                if r.rest() or removed not in (0,1):raise EOError('Invalid native citizenship removal reply')
                self.inn['removed']=bool(removed)
                self.inn.pop('registration',None)
                self.inn['notice']='Citizenship given up.' if removed else 'You are not registered at this inn. Visit the innkeeper of your current town to give up citizenship.'
                self.events[-1].update(kind='inn_citizenship_removed',removed=bool(removed))
            else:return
        else:return
        self.dirty=True
