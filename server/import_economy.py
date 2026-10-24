#!/usr/bin/env python3
"""Stage supplied NPC shops/drops (EODelta baseline) without touching accounts or password salt."""
import argparse, hashlib, json, pathlib, re

def install(runtime, source_data):
    runtime=pathlib.Path(runtime);source_data=pathlib.Path(source_data)
    report={}
    config=runtime/'config.local.ini';text=config.read_text()
    for kind,key in [('shops','ShopsFile'),('drops','DropsFile')]:
        data=(source_data/(kind+'.ini')).read_text(encoding='utf-8-sig')
        if kind=='shops' and not re.search(r'^Version\s*=\s*1\s*$',data,re.M):raise ValueError('Expected original per-NPC shop format Version 1')
        if not re.search(r'^\d+(?:\.trade|\.craft)?\s*=',data,re.M):raise ValueError('Missing original economy records')
        target=runtime/'data'/('aster-vale-'+kind+'.ini');target.write_text(data)
        value='./data/'+target.name;pattern=r'^'+key+r'\s*=.*$'
        if re.search(pattern,text,re.M):text=re.sub(pattern,key+' = '+value,text,flags=re.M)
        else:text=text.rstrip()+'\n'+key+' = '+value+'\n'
        report[kind]={'records':len(re.findall(r'^\d+(?:\.trade|\.craft)?\s*=',data,re.M)),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    config.write_text(text);config.chmod(0o600)
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',required=True,type=pathlib.Path);p.add_argument('--source-data',required=True,type=pathlib.Path);a=p.parse_args();print(json.dumps(install(a.runtime,a.source_data),indent=2))
if __name__=='__main__':main()
