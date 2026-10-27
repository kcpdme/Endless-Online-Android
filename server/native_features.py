"""Original EO services omitted by the first mobile slice.

Native packets remain authoritative. Contexts bind to the actual NPC/tile/map;
account actions bind to the authenticated account and owned character list.
"""
import time
from eo_session import EOError, Reader, number, string
from native_settings import settings
from skills import npc_types

def player_name(value):
    value=str(value).strip().lower()
    if not value.isascii() or not value.isalpha() or not 4<=len(value)<=12:raise EOError('Enter a character name with 4–12 letters')
    return value

def message_text(value,limit=256,multiline=False):
    value=str(value).strip()
    if multiline:value=value.replace('\r\n','\n').replace('\r','\n')
    if not value or len(value)>limit or any((ord(c)<32 and not(multiline and c in '\n\t')) or ord(c)==255 for c in value):raise EOError('Enter 1–%d printable characters'%limit)
    try:value.encode('latin1')
    except UnicodeEncodeError:raise EOError('Use classic Latin characters')
    return value

class NativeFeaturesMixin:
    feature_context=None

    def _feature_reply(self,kind,**fields):
        result=self.snapshot();result['feature']=dict(kind=kind,**fields);return result

    def _feature_barrier(self):
        # Native handlers with no reply still run before this self-inspection.
        self.send(30,1,number(self.player_id,2));self._wait_service(30,{3})

    def feature_open(self,kind,npc_index=0,x=0,y=0,player_id=0):
        self._standing()
        if kind in ('law','priest','reset'):
            typ={'law':13,'priest':12,'reset':14}[kind]
            npc=next((n for n in self.state['npcs'] if n['index']==int(npc_index)),None)
            if not npc or npc_types().get(npc['id'])!=typ:raise EOError('Choose the correct nearby service NPC')
            context=dict(kind=kind,npc_index=npc['index'],x=npc['x'],y=npc['y'],map_id=self.state['map_id'])
            self._near_service(context)
            if kind=='reset':
                self.skillmaster_open(npc['index']);self.feature_context=context
                from balance_rules import profile
                return self._feature_reply(kind,notice='Rebuild attributes and skill training for free. Learned spells and all invested points are kept.' if profile() else 'Reset all attributes and learned skills. Level-based points are refunded.')
            family=47 if kind=='law' else 46
            self.send(family,13,number(npc['index'],2));r=Reader(self._wait_service(family,{13,3}))
            if len(r.rest())==2:raise EOError(self._priest_error(r.num(2)))
            r.num(3 if kind=='law' else 4);self.feature_context=context
            cfg=settings({'MarriagePrice':'500','DivorcePrice':'10000','WeddingMinLevel':'5','WeddingOutfitMale':'133','WeddingOutfitFemale':'163'})
            return self._feature_reply(kind,prices=cfg,notice='Enter your partner’s character name.' if kind=='law' else 'Both partners must have approval, be present and wear wedding outfits. Minimum level '+str(cfg['WeddingMinLevel'])+'.')
        if kind in ('board','jukebox'):
            x,y=int(x),int(y)
            from native_settings import map_specs
            spec=map_specs(self.state['map_id']).get((x,y),-1)
            if (kind=='board' and spec not in range(20,28)) or (kind=='jukebox' and spec!=28):raise EOError('Choose the correct map object')
            context=dict(kind=kind,x=x,y=y,map_id=self.state['map_id']);self._near(context,11)
            self.feature_context=context
            if kind=='board':
                context['board_id']=spec-20;self.send(43,13,number(context['board_id'],2))
                data=self._board_list(self._wait_service(43,{13}));context['posts']=data['posts']
                return self._feature_reply(kind,**data)
            self.send(21,13,number(x,1)+number(y,1));r=Reader(self._wait_service(21,{13}));r.num(2)
            cfg=settings({'JukeboxPrice':'25','JukeboxSongs':'20'})
            return self._feature_reply(kind,price=int(str(cfg['JukeboxPrice']).replace(',','')),songs=int(cfg['JukeboxSongs']),owner=r.rest().decode('latin1'),notice='Choose a song to play for everyone on this map.')
        if kind=='book':
            pid=int(player_id) or self.player_id
            if not any(c['player_id']==pid for c in [self.state['self']]+self.state['characters']):raise EOError('This player is no longer nearby')
            self.send(51,1,number(pid,2));r=Reader(self._wait_service(51,{3}))
            data={k:r.text() for k in ['name','home','partner','title','guild','rank']};r.num(2);data.update(class_id=r.num(),gender=r.num());r.take(3)
            data['quests']=[]
            while r.rest():data['quests'].append(r.text())
            return self._feature_reply(kind,**data)
        if kind not in ('social','emotes','report','find'):raise EOError('Unknown service')
        return self._feature_reply(kind,whispers=getattr(self,'whispers_enabled',True))

    @staticmethod
    def _board_list(payload):
        r=Reader(payload);board_id=r.num()-1;count=r.num();posts=[]
        for _ in range(count):
            ident=r.num(2)
            if r.take(1)!=b'\xff':raise EOError('Malformed board list')
            posts.append(dict(id=ident,author=r.text().strip(),subject=r.text()))
        if r.rest():raise EOError('Malformed board tail')
        return dict(board_id=board_id,posts=posts)

    @staticmethod
    def _priest_error(code):
        return {1:'Wear your wedding outfit.',2:'You need a higher level.',3:'Your partner must be here.',4:'Your partner needs a wedding outfit.',5:'The priest is busy.',6:'Do you take this partner?',7:'Your partner is already married.',8:'Both partners need matching marriage approval.'}.get(code,'The priest declined this request.')

    def feature_action(self,kind,action,ident=0,text='',body=''):
        self._standing();ident=int(ident)
        wedding_reply=kind=='priest' and action in ('accept','vow')
        if wedding_reply:
            pending=getattr(self,'wedding_pending',None)
            if not pending or pending['action']!=action or pending['map_id']!=self.state['map_id'] or pending['until']<time.monotonic():raise EOError('No current wedding invitation or vow request')
        if kind in ('law','priest','board','jukebox','reset') and not wedding_reply:
            context=self.feature_context
            if not context or context['kind']!=kind:raise EOError('Open this service first')
            if kind in ('board','jukebox'):self._near(context,11)
            else:self._near_service(context)
            if 'npc_index' in context:
                npc=next((n for n in self.state['npcs'] if n['index']==context['npc_index']),None)
                if not npc or (npc['x'],npc['y'])!=(context['x'],context['y']):raise EOError('Open the service again nearby')
        if kind=='reset' and action=='reset':
            self.send(16,25,number(self.skillmaster['id'],4));r=Reader(self._wait_service(16,{25}))
            keys=['stat_points','skill_points','hp','max_hp','tp','max_tp','max_sp','strength','intelligence','wisdom','agility','constitution','charisma','min_damage','max_damage','accuracy','evade','armor']
            values={k:r.num(2) for k in keys}
            if r.rest():raise EOError('Malformed reset acknowledgement')
            from eo_stats import update
            from balance_rules import profile
            preserve=bool(profile())
            update(self,values);self.spells=[dict(s,level=0) for s in self.spells] if preserve else [];self.casting=None
            return self._feature_reply(kind,notice='Attributes and skill training refunded. Learned spells are kept.' if preserve else 'Attributes and skills reset. Your points are available again.',reset=True,preserved_spells=preserve)
        if kind=='law' and action in ('approve','divorce'):
            name=player_name(text)
            if name==self.state['self']['name'].lower():raise EOError('Choose another character')
            self.send(47,1,number(1 if action=='approve' else 2,1)+number(0,4)+b'\xff'+name.encode('ascii'))
            r=Reader(self._wait_service(47,{3}));code=r.num(2)
            if code!=3:raise EOError({1:'You are already married.',2:'You are not married.',4:'Not enough Gold.',5:'Enter your current partner’s name.',6:'This service is busy.'}.get(code,'Marriage request declined'))
            self._set_amount(1,r.num(4));self.feature_context=None
            return self._feature_reply(kind,notice='Marriage approval recorded.' if action=='approve' else 'Divorce completed.')
        if kind=='priest' and action in ('request','accept','vow'):
            if action=='request':self.send(46,1,number(0,4)+b'\xff'+player_name(text).encode('ascii'))
            elif action=='accept':self.send(46,2)
            else:self.send(46,10,number(0,4))
            if wedding_reply:self.wedding_pending=None
            # Invitations / vows complete asynchronously and must not block the ceremony.
            self._feature_barrier()
            return self._feature_reply(kind,notice='Request sent. Follow the priest’s messages.')
        if kind=='board':
            header=number(context['board_id'],2)
            if action=='read':
                if not 0<ident<253**2:raise EOError('Select a post')
                self.send(43,9,header+number(ident,2));r=Reader(self._wait_service(43,{8}));post_id=r.num(2)
                if post_id!=ident:raise EOError('Unexpected post reply')
                return self._feature_reply(kind,post_id=post_id,body=r.rest().decode('latin1'))
            if action=='post':
                subject=message_text(text,64);content=message_text(body,multiline=True)
                self.send(43,6,header+b'\xff'+subject.encode('latin1')+b'\xff'+content.encode('latin1')+b'\xff')
            elif action=='remove':
                if int(self.stats.get('admin',0))<=0:raise EOError('Admin moderation is required')
                if not 0<ident<253**2:raise EOError('Select a post')
                self.send(43,4,header+number(ident,2))
            else:raise EOError('Unknown board action')
            data=self._board_list(self._wait_service(43,{13}))
            previous={p['id'] for p in context.get('posts',[])};context['posts']=data['posts']
            if action=='post' and not any(p['id'] not in previous for p in data['posts']):raise EOError('Post was not accepted. Check the board’s posting limits; your message is retained.')
            if action=='remove' and any(p['id']==ident for p in data['posts']):raise EOError('The server did not permit removal of this post.')
            return self._feature_reply(kind,**data)
        if kind=='jukebox' and action=='play':
            maximum=int(settings({'JukeboxSongs':'20'})['JukeboxSongs'])
            if not 0<=ident<=maximum:raise EOError('Choose a listed song')
            self.send(21,15,number(context['x'],1)+number(context['y'],1)+number(ident,2))
            r=Reader(self._wait_service(21,{3,5}))
            if len(r.rest())!=4:raise EOError('Jukebox busy or not enough Gold. Nothing was purchased.')
            self._set_amount(1,r.num(4));return self._feature_reply(kind,notice='Song purchased. Playing for this map.')
        if kind=='emotes' and action=='emote':
            if ident not in tuple(range(1,11))+(14,):raise EOError('Choose a listed emote')
            self.send(9,21,number(ident,1));self._feature_barrier()
            self.events.append(dict(kind='player_emote',player_id=self.player_id,emote=ident));return self._feature_reply(kind,notice='')
        if kind=='social' and action=='whispers':
            if ident not in (0,1):raise EOError('Choose on or off')
            self.send(17,4 if ident else 8,b'n' if ident else b'y');self._feature_barrier();self.whispers_enabled=bool(ident)
            return self._feature_reply(kind,whispers=bool(ident),notice='Whispers enabled.' if ident else 'Whispers disabled for this session.')
        if kind=='find' and action=='find':
            name=player_name(text);self.send(22,2,name.encode('ascii'))
            r=Reader(self._wait_service(22,{240,241,242}));status=getattr(self,'find_status','unavailable')
            return self._feature_reply(kind,notice=name+': '+status)
        if kind=='report' and action in ('help','report'):
            now=time.monotonic()
            if now-getattr(self,'last_help_request',0)<30:raise EOError('Wait 30 seconds between help requests')
            payload=message_text(body,multiline=True).encode('latin1')
            if action=='report':payload=player_name(text).encode('ascii')+b'\xff'+payload
            self.send(48,20 if action=='help' else 21,payload);self._feature_barrier();self.last_help_request=now
            return self._feature_reply(kind,notice='Sent to the server’s admin support system.')
        raise EOError('Unknown service action')

    def delete_character(self,ident,name):
        if not getattr(self,'account_name','') or self.state:raise EOError('Return to character selection first')
        ident=int(ident);name=player_name(name)
        row=next((c for c in self.characters if c['id']==ident and c['name'].lower()==name),None)
        if not row:raise EOError('Select your character and type its exact name')
        self.send(3,9,number(ident,4));r=Reader(self.wait(3,8));ticket=r.num(2)
        if r.num(4)!=ident:raise EOError('Deletion identity mismatch')
        self.send(3,4,number(ticket,2)+number(ident,4));r=Reader(self.wait(3,3))
        if r.num(2)!=6:raise EOError('Character deletion declined')
        self.characters=self.parse_characters(r);return dict(characters=self.characters,deleted=name)

    def change_password(self,old,new):
        if not getattr(self,'account_name','') or self.state:raise EOError('Return to character selection first')
        if not 6<=len(str(new))<=64 or any(ord(c)<33 or ord(c)>126 for c in str(new)):raise EOError('Use a new password of 6–64 printable ASCII characters')
        if not 1<=len(str(old))<=64:raise EOError('Enter your current password')
        self.send(2,5,string(self.account_name)+string(old)+string(new));r=Reader(self.wait(2,3,timeout=15))
        if r.num(2)!=6:raise EOError('Password change declined. Check your current password.')
        return dict(changed=True)

    def apply_feature_packet(self,f,a,p):
        if not self.state:return
        r=Reader(p)
        if f==22 and a in (240,241,242):
            self.find_status={240:'not available',241:'nearby on this map',242:'online on another map'}[a]
        elif f==21 and a in (8,10):
            track=r.num(1 if a==8 else 2);self.events[-1].update(kind='jukebox_music',track=track);self.dirty=True
        elif (f,a)==(46,1):
            r.num(2);name=r.rest().decode('latin1');self.wedding_pending=dict(action='accept',map_id=self.state['map_id'],until=time.monotonic()+30);self.events[-1].update(kind='wedding_invite',name=name);self.dirty=True
        elif (f,a)==(46,3):
            code=r.num(2)
            if code==6:self.wedding_pending=dict(action='vow',map_id=self.state['map_id'],until=time.monotonic()+12)
            self.events[-1].update(kind='wedding_notice',code=code,message=self._priest_error(code));self.dirty=True
        elif (f,a)==(47,3) and len(p)==2 and r.num(2)==7:
            self.events[-1].update(kind='wedding_notice',code=7,message='Your partner has ended the marriage.');self.dirty=True
