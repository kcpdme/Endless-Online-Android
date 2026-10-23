"""Native Babs hair service: original prices, appearance and Gold acknowledgements."""
from functools import lru_cache
from eo_session import EOError,Reader,number
from services import runtime_path
from skills import npc_types

@lru_cache(maxsize=1)
def barber_settings():
    settings=dict(BarberBase=0,BarberStep=200,MaxHairStyle=20,MaxHairColor=9)
    runtime=runtime_path().resolve();seen=set()
    def read(path):
        path=path.resolve()
        if path in seen or not path.is_relative_to(runtime) or not path.is_file():return
        seen.add(path)
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=');key=key.strip();value=value.split('#',1)[0].strip()
            if not sep:continue
            if key in ('INCLUDE','REQUIRE'):read(runtime/value)
            elif key in settings:settings[key]=int(value.replace(',',''))
    read(runtime/'config.ini');read(runtime/'config.local.ini');return settings

class BarberMixin:
    barber=None
    def barber_open(self,npc_index):
        self._standing();npc_index=int(npc_index)
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc or npc_types().get(npc['id'])!=10:raise EOError('Select a nearby haircutter')
        context=dict(npc_index=npc_index,npc_id=npc['id'],map_id=self.state['map_id'])
        self._near_service(context);self.barber=None
        self.send(38,13,number(npc_index,2));r=Reader(self._wait_service(38,{13}));token=r.num(4)
        if r.rest():raise EOError('Invalid haircutter acknowledgement')
        settings=barber_settings()
        self.barber=dict(context,token=token,price=settings['BarberBase']+max(1,int(self.stats.get('level',1)))*settings['BarberStep'],max_style=min(20,settings['MaxHairStyle']),max_color=min(9,settings['MaxHairColor']))
        self.shop=None;self.bank=None;self.locker=None;self.chest=None;self.skillmaster=None;self.guild=None;self.inn=None;self.quest_dialog=None;self.quest_context=None
        return self.snapshot()
    def barber_buy(self,style,color):
        self._near_service(self.barber);style,color=int(style),int(color)
        if not 0<=style<=self.barber['max_style'] or not 0<=color<=self.barber['max_color']:raise EOError('Choose an offered hair style and color')
        me=self.state['self']
        if (style,color)==(me.get('hairstyle'),me.get('haircolor')):raise EOError('You already have this hairstyle and color')
        if self.item_amount(1)<self.barber['price']:raise EOError('You need %d Gold for this haircut'%self.barber['price'])
        # The pinned etheos handler reads two chars directly (no session prefix).
        self.send(38,11,number(style,1)+number(color,1));self._wait_service(38,{5})
        return self.snapshot()
    def barber_close(self):
        self.barber=None;return self.snapshot()
    def apply_barber_packet(self,f,a,p):
        if (f,a)!=(38,5):return
        r=Reader(p);gold=r.num(4);pid=r.num(2);slot=r.num();r.num();style=r.num();color=r.num()
        if r.rest() or pid!=self.player_id or slot!=2 or not 0<=style<=20 or not 0<=color<=9:raise EOError('Invalid haircut receipt')
        self._set_amount(1,gold);self.state['self'].update(hairstyle=style,haircolor=color)
        self.events[-1].update(kind='haircut',player_id=pid,hairstyle=style,haircolor=color)
        self.dirty=True
