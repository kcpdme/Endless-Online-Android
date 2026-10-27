#!/usr/bin/env python3
"""Loopback JSON-lines development adapter to real EO v28 sessions. Never a mock server."""
import argparse, collections, json, select, socket, socketserver, time, threading
from eo_session import EOError
from auth_sessions import AuthSessions
from shortcuts import ShortcutStore
from live_session import LiveSession as Session

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.session=None;self.streaming=False;self.request.settimeout(8);self.request.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1);buffer=b'';recent=collections.deque();last_push=0.0
        try:
            while True:
                if b'\n' not in buffer:
                    readers=[self.request]+([self.session.sock] if self.session and self.session.sock else [])
                    ready,_,_=select.select(readers,[],[],0.05 if self.streaming else 1)
                    if self.session and self.session.sock in ready:
                        self.session.pump()
                        for _ in range(31):
                            if not select.select([self.session.sock],[],[],0)[0]:break
                            self.session.pump()
                    if self.session:self.session.poll_actions()
                    if self.streaming and self.session and self.session.dirty and not self.session.warp and time.monotonic()-last_push>=0.045:
                        self.write_message({'event':'world','ok':True,'data':self.session.world_update()});last_push=time.monotonic()
                    if self.request not in ready:continue
                    block=self.request.recv(8192)
                    if not block:return
                    buffer+=block
                    if len(buffer)>65536:raise ValueError('Request exceeds 64 KiB')
                    if b'\n' not in buffer:continue
                line,buffer=buffer.split(b'\n',1);request={};error_code=None
                try:
                    raw=json.loads(line)
                    if not isinstance(raw,dict):raise ValueError('Request must be a JSON object')
                    request=raw
                    if len(request)>16:raise ValueError('Request must be a small JSON object')
                    if any(not isinstance(v,(str,int,float,bool,type(None))) or (isinstance(v,str) and len(v)>256) for v in request.values()):raise ValueError('Invalid request field')
                    now=time.monotonic()
                    while recent and recent[0]<now-1:recent.popleft()
                    if len(recent)>=16:raise EOError('Too many requests; wait before retrying')
                    recent.append(now)
                    data=self.execute(request)
                    result={'id':request.get('id'),'op':request.get('op'),'ok':True,'data':data}
                except (EOError,ValueError,KeyError,TypeError,TimeoutError,OSError,RuntimeError) as exc:
                    error_code=getattr(exc,'code',None)
                    result={'id':request.get('id'),'op':request.get('op'),'ok':False,'error':str(exc) if isinstance(exc,EOError) else 'Request failed; check fields or reconnect to the local server.'}
                if error_code is not None:result["error_code"]=error_code
                self.write_message(result)
        except (OSError,ValueError,RuntimeError):pass
        finally:
            self.server.auth_sessions.forget(self)
            if self.session:self.session.close()
    def end_session(self):
        # A verified in-memory reconnect proof may retire only its own old session.
        for connection in (self.request,self.session.sock if self.session else None):
            if connection:
                try:connection.shutdown(socket.SHUT_RDWR)
                except OSError:pass
                try:connection.close()
                except OSError:pass
    def write_message(self,message):
        self.request.sendall((json.dumps(message,separators=(',',':'))+'\n').encode('utf-8'))
    def execute(self,r):
        op=r.get('op')
        if op=='connect':
            self.server.auth_sessions.forget(self)
            if self.session:self.session.close()
            self.session=Session(*self.server.eo_address)
            return {'connected':True,'protocol':'EO v28','server':'etheos','authenticated':False}
        if op=='stream':
            if not self.session or not self.session.state:raise EOError('Enter a character before enabling movement streaming')
            self.streaming=bool(r.get('enabled',True));return {'enabled':self.streaming,'movement_seconds':0.42}
        if op=='disconnect':
            self.server.auth_sessions.forget(self)
            if self.session:self.session.close();self.session=None
            return {'connected':False}
        s=self.session
        if not s:raise EOError('Connect to the local server first')
        if op=='ping':return {'connected':True}
        if op=='feature_open':return s.feature_open(str(r['kind']),r.get('npc_index',0),r.get('x',0),r.get('y',0),r.get('player_id',0))
        if op=='feature_action':
            data=s.feature_action(str(r['kind']),str(r['action']),r.get('ident',0),r.get('text',''),r.get('body',''))
            if r['kind']=='reset' and data.get('feature',{}).get('reset') and not data.get('feature',{}).get('preserved_spells'):
                self.server.shortcuts.write(s,'skills',0,0)
                data['shortcuts']=self.server.shortcuts.read(s)
            return data
        if op=='delete_character':
            result=s.delete_character(r['character_id'],r['name'])
            self.server.shortcuts.remove_deleted_character(s,result['deleted'])
            return result
        if op=='change_password':
            result=s.change_password(str(r['old_password']),str(r['new_password']))
            self.server.auth_sessions.forget(self)
            return result
        if op=='admin_open':return s.admin_open()
        if op=='admin_teleport':return s.admin_teleport(r.get('destination',''))
        if op=='admin_item':return s.admin_item(r.get('item_id'))
        if op=='admin_spawn':return s.admin_spawn(r.get('npc_id'))
        if s.trade and op in ('walk','attack','spend_stat'):raise EOError('Close the trade before acting')
        if op=='register':return s.register(str(r['username']),str(r['password']))
        if op=='login':
            username=str(r['username']).strip().lower()
            if self.server.auth_sessions.resume(username,str(r.get('resume_token','')),self):time.sleep(.2)
            data=s.login(username,str(r['password']))
            s.shortcut_account=username
            data['resume_token']=self.server.auth_sessions.issue(username,self)
            return data
        if op=='create_character':return s.create_character(str(r['name']),int(r.get('gender',1)),int(r.get('hairstyle',1)),int(r.get('haircolor',0)),int(r.get('race',0)))
        if op=='enter':
            s.enter(int(r['character_id']));data=s.snapshot()
            data['shortcuts']=self.server.shortcuts.read(s)
            from balance_rules import profile
            data['balance_catalog']=profile()
            return data
        if op=='shortcuts_set':return self.server.shortcuts.write(s,r['kind'],r['first'],r['second'])
        if op=='move':return s.move(int(r['direction']),int(r['input_seq']),int(r['map_id']),int(r['x']),int(r['y']),bool(r.get('open_door',False)))
        if op=='refresh':s.refresh();return s.snapshot()
        if op=='walk':s.walk(int(r['direction']),bool(r.get('open_door',False)));return s.snapshot()
        if op=='face':return s.face(int(r['direction']))
        if op=='sit':return s.sit(r.get('x'),r.get('y'))
        if op=='guild_open':return s.guild_open(int(r['npc_index']))
        if op=='guild_info':return s.guild_lookup(str(r['query']))
        if op=='guild_members':return s.guild_lookup(str(r['query']),members=True)
        if op=='guild_refresh':return s.guild_refresh()
        if op=='guild_begin':return s.guild_begin(r['tag'],r['name'])
        if op=='guild_found':return s.guild_found(r.get('description',''))
        if op=='guild_support':return s.guild_support(r.get('accept',False))
        if op=='guild_join':return s.guild_join(r['tag'],r['recruiter'])
        if op=='guild_recruit':return s.guild_recruit(int(r['player_id']),r.get('accept',False))
        if op=='guild_deposit':return s.guild_deposit(int(r['amount']))
        if op=='guild_description':return s.guild_description(r['description'])
        if op=='guild_ranks':return s.guild_ranks(r['ranks'])
        if op=='guild_rank':return s.guild_rank(r['name'],int(r['rank']))
        if op=='guild_kick':return s.guild_kick(r['name'])
        if op=='guild_leave':return s.guild_leave()
        if op=='guild_disband':return s.guild_leave(disband=True)
        if op=='guild_chat':return s.chat_send('guild',r['message'])
        if op=='guild_close':return s.guild_close()
        if op=='inn_open':return s.inn_open(int(r['npc_index']))
        if op=='inn_register':return s.inn_register([r.get('answer1',''),r.get('answer2',''),r.get('answer3','')])
        if op=='inn_remove':return s.inn_remove()
        if op=='inn_quote':return s.inn_quote()
        if op=='inn_sleep':return s.inn_sleep()
        if op=='inn_close':return s.inn_close()
        if op=='barber_open':return s.barber_open(int(r['npc_index']))
        if op=='barber_buy':return s.barber_buy(int(r['style']),int(r['color']))
        if op=='barber_close':return s.barber_close()
        if op=='quest_list':return s.quest_list(str(r.get('page','progress')))
        if op=='quest_open':return s.quest_open(int(r['npc_index']),int(r.get('quest_id',0)))
        if op=='quest_reply':return s.quest_reply(r.get('action'))
        if op=='quest_close':return s.quest_close()
        if op=='strike':return s.strike(int(r['direction']))
        if op=='spend_stat':return s.spend_stat(int(r['stat_id']))
        if op=='attack':s.attack(r.get('direction'));return s.snapshot()
        if op=='shop_open':return s.shop_open(int(r['npc_index']))
        if op in ('shop_buy','shop_sell','shop_craft'):return s.shop_trade(op.removeprefix('shop_'),int(r['item_id']),int(r.get('amount',1)))
        if op=='collect':return s.collect(int(r['uid']))
        if op=='spell_cast':return s.cast_spell(int(r['spell_id']),str(r['target_kind']),int(r.get('target_id',0)))
        if op=='spell_cancel':return s.cancel_spell()
        if op=='skillmaster_open':return s.skillmaster_open(int(r['npc_index']))
        if op in ('skill_learn','skill_forget','skill_level'):return s.skill_change(op.removeprefix('skill_'),int(r['spell_id']))
        if op=='bard_note':return s.bard_note(r['note'])
        if isinstance(op,str) and op.startswith('party_'):return s.party_action(op.removeprefix('party_'),r.get('player_id',0))
        if op=='diagnostics':return dict(s.metrics)
        if op=='pickup':return s.pickup(int(r['uid']))
        if op in ('equip','unequip'):
            s._standing()
            if op=='equip':
                from balance_rules import check_equipment
                check_equipment(s,int(r['item_id']))
            s.equip(int(r['item_id']),op=='unequip',int(r.get('subloc',0)));return s.snapshot()
        if op=='item_drop':return s.drop_item(int(r['item_id']),int(r.get('amount',1)))
        if op=='item_junk':return s.junk_item(int(r['item_id']),int(r.get('amount',1)))
        if op=='redeem_code':return s.redeem_code(str(r['code']))
        if op=='item_use':return s.use_item(int(r['item_id']))
        if op=='potion_use':return s.use_potion(int(r['item_id']))
        if op=='bank_upgrade':return s.bank_upgrade()
        if op=='bank_open':return s.bank_open(int(r['npc_index']))
        if op in ('bank_deposit','bank_withdraw'):return s.bank_change(op=='bank_withdraw',int(r['amount']))
        if op=='locker_open':return s.locker_open(int(r['x']),int(r['y']))
        if op in ('locker_deposit','locker_withdraw'):return s.locker_change(op=='locker_withdraw',int(r['item_id']),int(r.get('amount',1)))
        if op=='chest_open':return s.chest_open(int(r['x']),int(r['y']))
        if op=='chest_close':return s.chest_close()
        if op in ('chest_deposit','chest_take'):return s.chest_change(op=='chest_take',int(r['item_id']),int(r.get('amount',1)))
        if op=='online_players':return s.request_online_players()
        if op=='chat_send':return s.chat_send(str(r['channel']),str(r['message']),str(r.get('target','')))
        if op=='inspect_player':return s.inspect_player(int(r['player_id']))
        if isinstance(op,str) and op.startswith('trade_'):return s.trade_action(op.removeprefix('trade_'),int(r.get('player_id',0)),int(r.get('item_id',0)),int(r.get('amount',0)),bool(r.get('agree',True)))
        raise EOError('Unsupported gateway operation')
class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address=True;daemon_threads=True
    auth_sessions=AuthSessions()
    slots=threading.BoundedSemaphore(12)
    def process_request(self,request,address):
        if not self.slots.acquire(blocking=False):self.shutdown_request(request);return
        super().process_request(request,address)
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=8079)
    p.add_argument('--eo-host',default='127.0.0.1');p.add_argument('--eo-port',type=int,default=8078)
    a=p.parse_args()
    if a.host!='127.0.0.1' or a.eo_host!='127.0.0.1':p.error('This development adapter enforces loopback for both connections. TLS/public hosting is a separate milestone.')
    with Server((a.host,a.port),Handler) as server:
        server.eo_address=(a.eo_host,a.eo_port)
        server.shortcuts=ShortcutStore()
        print(f'Aster Vale local EO gateway listening on {a.host}:{a.port} -> etheos {a.eo_host}:{a.eo_port}',flush=True)
        try:server.serve_forever()
        except KeyboardInterrupt:pass
if __name__=='__main__':main()
