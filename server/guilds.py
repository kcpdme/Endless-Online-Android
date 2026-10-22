"""Guild Bob's native EO flows. Membership, gold and approvals belong to etheos."""
from functools import lru_cache
import socket
import time
from eo_session import EOError, Reader, number, string
from skills import npc_types
from services import runtime_path

REPLIES = {1:'Guild service is busy',2:'Guild tag or name was not approved',3:'You already belong to a guild',4:'Not enough founding members',5:'Guild tag or name already exists',9:'The recruiter is offline',10:'The recruiter must be on this map',11:'The recruiter belongs to another guild',12:'That member cannot recruit',14:'The applicant is no longer present',15:'The guild bank needs more Gold to recruit',16:'Applicant accepted',17:'Guild not found',18:'Guild updated',19:'Rank names updated',20:'You cannot remove this leader',21:'That character is not a guild member',22:'Member removed',23:'You cannot change this founder or leader',24:'That character is not a guild member'}

@lru_cache(maxsize=1)
def guild_settings():
    settings=dict(GuildPrice=50000,GuildCreateMembers=10,RecruitCost=1000,GuildMinDeposit=1000,GuildBankMax=2000000000,GuildMaxNameLength=24,GuildMaxDescLength=240,GuildMaxRankLength=16,GuildEditRank=1,GuildKickRank=1,GuildPromoteRank=1,GuildDemoteRank=1,GuildPromoteSameRank=1,GuildRecruitRank=2,GuildDisbandRank=0,GuildMultipleFounders=1)
    runtime=runtime_path().resolve();seen=set()
    def read(path):
        path=path.resolve()
        if path in seen or not path.is_relative_to(runtime) or not path.is_file():return
        seen.add(path)
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=');key=key.strip();value=value.split('#',1)[0].strip()
            if not sep:continue
            if key in ('INCLUDE','REQUIRE'):read(runtime/value)
            elif key in settings:settings[key]={'yes':1,'no':0,'true':1,'false':0}.get(value.lower(),value.replace(',',''))
    read(runtime/'config.ini');read(runtime/'config.local.ini')
    return {k:int(v) for k,v in settings.items()}

class GuildsMixin:
    guild=None
    guild_creation=None
    guild_invitation=None
    guild_requests=None
    guild_notice=''

    def _guild_wait(self, actions, codes=(), timeout=4):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            self.sock.settimeout(max(.1,deadline-time.monotonic()))
            try:f,a,p=self.receive()
            except socket.timeout:raise EOError('No guild acknowledgement. Refresh before retrying; the server may have applied the action.')
            finally:self.sock.settimeout(8)
            if self.control_packet(f,a,p):continue
            self.apply_event(f,a,p)
            if f!=39:continue
            if a==3:
                code=Reader(p).num(1 if len(p)==1 else 2)
                if code not in codes:continue  # Invitations/other async replies are not this transaction's ACK.
                if code not in (6,16,18,19,22):raise EOError(REPLIES.get(code,'Guild request declined'))
                return p
            if a in actions:return p
        raise EOError('Guild request timed out; refresh before retrying')

    def guild_open(self, npc_index):
        self._standing();npc_index=int(npc_index)
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc or npc_types().get(npc['id'])!=11:raise EOError('Select a nearby guild NPC')
        context=dict(npc_index=npc_index,npc_id=npc['id'],map_id=self.state['map_id'])
        self._near_service(context);self.guild=None
        self.send(39,13,number(npc_index,2))
        token=Reader(self._guild_wait({13})).num(3)
        self.guild=dict(context,token=token,settings=guild_settings())
        self.shop=None;self.bank=None;self.locker=None;self.chest=None;self.skillmaster=None
        self.quest_dialog=None;self.quest_context=None;self.inn=None
        self._guild_sync()
        return self.snapshot()

    def _guild_token(self):
        self._near_service(self.guild)
        return number(self.guild['token'],4)

    def _guild_text(self, value, kind):
        value=str(value).strip();settings=guild_settings()
        if kind=='tag':valid=2<=len(value)<=3 and value.isascii() and value.isalpha();value=value.upper()
        elif kind=='name':valid=4<=len(value)<=settings['GuildMaxNameLength'] and value.isascii() and all(c.isalpha() or c==' ' for c in value);value=value.lower()
        elif kind=='character':valid=4<=len(value)<=12 and value.isascii() and value.isalpha();value=value.lower()
        elif kind=='rank':valid=len(value)<=settings['GuildMaxRankLength'] and value.isascii() and all(c.isalpha() or c==' ' for c in value)
        else:valid=len(value)<=settings['GuildMaxDescLength'] and value.isascii() and all(c.isalnum() or c in ' @_-. ' for c in value)
        if not valid:raise EOError('Invalid guild '+kind+': check length and allowed letters/spaces'+(' or numbers, @ _ - .' if kind=='description' else ''))
        return value

    def _guild_read(self, query, members=False):
        query=str(query).strip()
        if not 2<=len(query)<=guild_settings()['GuildMaxNameLength'] or not query.isascii() or any(not(c.isalnum() or c==' ') for c in query):raise EOError('Enter a guild tag or name')
        if len(query)<=3:query=query.upper()
        action=20 if members else 21
        self.send(39,action,self._guild_token()+query.encode('ascii'))
        r=Reader(self._guild_wait({action},{17}))
        if members:
            count=r.num(2)
            if r.take(1)!=b'\xff':raise EOError('Invalid native guild member list')
            rows=[]
            for _ in range(count):
                rank=r.num()
                if r.take(1)!=b'\xff':raise EOError('Invalid native guild member')
                rows.append(dict(rank=rank,name=r.text(),title=r.text()))
            result=dict(query=query,members=rows)
        else:
            result=dict(zip(('name','tag','created','description','bank'),[r.text() for _ in range(5)]))
            result['ranks']=[r.text().strip() for _ in range(9)];count=r.num(2)
            if r.take(1)!=b'\xff':raise EOError('Invalid native guild information')
            leaders=[]
            for _ in range(count):
                role=r.num()
                if r.take(1)!=b'\xff':raise EOError('Invalid native guild leader')
                leaders.append(dict(role=role,name=r.text()))
            result.update(query=query,leaders=leaders)
        if r.rest():raise EOError('Unexpected native guild data')
        return result

    def guild_lookup(self, query, members=False):
        result=self._guild_read(query,members)
        self.guild=dict(self.guild,result=result)
        return self.snapshot()

    def _guild_sync(self):
        # Paperdoll self-query is a native ordering barrier for silent Leave/Disband.
        # It also catches membership/rank changes made by another player.
        self.send(30,1,number(self.player_id,2));r=Reader(self._wait_service(30,{3}))
        fields=[r.text() for _ in range(6)]
        if r.num(2)!=self.player_id:raise EOError('Guild membership response was for another player')
        self.stats.update(guild=fields[4],guild_rank=fields[5])
        if not fields[4]:
            self.stats['guild_tag']='';self.guild['membership']=None
        else:
            info=self._guild_read(fields[4]);members=self._guild_read(info['tag'],True)['members']
            name=self.state['self']['name'].lower()
            me=next((row for row in members if row['name'].lower()==name),None)
            if not me:raise EOError('Guild membership changed; refresh the guild window')
            self.guild['membership']=dict(me,tag=info['tag'],guild_name=info['name'],bank=int(info['bank']),description=info['description'],ranks=info['ranks'])
            self.stats['guild_tag']=info['tag']

    def guild_refresh(self):
        self._guild_token();self._guild_sync();return self.snapshot()

    def _guild_member(self, permission=None):
        self._guild_token();self._guild_sync();member=self.guild.get('membership')
        if not member:raise EOError('Join a guild first')
        if permission and member['rank']>guild_settings()[permission]:raise EOError('Your guild rank cannot perform this action')
        return member

    def guild_begin(self, tag, name):
        token=self._guild_token();self._guild_sync();settings=guild_settings()
        if self.guild.get('membership'):raise EOError('You already belong to a guild')
        if settings['GuildCreateMembers']<=0:raise EOError('Guild creation is disabled by this server')
        if self.item_amount(1)<settings['GuildPrice']:raise EOError('You need %d Gold to found a guild'%settings['GuildPrice'])
        tag=self._guild_text(tag,'tag');name=self._guild_text(name,'name')
        previous=self.guild_creation
        self.guild_creation=dict(tag=tag,name=name,members=[self.state['self']['name']],ready=False)
        try:
            self.send(39,1,token+b'\xff'+string(tag)+string(name))
            self._guild_wait(set(),{1,2,3,4,5,6})
        except Exception:self.guild_creation=previous;raise
        self.guild_notice='Founding invitations sent to guildless players on this map'
        return self.snapshot()

    def guild_found(self, description):
        token=self._guild_token();creation=self.guild_creation
        if not creation or not creation['ready']:raise EOError('Wait for the server to confirm enough founding members')
        description=self._guild_text(description,'description')
        self.send(39,6,token+b'\xff'+string(creation['tag'])+string(creation['name'])+string(description))
        self._guild_wait({6},{1,2,3,4,5});self._guild_sync()
        return self.snapshot()

    def guild_support(self, accept):
        if not isinstance(accept,bool):raise EOError('Choose Accept or Dismiss')
        self._standing();invite=self.guild_invitation
        if not invite or invite['map_id']!=self.state['map_id']:raise EOError('This founding invitation is no longer on your map')
        if accept:self.send(39,2)
        self.guild_invitation=None
        self.guild_notice='Support sent. Membership begins only when the founder completes creation.' if accept else 'Founding invitation dismissed'
        return self.snapshot()

    def guild_join(self, tag, recruiter):
        token=self._guild_token();self._guild_sync()
        if self.guild.get('membership'):raise EOError('You already belong to a guild')
        tag=self._guild_text(tag,'tag');recruiter=self._guild_text(recruiter,'character')
        self.send(39,8,token+b'\xff'+string(tag)+string(recruiter))
        self.guild_notice='Request sent; waiting for the recruiter to accept'
        # Native success is delivered to the recruiter, not this requester.
        return self.snapshot()

    def guild_recruit(self, player_id, accept):
        if not isinstance(accept,bool):raise EOError('Choose Accept or Dismiss')
        self._standing();player_id=int(player_id)
        request=next((row for row in (self.guild_requests or []) if row['player_id']==player_id),None)
        if not request or request['map_id']!=self.state['map_id']:raise EOError('This application is no longer on your map')
        if accept:
            self.send(39,10,number(player_id,2));self._guild_wait(set(),{14,15,16})
        self.guild_requests=[row for row in self.guild_requests if row['player_id']!=player_id]
        if self.guild:self._guild_sync()
        self.guild_notice='Applicant accepted' if accept else 'Application dismissed'
        return self.snapshot()

    def guild_deposit(self, amount):
        member=self._guild_member();amount=int(amount);settings=guild_settings()
        if not settings['GuildMinDeposit']<=amount<=min(self.item_amount(1),settings['GuildBankMax']-member['bank']):raise EOError('Check the minimum deposit, your Gold and guild bank capacity')
        self.send(39,11,self._guild_token()+number(amount,4));self._guild_wait({11});self._guild_sync()
        self.guild_notice='Gold deposited in the guild bank';return self.snapshot()

    def guild_description(self, description):
        self._guild_member('GuildEditRank');description=self._guild_text(description,'description')
        self.send(39,5,self._guild_token()+number(1,2)+description.encode('ascii'));self._guild_wait(set(),{18});self._guild_sync()
        return self.snapshot()

    def guild_ranks(self, ranks):
        self._guild_member('GuildEditRank');ranks=str(ranks).split(',')
        if len(ranks)!=9:raise EOError('Supply all nine guild rank names')
        ranks=[self._guild_text(rank,'rank') for rank in ranks]
        self.send(39,5,self._guild_token()+number(2,2)+b''.join(string(rank) for rank in ranks));self._guild_wait(set(),{19});self._guild_sync()
        return self.snapshot()

    def guild_rank(self, name, rank):
        member=self._guild_member();name=self._guild_text(name,'character');rank=int(rank);settings=guild_settings()
        target=next((row for row in self._guild_read(member['tag'],True)['members'] if row['name'].lower()==name),None)
        if not target:raise EOError('That character is not a guild member')
        if not 0<=rank<=9 or target['rank']==0:raise EOError('Choose rank 0–9; existing founders cannot be changed')
        if rank==0:
            if member['rank']!=0 or not settings['GuildMultipleFounders']:raise EOError('Only a founder may appoint another founder')
        else:
            permission='GuildPromoteRank' if rank<=target['rank'] else 'GuildDemoteRank'
            if member['rank']>settings[permission] or (member['rank']!=0 and member['rank']>=target['rank']) or rank<member['rank'] or (rank==member['rank'] and member['rank']>settings['GuildPromoteSameRank']):raise EOError('Your guild rank cannot make that change')
        self.send(39,29,self._guild_token()+number(rank,1)+name.encode('ascii'));self._guild_wait(set(),{18,23,24});self._guild_sync()
        return self.snapshot()

    def guild_kick(self, name):
        member=self._guild_member('GuildKickRank');name=self._guild_text(name,'character')
        target=next((row for row in self._guild_read(member['tag'],True)['members'] if row['name'].lower()==name),None)
        if not target or target['rank']<=member['rank']:raise EOError('Choose a member ranked below you')
        self.send(39,28,self._guild_token()+name.encode('ascii'));self._guild_wait(set(),{20,21,22});self._guild_sync()
        return self.snapshot()

    def guild_leave(self, disband=False):
        self._guild_member('GuildDisbandRank' if disband else None)
        self.send(39,25 if disband else 4,self._guild_token());self._guild_sync()
        if self.guild.get('membership'):raise EOError('The server did not confirm leaving the guild')
        self.guild_creation=None;self.guild_notice='Guild disbanded' if disband else 'You left the guild'
        return self.snapshot()

    def guild_close(self):
        self.guild=None
        return self.snapshot()

    def apply_guild_packet(self,f,a,p):
        if f!=39:return
        r=Reader(p)
        if a==1:
            pid=r.num(2);display=r.rest().decode('latin1')
            self.guild_invitation=dict(player_id=pid,display=display,map_id=self.state['map_id'])
        elif a==3:
            code=r.num(1 if len(p)==1 else 2)
            if code in (7,8):
                name=r.rest().decode('latin1')
                if self.guild_creation:
                    creation=dict(self.guild_creation);names=list(creation['members'])
                    if name and name not in names:names.append(name)
                    creation.update(members=names,ready=code==7 or creation['ready']);self.guild_creation=creation
            elif code==13:
                request=dict(player_id=r.num(2),name=r.rest().decode('latin1'),map_id=self.state['map_id'])
                self.guild_requests=([row for row in (self.guild_requests or []) if row['player_id']!=request['player_id']]+[request])[-16:]
            elif code in REPLIES:self.guild_notice=REPLIES[code]
        elif a in (5,6):
            r.num(2)
            if r.take(1)!=b'\xff':raise EOError('Invalid native guild membership')
            tag,name,title=r.text(),r.text(),r.text()
            if a==6:
                remaining=r.num(4)
                if r.rest():raise EOError('Unexpected native guild creation data')
                self._set_amount(1,remaining);self.guild_creation=None
            elif r.take(1)!=b'\xff':raise EOError('Invalid native guild acceptance')
            self.stats.update(guild=name,guild_tag=tag,guild_rank=title)
            self.guild_invitation=None;self.guild_notice='Guild created' if a==6 else 'You joined '+name
        elif a==11:
            remaining=r.num(4)
            if r.rest():raise EOError('Invalid native guild deposit reply')
            self._set_amount(1,remaining)
        self.dirty=True
