"""Configure the classic empty-inventory Tutorial Island birth.

Apply with the world stopped and a private config/database backup. Requires
etheos-starter-kit.patch for gender-specific bag outfits. Existing players are
never modified by this configuration.
"""
import argparse
import json
from pathlib import Path
import re

STARTERS = {
    'StartMap': '192', 'StartX': '7', 'StartY': '6',
    'StartItems': '', 'StartItemsMale': '', 'StartItemsFemale': '',
    'StartSpells': '',
    'StartEquipMale': ','.join(['0']*15),
    'StartEquipFemale': ','.join(['0']*15),
}

def patched_config(text):
    for key,value in STARTERS.items():
        pattern=r'^'+key+r'\s*=.*$';line=f'{key} = {value}'.rstrip()
        text=re.sub(pattern,line,text,flags=re.MULTILINE) if re.search(pattern,text,re.MULTILINE) else text.rstrip()+'\n'+line+'\n'
    return text


def configure(runtime):
    path = Path(runtime) / 'config.local.ini'
    if path.is_symlink() or path.parent.is_symlink():
        raise ValueError('Materialize private config before writing starter rules')
    path.write_text(patched_config(path.read_text()))
    return dict(starters=STARTERS, existing_characters_changed=False, restart_required=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    print(json.dumps(configure(parser.parse_args().runtime), indent=2))
