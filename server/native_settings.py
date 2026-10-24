"""Read a whitelist of public gameplay settings; never return private config."""
from functools import lru_cache
from services import runtime_path
from eo_session import EOError, Reader

def settings(defaults):
    return dict(_settings(tuple(sorted(defaults.items()))))

@lru_cache(maxsize=32)
def _settings(defaults):
    root=runtime_path().resolve();result=dict(defaults)
    def read(path,stack=()):
        path=path.resolve()
        if path in stack or not path.is_relative_to(root) or not path.is_file():return
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=');key=key.strip();value=value.split('#',1)[0].strip()
            if not sep:continue
            if key in ('INCLUDE','INCLUDE_NOWARN','REQUIRE'):read(root/value,stack+(path,))
            elif key in result:result[key]=value
    read(root/'config.ini')
    return result

@lru_cache(maxsize=512)
def map_flags(map_id):
    path=runtime_path()/'data/maps'/('%05d.emf'%int(map_id))
    data=path.read_bytes()
    if data[:3]!=b'EMF':raise EOError('Invalid native map')
    r=Reader(data[31:33]);return r.num()==3,r.num()

def world_rules(map_id):
    pk,effect=map_flags(map_id)
    cfg=settings({'GlobalPK':'no','PKExcept':''})
    exceptions=[int(v.strip()) for v in cfg['PKExcept'].split(',') if v.strip().isdigit()]
    pk=pk or (str(cfg['GlobalPK']).lower() in ('yes','true','1') and map_id not in exceptions)
    return dict(map_id=map_id,pk=pk,effect=effect)

@lru_cache(maxsize=512)
def map_specs(map_id):
    r=Reader((runtime_path()/'data/maps'/('%05d.emf'%int(map_id))).read_bytes())
    r.take(46)
    r.take(r.num()*8);r.take(r.num()*4);r.take(r.num()*12)
    specs={}
    for _ in range(r.num()):
        y=r.num()
        for _ in range(r.num()):
            x=r.num();specs[x,y]=r.num()
    return specs
