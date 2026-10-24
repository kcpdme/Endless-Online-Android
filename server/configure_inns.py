#!/usr/bin/env python3
"""Enable native question-based citizenship changes at another town's inn.

Only the explicit subscription rule changes. Existing homes, questions, account
records, password configuration and default death spawn are preserved.
"""
from pathlib import Path
import re

def configure(runtime):
    path=Path(runtime)/'config.local.ini';original=path.read_text()
    pattern=r'^CitizenSubscribeAnytime\s*=.*$'
    line='CitizenSubscribeAnytime = yes'
    result=re.sub(pattern,line,original,flags=re.M) if re.search(pattern,original,re.M) else original.rstrip()+'\n'+line+'\n'
    path.write_text(result)
    return dict(native_citizenship_switching=True,home_or_database_rewritten=False)

if __name__=='__main__':
    import argparse,json
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True)
    print(json.dumps(configure(p.parse_args().runtime)))
