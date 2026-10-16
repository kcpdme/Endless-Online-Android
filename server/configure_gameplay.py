#!/usr/bin/env python3
"""Configure valid default home and death recovery for the pinned etheos runtime.
Changes two explicit overrides; account database and password salt are untouched.
"""
import argparse,pathlib,re

def configure(runtime):
    runtime=pathlib.Path(runtime);config=runtime/'config.local.ini'
    original=config.read_text()
    home=runtime/'data/aster-vale-home.ini'
    home.write_text('# Aster Vale default home; all levels without a personal citizenship.\nVersion = 2\naeven.name = Aeven\naeven.location = 5, 40,40\nlevel.0 = aeven\n')
    values={'HomeFile':'./data/aster-vale-home.ini','DeathRecover':'50'}
    for key,value in values.items():
        line=f'{key} = {value}'
        pattern=r'^'+re.escape(key)+r'\s*=.*$'
        if re.search(pattern,original,re.MULTILINE):original=re.sub(pattern,line,original,flags=re.MULTILINE)
        else:original=original.rstrip()+'\n'+line+'\n'
    config.write_text(original);config.chmod(0o600)
    return {'default_home':[5,40,40],'death_recovery_percent':50,'reason':'Pinned Character::DeathRespawn divides the configured number by 100; use 50 rather than 50% (0.5).','database_modified':False}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=pathlib.Path,required=True);a=p.parse_args()
    print(configure(a.runtime))
if __name__=='__main__':main()
