"""Typed admin tools. Existing native commands retain final rank/duty authority."""
import socket
import time
from functools import lru_cache
from eo_session import EOError, Reader
from services import runtime_path, item_definitions

# Stable keys keep the mobile menu extensible without accepting arbitrary commands.
DESTINATIONS = (
    dict(key='apozen', name='Apozen', map_id=119, x=24, y=29),
    dict(key='apozen_overlord', name='Apozen Overlord', map_id=136, x=49, y=18),
    dict(key='wraith_room', name='Wraith Room', map_id=277, x=11, y=31),
    dict(key='reaper_cave', name='Reaper Cave', map_id=109, x=7, y=13),
    dict(key='octopus', name='Octopus', map_id=155, x=8, y=11),
    # Original Monkey Island quest arrival, pyramid entrance, and GM meeting room.
    dict(key='monkey_island', name='Monkey Island', map_id=271, x=25, y=54),
    dict(key='pyramid', name='Pyramid', map_id=229, x=82, y=112),
    dict(key='admin_room', name='Admin Room', map_id=21, x=12, y=6),
    # Original Anundo inn exit and Atlantis pathway arrival.
    dict(key='anundo', name='Anundo', map_id=161, x=32, y=36),
    dict(key='atlantis', name='Atlantis', map_id=255, x=12, y=19),
)

def command_settings():
    """Read only public command configuration, including local overrides."""
    runtime=runtime_path().resolve(); settings={'AdminPrefix':'$','warp':'4','sitem':'4','snpc':'4'}
    def read(path, keys, stack=()):
        path=path.resolve()
        if path in stack or not path.is_relative_to(runtime) or not path.is_file():return
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=');key=key.strip();value=value.split('#',1)[0].strip()
            if not sep:continue
            if key in ('INCLUDE','INCLUDE_NOWARN','REQUIRE'):read(runtime/value,keys,stack+(path,))
            elif key in keys:settings[key]=value
    read(runtime/'config.ini',{'AdminPrefix'})
    read(runtime/'admin.ini',{'warp','sitem','snpc'})
    return settings

@lru_cache(maxsize=1)
def npc_ids():
    r=Reader((runtime_path()/'data/pub/dtn001.enf').read_bytes())
    if r.take(3)!=b'ENF':raise EOError('Native NPC definitions are unavailable')
    r.take(4);count=r.num(2);r.num();result=set()
    for ident in range(1,count+1):
        name=r.take(r.num()).decode('latin1');r.take(39)
        if name.lower()=='eof':break
        result.add(ident)
    return result

class AdminMixin:
    def _admin_guard(self, command=None):
        # This role comes exclusively from native Welcome, never request fields.
        if not self.state or int(self.stats.get('admin',0))<=0:raise EOError('Admin access is required')
        settings=command_settings()
        if command and int(self.stats['admin'])<int(settings[command]):raise EOError('Your admin rank cannot use this function')
        return settings

    def admin_open(self):
        settings=self._admin_guard()
        return dict(destinations=[dict(d) for d in DESTINATIONS], capabilities={k:int(self.stats['admin'])>=int(settings[c]) for k,c in [('teleport','warp'),('item','sitem'),('spawn','snpc')]})

    def _admin_command(self, command, arguments, accepted):
        settings=self._admin_guard(command);self._standing()
        if self.state['self'].get('sitting',0):raise EOError('Stand up before using admin tools')
        now=time.monotonic()
        if now-getattr(self,'last_admin_action',0)<.7:raise EOError('Wait a moment between admin actions')
        self.last_admin_action=now
        # All arguments have already been validated as integers or server presets.
        payload=(settings['AdminPrefix']+command+' '+arguments).encode('ascii')
        self.send(18,21,payload)
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            self.sock.settimeout(max(.1,deadline-time.monotonic()))
            try:f,a,p=self.receive()
            except socket.timeout:break
            finally:self.sock.settimeout(8)
            control=self.control_packet(f,a,p)
            if not control:self.apply_event(f,a,p)
            if accepted(f,a,p):return self.snapshot()
            if (f,a)==(18,23):raise EOError(Reader(p).rest().decode('latin1'))
        raise EOError('The server did not confirm this action. Check your admin rank, duty status and capacity before retrying.')

    def admin_teleport(self, key):
        self._admin_guard('warp')
        destination=next((d for d in DESTINATIONS if d['key']==key),None)
        if not destination:raise EOError('Choose a listed teleport destination')
        target=(destination['map_id'],destination['x'],destination['y'])
        def accepted(f,a,p):
            me=self.state['self']
            return (f,a)==(19,5) and not self.warp and (self.state['map_id'],me['x'],me['y'])==target
        data=self._admin_command('warp','%d %d %d'%target,accepted)
        data['admin_notice']='Teleported to '+destination['name'];return data

    def admin_item(self, item_id):
        self._admin_guard('sitem')
        if type(item_id) is not int or item_id not in item_definitions():raise EOError('Enter a valid item ID')
        def accepted(f,a,p):
            if (f,a)!=(14,27):return False
            r=Reader(p);return r.num(2)==0 and r.num(2)==item_id and r.num(3)==1
        data=self._admin_command('sitem','%d 1'%item_id,accepted)
        data['admin_notice']='Added 1 item (ID %d) to your bag.'%item_id;return data

    def admin_spawn(self, npc_id):
        self._admin_guard('snpc')
        if type(npc_id) is not int or npc_id not in npc_ids():raise EOError('Enter a valid NPC ID')
        previous={n['index'] for n in self.state['npcs']}
        def accepted(f,a,p):
            return (f,a)==(29,3) and any(n['id']==npc_id and n['index'] not in previous for n in self.state['npcs'])
        data=self._admin_command('snpc','%d 1'%npc_id,accepted)
        data['admin_notice']='Spawned 1 NPC (ID %d) nearby.'%npc_id;return data
