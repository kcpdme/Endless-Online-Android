"""Install supplied original Version 1 skill-master data without changing prices."""
import argparse, hashlib, pathlib, re

def install(runtime, source):
    runtime=pathlib.Path(runtime);source=pathlib.Path(source)
    if source.is_dir():source=source/'skills.ini'
    raw=source.read_bytes();text=raw.decode('utf-8-sig')
    if not re.search(r'^Version\s*=\s*[12]\s*$',text,re.M):raise ValueError('Missing native skill config version')
    if not re.search(r'^\d+\.learn\s*=',text,re.M):raise ValueError('No supplied skill-master offers')
    (runtime/'data/aster-vale-skills.ini').write_bytes(raw)
    local=runtime/'config.local.ini';config=local.read_text()
    config=re.sub(r'^SkillsFile\s*=.*\n?', '',config,flags=re.M)
    local.write_text(config.rstrip()+'\nSkillsFile = ./data/aster-vale-skills.ini\n')
    return {'source_sha256':hashlib.sha256(raw).hexdigest(),'native_offer_rows':len(re.findall(r'^\d+\.learn\s*=',text,re.M))}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=pathlib.Path,required=True);p.add_argument('--source',type=pathlib.Path,required=True);a=p.parse_args();print(install(a.runtime,a.source))
