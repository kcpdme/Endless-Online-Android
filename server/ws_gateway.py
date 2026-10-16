#!/usr/bin/env python3
"""Loopback WebSocket transport for the existing EO JSON gateway, suitable behind Caddy WSS."""
import argparse,json,logging,pathlib,socket,threading
from http import HTTPStatus
from bootstrap_ws import DEFAULT_TARGET,load

class Transport:
    def __init__(self,address):self.address=address;self.slots=threading.BoundedSemaphore(12)
    def handle(self,websocket):
        if not self.slots.acquire(blocking=False):websocket.close(code=1013,reason='Server is full; retry later');return
        connection=None;reader_thread=None;stopped=threading.Event()
        try:
            connection=socket.create_connection(self.address,timeout=15);connection.settimeout(1)
            connection.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
            def receive_backend():
                pending=b''
                try:
                    while not stopped.is_set():
                        try:chunk=connection.recv(65536)
                        except socket.timeout:continue
                        if not chunk:break
                        pending+=chunk
                        if len(pending)>4*1024*1024:break
                        while b'\n' in pending:
                            reply,pending=pending.split(b'\n',1);websocket.send(reply.decode('utf-8'))
                except Exception:pass
                finally:
                    stopped.set()
                    try:websocket.close(code=1011,reason='EO session ended; reconnect')
                    except Exception:pass
            reader_thread=threading.Thread(target=receive_backend,daemon=True);reader_thread.start()
            while not stopped.is_set():
                try:message=websocket.recv(timeout=1)
                except TimeoutError:continue
                if not isinstance(message,str):websocket.close(code=1003,reason='Send JSON text messages');return
                try:
                    obj=json.loads(message,parse_constant=lambda _:(_ for _ in ()).throw(ValueError('Invalid JSON number')))
                    encoded=json.dumps(obj,separators=(',',':'),allow_nan=False).encode('utf-8')+b'\n'
                except (ValueError,TypeError):
                    websocket.send(json.dumps({'id':None,'op':None,'ok':False,'error':'Send one valid JSON request per message.'}));continue
                if len(encoded)>65536:websocket.close(code=1009,reason='Request exceeds64KiB');return
                connection.sendall(encoded)
        except Exception:
            # No traceback, frames, credentials or request bodies in service logs.
            try:websocket.close(code=1011,reason='Connection ended; reconnect')
            except Exception:pass
        finally:
            stopped.set()
            if connection:
                try:connection.shutdown(socket.SHUT_RDWR)
                except OSError:pass
                connection.close()
            if reader_thread:reader_thread.join(timeout=2)
            self.slots.release()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=8081)
    p.add_argument('--tcp-host',default='127.0.0.1');p.add_argument('--tcp-port',type=int,default=8079)
    p.add_argument('--deps-dir',type=pathlib.Path,default=DEFAULT_TARGET);p.add_argument('--origin',action='append',default=[])
    a=p.parse_args()
    if a.host!='127.0.0.1' or a.tcp_host!='127.0.0.1':p.error('Native services must remain on loopback; terminate public TLS at the reverse proxy.')
    load(a.deps_dir)
    from websockets.sync.server import serve
    from websockets.exceptions import ConnectionClosed
    logger=logging.getLogger('astervale.websocket');logger.addHandler(logging.NullHandler());logger.propagate=False;logger.setLevel(logging.WARNING)
    def process_request(connection,request):
        if request.path=='/healthz':
            try:
                with socket.create_connection((a.tcp_host,a.tcp_port),timeout=1):pass
                return connection.respond(HTTPStatus.OK,'ok\n')
            except OSError:return connection.respond(HTTPStatus.SERVICE_UNAVAILABLE,'gateway unavailable\n')
        if request.path!='/ws':return connection.respond(HTTPStatus.NOT_FOUND,'not found\n')
        return None
    transport=Transport((a.tcp_host,a.tcp_port))
    with serve(transport.handle,a.host,a.port,origins=[None]+a.origin,compression=None,
               process_request=process_request,max_size=65536,max_queue=4,open_timeout=10,
               ping_interval=5,ping_timeout=8,close_timeout=5,server_header=None,logger=logger) as server:
        print(f'Aster Vale WebSocket gateway ws://{a.host}:{a.port}/ws -> TCP {a.tcp_host}:{a.tcp_port}',flush=True)
        try:server.serve_forever()
        except KeyboardInterrupt:pass
if __name__=='__main__':main()
