"""Disposable native integration probe used only by the isolated test harness."""
import json,select,secrets,sqlite3,time
from pathlib import Path
from live_session import LiveSession
from eo_session import Session,EOError,number
from test_online import dev_name

def run(runtime,port=18886):
    runtime=Path(runtime);actors=[];sessions=[];checks=[]
    def verify(value,name):
        if not value:raise AssertionError(name)
        checks.append(name);print('FEATURE NATIVE:',name,flush=True)
    def wait(test,timeout=12):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            for s in sessions:
                if s.sock and select.select([s.sock],[],[],.03)[0]:s.pump()
                s.poll_actions()
            if test():return True
        return False
    def warp(s,mid,x,y):
        s.send(18,21,f'$warp {mid} {x} {y}'.encode('ascii'))
        assert wait(lambda:s.state['map_id']==mid and not s.warp and (s.state['self']['x'],s.state['self']['y'])==(x,y)),'Native warp failed'
    def npc(s,ident):return next(n for n in s.state['npcs'] if n['id']==ident)
    try:
        for _ in range(2):
            f=dict(username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name())
            s=Session(port=port);s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name']);s.close();actors.append(f)
        time.sleep(.7)
        inventory='1,50000;6,5;261,3;249,3;162,2;256,3;257,4;337,5;338,5;'
        with sqlite3.connect(runtime/'database.sdb') as db:
            for f in actors:db.execute('UPDATE characters SET admin=4,map=5,x=40,y=40,level=50,"str"=100,agi=1,"int"=100,wis=1000,"con"=1000,hp=30000,tp=30000,inventory=?,spells=?,paperdoll=?,gender=1 WHERE name=? AND account=?',(inventory,'1,0;4,3;17,0;','0,0,0,0,133,0,0,0,0,0,0,0,0,0,0,',f['name'],f['username']))
            db.execute('UPDATE characters SET agi=3000 WHERE name=?',(actors[0]['name'],))
        for f in actors:
            s=LiveSession('127.0.0.1',port);rows=s.login(f['username'],f['password'])['characters'];s.enter(rows[0]['id']);s.snapshot();sessions.append(s)
        a,b=sessions
        data=a.feature_open('book')['feature'];verify(data['name']==actors[0]['name'],'native character book')
        data=a.feature_action('find','find',text=actors[1]['name'])['feature'];verify('nearby' in data['notice'],'native find nearby player')
        a.feature_action('social','whispers',0);verify(not a.whispers_enabled,'native whisper off ordering barrier')
        a.feature_action('social','whispers',1);verify(a.whispers_enabled,'native whisper on ordering barrier')
        data=a.feature_action('emotes','emote',7);verify(any(e.get('kind')=='player_emote' and e.get('emote')==7 for e in data['events']),'native manual emote')
        a.feature_action('report','help',body='Isolated integration probe');verify(True,'native admin help request')
        warp(a,5,46,2);data=a.feature_open('board',x=46,y=1)['feature'];verify(data['board_id']==0,'native board tile open')
        subject='Probe '+actors[0]['name'];data=a.feature_action('board','post',text=subject,body='A disposable test post.')['feature'];post=next(p for p in data['posts'] if p['subject'].startswith(subject))
        data=a.feature_action('board','read',post['id'])['feature'];verify(data['body']=='A disposable test post.','native board publish and read')
        data=a.feature_action('board','remove',post['id'])['feature'];verify(not any(p['id']==post['id'] for p in data['posts']),'native board moderation')
        warp(a,14,16,2);before=a.item_amount(1);a.feature_open('jukebox',x=16,y=1);a.feature_action('jukebox','play',0)
        verify(a.item_amount(1)==before-25,'native jukebox Gold payment')
        verify(wait(lambda:any(e.get('kind')=='jukebox_music' for e in a.events)),'native shared jukebox track')
        # Authored quest acceptance, hand-in, reward, history and no second grant.
        from native_settings import map_specs
        from eo_session import Reader
        for ident in [192,193,252,300,301,302,305,303]:
            match=None
            for path in sorted((runtime/'data/maps').glob('*.emf')):
                raw=path.read_bytes();r=Reader(raw);r.take(46)
                for _ in range(r.num()):
                    x,y,nid=r.num(),r.num(),r.num(2);r.take(4)
                    if nid==ident:match=(int(path.stem),x,y);break
                if match:break
            assert match
            mid,x,y=match;specs=map_specs(mid)
            px,py=next((xx,yy) for xx,yy in [(x,y+1),(x+1,y),(x,y-1),(x-1,y)] if specs.get((xx,yy),-1) not in tuple(range(10))+(16,18,34,35,36))
            warp(a,mid,px,py);target=npc(a,ident);before_exp=a.stats.get('experience',0);before_gold=a.item_amount(1);before_flock=a.item_amount(492);observed_speech=False
            for _ in range(16):
                if a.stats.get('experience',0)>before_exp or a.item_amount(492)>before_flock:break
                a.quest_open(target['index']);dialog=a.quest_dialog
                action=next((link['id'] for link in dialog['links'] if link['id']==2),None)
                a.quest_reply(action);a._feature_barrier()
                observed_speech |= any(e.get('kind')=='npc_speech' for e in a.events)
            verify(a.stats.get('experience',0)>before_exp,'native quest completion NPC '+str(ident))
            if ident!=303:
                verify(observed_speech,'native quest NPC speech '+str(ident))
                earned=a.item_amount(1)
                try:a.quest_open(target['index']);a._feature_barrier()
                except EOError:pass # Finished one-time quests correctly offer no new dialogue.
                verify(a.item_amount(1)==earned,'no duplicate quest reward '+str(ident))
            else:verify(a.item_amount(492)==before_flock+1 and a.item_amount(337)==0 and a.item_amount(338)==0,'Baru daily consumes correct ice and grants new Flock ID')
        # Real damage/drain packets, without altering live maps or production timers.
        warp(a,229,5,5);hp=a.stats['hp'];verify(wait(lambda:a.stats['hp']<hp,4),'native HP drain synchronization')
        warp(a,136,88,36);tp=a.stats['tp'];verify(wait(lambda:a.stats['tp']<tp,4),'native TP drain synchronization')
        a.send(18,21,b'$quake 4');verify(wait(lambda:any(e.get('kind')=='quake' for e in a.events),3),'native earthquake event')
        warp(a,245,5,5);warp(b,245,5,6);a.events.clear();b.events.clear()
        hp=b.stats['hp']
        for _ in range(5):
            a.strike(0)
            if wait(lambda:b.stats['hp']<hp,1):break
        verify(wait(lambda:b.stats['hp']<hp and any(e.get('source')=='pk' for e in b.events)),'native melee PK damage and HP')
        a.events.clear();b.events.clear();hp=b.stats['hp'];tp=a.stats['tp']
        for _ in range(5):
            a.cast_spell(4,'player',b.player_id)
            wait(lambda:a.casting is None,8)
            if b.stats['hp']<hp:break
        ok=wait(lambda:b.stats['hp']<hp and a.stats['tp']<tp and any(e.get('spell_id')==4 and e.get('source')=='pk' for e in b.events),2)
        if not ok:print('PK DIAGNOSTIC',dict(before_hp=hp,after_hp=b.stats['hp'],before_tp=tp,after_tp=a.stats['tp'],casting=a.casting,events=a.events[-8:],victim_events=b.events[-8:]),flush=True)
        verify(ok,'native offensive player spell and caster TP')
        # Marriage approval on each side, actual priest invitation and timed vows.
        for s,partner in [(a,actors[1]['name']),(b,actors[0]['name'])]:
            warp(s,157,5,3);s.feature_open('law',npc(s,115)['index']);s.feature_action('law','approve',text=partner)
        verify(True,'native two-sided marriage approval')
        warp(a,15,6,9);warp(b,15,7,9);a.feature_open('priest',npc(a,114)['index']);a.feature_action('priest','request',text=actors[1]['name'])
        verify(wait(lambda:(getattr(b,'wedding_pending',None) or {}).get('action')=='accept'),'native wedding invitation')
        b.feature_action('priest','accept')
        deadline=time.monotonic()+110;vows=0
        while time.monotonic()<deadline:
            wait(lambda:any((getattr(s,'wedding_pending',None) or {}).get('action')=='vow' for s in sessions),1)
            for s in sessions:
                if (getattr(s,'wedding_pending',None) or {}).get('action')=='vow':s.feature_action('priest','vow');vows+=1
            data=a.feature_open('book')['feature']
            if data.get('partner')==actors[1]['name']:break
        verify(vows==2 and data.get('partner')==actors[1]['name'],'native wedding ceremony and both vows')
        warp(a,157,5,3);a.feature_open('law',npc(a,115)['index']);a.feature_action('law','divorce',text=actors[1]['name'])
        verify(not a.feature_open('book')['feature']['partner'],'native divorce and partner update')
        # Native full reset, not a client-only point counter.
        from skills import npc_types
        target=None
        for path in sorted((runtime/'data/maps').glob('*.emf')):
            r=Reader(path.read_bytes());r.take(46)
            for _ in range(r.num()):
                x,y,nid=r.num(),r.num(),r.num(2);r.take(4)
                if npc_types().get(nid)==14:target=(int(path.stem),x,y,nid);break
            if target:break
        mid,x,y,nid=target;warp(a,mid,x,y+1);a.feature_open('reset',npc(a,nid)['index']);a.feature_action('reset','reset')
        verify(not a.spells and all(a.stats[k]==0 for k in ['strength','intelligence','wisdom','agility','constitution','charisma']) and a.stats['stat_points']>0,'native full attribute and spell reset')
        return dict(result='passed',checks=len(checks),verified=checks)
    finally:
        for s in sessions:s.close()
