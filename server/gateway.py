#!/usr/bin/env python3
"""Loopback JSON-lines development adapter to real EO v28 sessions. Never a mock server."""
import argparse, collections, json, select, socket, socketserver, time, threading
from eo_session import EOError,Session

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.session=None;self.request.settimeout(8);buffer=b'';recent=collections.deque()
        try:
            while True:
                if b'\n' not in buffer:
                    readers=[self.request]+([self.session.sock] if self.session and self.session.sock else [])
                    ready,_,_=select.select(readers,[],[],1)
                    if self.session and self.session.sock in ready:self.session.pump()
                    if self.request not in ready:continue
                    block=self.request.recv(8192)
                    if not block:return
                    buffer+=block
                    if len(buffer)>65536:raise ValueError('Request exceeds 64 KiB')
                    if b'\n' not in buffer:continue
                line,buffer=buffer.split(b'\n',1);request={}
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
                    result={'id':request.get('id'),'op':request.get('op'),'ok':False,'error':str(exc) if isinstance(exc,EOError) else 'Request failed; check fields or reconnect to the local server.'}
                self.request.sendall((json.dumps(result,separators=(',',':'))+'\n').encode('utf-8'))
        except (OSError,ValueError,RuntimeError):pass
        finally:
            if self.session:self.session.close()
    def execute(self,r):
        op=r.get('op')
        if op=='connect':
            if self.session:self.session.close()
            self.session=Session(*self.server.eo_address)
            return {'connected':True,'protocol':'EO v28','server':'etheos','authenticated':False}
        if op=='disconnect':
            if self.session:self.session.close();self.session=None
            return {'connected':False}
        s=self.session
        if not s:raise EOError('Connect to the local server first')
        if op=='register':return s.register(str(r['username']),str(r['password']))
        if op=='login':return s.login(str(r['username']),str(r['password']))
        if op=='create_character':return s.create_character(str(r['name']),int(r.get('gender',1)),int(r.get('hairstyle',1)),int(r.get('haircolor',0)),int(r.get('race',0)))
        if op=='enter':s.enter(int(r['character_id']));return s.snapshot()
        if op=='refresh':s.refresh();return s.snapshot()
        if op=='walk':s.walk(int(r['direction']));return s.snapshot()
        if op=='attack':s.attack(r.get('direction'));return s.snapshot()
        if op=='pickup':s.pickup(int(r['uid']));return s.snapshot()
        if op in ('equip','unequip'):s.equip(int(r['item_id']),op=='unequip',int(r.get('subloc',0)));return s.snapshot()
        raise EOError('Unsupported gateway operation')
class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address=True;daemon_threads=True
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
        print(f'Aster Vale local EO gateway listening on {a.host}:{a.port} -> etheos {a.eo_host}:{a.eo_port}',flush=True)
        try:server.serve_forever()
        except KeyboardInterrupt:pass
if __name__=='__main__':main()
