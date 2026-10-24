"""Capture public classic economy facts for review; never writes a live runtime."""
import argparse, concurrent.futures, hashlib, html, json, re, time, urllib.request
from pathlib import Path

BASE = 'https://apollo-games.com/eoclassic/'

def table(text, ident):
    found = re.search(r'<table\s+id="'+re.escape(ident)+r'"[^>]*>(.*?)</table>', text, re.S)
    return found[1] if found else ''

def rows(text):
    return re.split(r'<tr\b[^>]*>', text)[1:]

def plain(text):
    return html.unescape(re.sub('<[^>]+>', ' ', text)).strip()

def shop(text, ident):
    vendors = [int(v) for v in re.findall(r'npc.php\?npc=(\d+)', table(text,'shop-vendors'))]
    name = plain(re.search(r'<h2[^>]*>(.*?)</h2>',table(text,'shop'),re.S)[1])
    trade=[];craft=[]
    for row in rows(table(text,'shop-trades')):
        item=re.search(r'item.php\?item=(\d+)',row)
        if not item:continue
        prices={key.lower():int(value.replace(',','')) for key,value in re.findall(r'(Buy|Sell):\s*<a>([\d,]+)g',row)}
        if not prices:raise ValueError('Shop row has no prices')
        trade.append(dict(id=int(item[1]),buy=prices.get('buy',0),sell=prices.get('sell',0)))
    for row in rows(table(text,'shop-crafts')):
        items=re.findall(r'item.php\?item=(\d+)',row)
        if not items:continue
        ingredients=re.findall(r'item.php\?item=(\d+)[^>]*>[^<]*</a>\s*<b>:\s*(\d+)</b>',row,re.S)
        if not ingredients or len(ingredients)>4:raise ValueError('Unrecognized recipe')
        craft.append(dict(id=int(items[0]),ingredients=[[int(k),int(v)] for k,v in ingredients]))
    if not vendors or not trade and not craft:raise ValueError('Empty shop')
    return dict(id=ident,name=name,npc_ids=vendors,trade=trade,craft=craft)

def gold(text):
    result=[]
    for row in rows(table(text,'item-drops')):
        npc=re.search(r'npc.php\?npc=(\d+)',row)
        if not npc:continue
        values=re.search(r'<b>(\d+)\s*-\s*(\d+)</b>.*?<b>([\d.]+)%</b>',row,re.S)
        if not values:raise ValueError('Unrecognized Gold drop')
        low,high,chance=values.groups()
        result.append(dict(npc_id=int(npc[1]),minimum=int(low),maximum=int(high),chance=float(chance)))
    return result

def npc_drops(text,ident):
    if 'NPC ID:' not in text or not re.search(r'#'+str(ident)+r'\b',text):raise ValueError('Missing NPC record '+str(ident))
    result=[]
    for row in rows(table(text,'npc-drops')):
        item=re.search(r'item.php\?item=(\d+)',row)
        if not item:continue
        values=re.search(r'<b>(\d+)(?:\s*-\s*(\d+))?</b>.*?<b>([\d.]+)%</b>',row,re.S)
        if not values:raise ValueError('Unrecognized NPC drop '+str(ident))
        low,high,chance=values.groups()
        result.append(dict(id=int(item[1]),minimum=int(low),maximum=int(high or low),chance=float(chance)))
    return dict(npc_id=ident,drops=result)

def capture(cache,npc_catalog=None):
    cache=Path(cache);cache.mkdir(parents=True,exist_ok=True);sources={}
    def fetch(name,relative):
        url=BASE+relative;path=cache/(name+'.html')
        if path.exists() and b"OH GOD I'M DYING" in path.read_bytes():path.unlink()
        if not path.exists():
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            request=urllib.request.Request(url,headers={'User-Agent':'AsterVale-classic-economy-audit/1.0'})
            for attempt in range(4):
                raw=opener.open(request,timeout=45).read()
                if b"OH GOD I'M DYING" not in raw:break
                time.sleep(attempt+1)
            else:raise ValueError('Classic database temporarily unavailable: '+url)
            path.write_bytes(raw)
        raw=path.read_bytes();return raw.decode('utf-8'),dict(url=url,sha256=hashlib.sha256(raw).hexdigest())
    index,source=fetch('shops','shops.php');sources['shops']=source
    ids=sorted(set(int(v) for v in re.findall(r'shop.php\?shop=(\d+)',index)))
    if ids!=list(range(1,43)):raise ValueError('Classic shop index changed; review new source')
    def load(ident):
        text,source=fetch('shop'+str(ident),'shop.php?shop='+str(ident))
        return shop(text,ident),source
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        loaded=list(pool.map(load,ids))
    shops=[]
    for entry,source in loaded:shops.append(entry);sources['shop'+str(entry['id'])]=source
    text,source=fetch('gold','item.php?item=1');sources['gold']=source;drops=gold(text)
    if len(drops)!=50:raise ValueError('Classic Gold list changed; review source')
    result=dict(version=1,captured_date='2026-10-24',sources=sources,shops=shops,gold=drops)
    if npc_catalog:
        catalog=json.loads(Path(npc_catalog).read_text())
        ids=sorted(int(k) for k,v in catalog['npcs'].items() if v['type'] in (1,2))
        def load_npc(ident):
            text,source=fetch('npc'+str(ident),'npc.php?npc='+str(ident));return npc_drops(text,ident),source
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:loaded=list(pool.map(load_npc,ids))
        result['npc_drops']=[]
        for entry,source in loaded:result['npc_drops'].append(entry);sources['npc'+str(entry['npc_id'])]=source
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--cache',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--npc-catalog',type=Path);a=p.parse_args()
    result=capture(a.cache,a.npc_catalog);a.out.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(shops=len(result['shops']),trade_rows=sum(len(s['trade']) for s in result['shops']),recipes=sum(len(s['craft']) for s in result['shops']),gold_rows=len(result['gold']))))
