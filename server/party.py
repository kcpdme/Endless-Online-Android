"""Native EO party invitations, membership, HP, EXP, chat and bard notes."""
import time
from eo_session import EOError, Reader, number
from eo_stats import update
from skills import spell_definitions
from services import item_definitions, runtime_path
from functools import lru_cache

@lru_cache(maxsize=1)
def level_points():
    runtime=runtime_path().resolve(); values={"StatPerLevel":3,"SkillPerLevel":3}; seen=set()
    def read(path):
        path=path.resolve()
        if path in seen or not path.is_relative_to(runtime) or not path.is_file():return
        seen.add(path)
        for line in path.read_text().splitlines():
            key,sep,value=line.partition("=");key=key.strip();value=value.split("#",1)[0].strip()
            if not sep:continue
            if key in ("INCLUDE","REQUIRE"):read(runtime/value)
            elif key in values:values[key]=int(value)
    read(runtime/"config.ini");read(runtime/"config.local.ini")
    return values

class PartyMixin:
    def init_party(self):
        self.party_members=[];self.party_invitation=None;self.party_notice='';self.last_bard=0

    def party_action(self, action, player_id=0):
        self._mobile_action();player_id=int(player_id)
        if action in ('invite','join'):
            self._peer(player_id)
            if any(m['player_id']==player_id for m in self.party_members):raise EOError('This player is already in your party')
            if action=='join' and self.party_members:raise EOError('Leave your current party before asking to join another')
            if self.party_members and not next((m['leader'] for m in self.party_members if m['player_id']==self.player_id),False):raise EOError('Ask your party leader to invite players')
            self.send(24,1,number(1 if action=='invite' else 0,1)+number(player_id,2))
            self.party_notice='Party invitation sent.' if action=='invite' else 'Party join request sent.'
        elif action in ('accept','decline'):
            invitation=self.party_invitation
            if not invitation or invitation['expires']<time.monotonic():raise EOError('This party request has expired')
            if action=='accept':
                if invitation['type']==0 and self.party_members and not any(m['leader'] and m['player_id']==self.player_id for m in self.party_members):raise EOError('Only your party leader can accept join requests')
                self._peer(invitation['player_id'])
                self.send(24,2,number(invitation['type'],1)+number(invitation['player_id'],2))
                self.party_notice='Waiting for the native party confirmation.'
            else:self.party_notice='Party request declined.'
            self.party_invitation=None
        elif action in ('leave','kick'):
            target=self.player_id if action=='leave' else player_id
            if action=='kick' and target==self.player_id:raise EOError('Use Leave party to remove yourself')
            if not self.party_members or not any(m['player_id']==target for m in self.party_members):raise EOError('This player is not in your party')
            if action=='kick' and not any(m['player_id']==self.player_id and m['leader'] for m in self.party_members):raise EOError('Only the party leader can remove members')
            self.send(24,4,number(target,2))
        elif action=='refresh':
            if self.party_members:self.send(24,9)
        else:raise EOError('Unknown party action')
        self.dirty=True
        return self.snapshot()

    def bard_note(self, note):
        self._mobile_action()
        if type(note) is not int or not 0<=note<36:raise EOError('Choose one of the 36 instrument notes')
        if not any(spell_definitions().get(s['id'],{}).get('type')==2 for s in self.spells):raise EOError('Learn Bard before playing an instrument')
        graphic=item_definitions().get(self.equipment.get('weapon',0),{}).get('graphic_value')
        if graphic not in (49,50):raise EOError('Equip a Harp or Guitar to play Bard')
        now=time.monotonic()
        if now-self.last_bard<.14:raise EOError('Let the previous note begin')
        self.send(21,10,number(graphic,1)+number(note,1));self.last_bard=now
        # Native excludes the player from the broadcast, as for local chat.
        self.events.append(dict(kind='bard_note',player_id=self.player_id,direction=self.state['self']['direction'],instrument=graphic,note=note))
        self.dirty=True
        return self.snapshot()

    @staticmethod
    def _party_member(r, terminated=True):
        return dict(player_id=r.num(2),leader=bool(r.num()),level=r.num(),hp_percent=r.num(),name=r.text() if terminated else r.rest().decode('latin1'))

    def apply_party_packet(self,f,a,p):
        r=Reader(p)
        if f==24:
            if a==1:
                kind=r.num();pid=r.num(2);name=r.rest().decode('latin1')
                if kind not in (0,1):raise EOError('Invalid party request')
                self.party_invitation=dict(type=kind,player_id=pid,name=name,expires=time.monotonic()+30)
                self.party_notice=name+(' invited you to a party.' if kind else ' wants to join your party.')
            elif a in (6,18):
                members=[]
                while r.rest():members.append(self._party_member(r))
                self.party_members=members;self.party_invitation=None;self.party_notice='Party members updated.'
            elif a==7:
                member=self._party_member(r,False)
                self.party_members=[m for m in self.party_members if m['player_id']!=member['player_id']]+[member]
            elif a==4:
                pid=r.num(2);self.party_members=[m for m in self.party_members if m['player_id']!=pid]
            elif a==14:
                self.party_members=[];self.party_invitation=None;self.party_notice='You left the party or it was disbanded.'
            elif a==5:
                pid=r.num(2);hp=r.num()
                for member in self.party_members:
                    if member['player_id']==pid:member['hp_percent']=hp
            elif a==33:
                pid=r.num(2);gain=r.num(4);level_up=r.num()
                if pid==self.player_id:
                    update(self,dict(experience=self.stats.get('experience',0)+gain))
                    self.events[-1].update(kind='party_exp',exp_gain=gain)
                    if level_up:
                        # Refresh native level/maxima. Never synthesize primary stats.
                        points=level_points();level=self.stats.get('level',1)+1
                        update(self,dict(level=level,stat_points=self.stats.get('stat_points',0)+points['StatPerLevel'],skill_points=self.stats.get('skill_points',0)+points['SkillPerLevel']))
                        self.send(25,1)
                        self.events[-1]['level_up']=level
            else:return
            self.dirty=True
        elif (f,a)==(18,13):
            pid=r.num(2);message=r.rest().decode('latin1')
            name=next((m['name'] for m in self.party_members if m['player_id']==pid),'Party member')
            self.events.append(dict(kind='chat',channel='party',player_id=pid,name=name,message=message))
            self.dirty=True
        elif (f,a)==(21,15):
            pid=r.num(2);direction=r.num();instrument=r.num();note=r.num()
            if instrument in (49,50) and note in range(36) and not r.rest():
                self.events[-1].update(kind='bard_note',player_id=pid,direction=direction,instrument=instrument,note=note);self.dirty=True
