#!/usr/bin/env python3
"""Loopback-only integration-test proxy with pipelined propagation delay and jitter."""
import argparse,asyncio,time
from bootstrap_ws import load,DEFAULT_TARGET

async def main(a):
    from websockets.asyncio.client import connect
    from websockets.asyncio.server import serve
    from websockets.exceptions import ConnectionClosed
    async def forward(source,destination):
        queue=asyncio.Queue(maxsize=256);counter=0;last_due=0
        async def read():
            nonlocal counter,last_due
            try:
                async for message in source:
                    pattern=(-1,.7,-.4,1,0,.4)
                    delay=max(0,a.delay_ms+a.jitter_ms*pattern[counter%len(pattern)])/1000
                    counter+=1;last_due=max(last_due,time.monotonic()+delay)
                    await queue.put((last_due,message))
            finally:await queue.put((0,None))
        reader=asyncio.create_task(read())
        try:
            while True:
                due,message=await queue.get()
                if message is None:return
                await asyncio.sleep(max(0,due-time.monotonic()))
                await destination.send(message)
        finally:reader.cancel()
    async def handle(client):
        try:
            async with connect(a.upstream,proxy=None,max_size=4194304,compression=None) as upstream:
                tasks=[asyncio.create_task(forward(client,upstream)),asyncio.create_task(forward(upstream,client))]
                done,pending=await asyncio.wait(tasks,return_when=asyncio.FIRST_COMPLETED)
                for task in pending:task.cancel()
                for task in done:task.result()
        except ConnectionClosed:pass
    async with serve(handle,'127.0.0.1',a.port,max_size=4194304,compression=None):
        print(f'Loopback latency test proxy on {a.port}; each direction {a.delay_ms} ± {a.jitter_ms} ms',flush=True)
        await asyncio.Future()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--upstream',default='ws://127.0.0.1:8183/ws');p.add_argument('--port',type=int,default=8194);p.add_argument('--delay-ms',type=float,default=120);p.add_argument('--jitter-ms',type=float,default=80);p.add_argument('--deps-dir',type=str,default=str(DEFAULT_TARGET));a=p.parse_args();load(a.deps_dir)
    asyncio.run(main(a))
