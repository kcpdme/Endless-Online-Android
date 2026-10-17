"""Configure the native, once-at-creation inventory and learned Heal Self.

Apply with the world stopped and a private config/database backup. Requires
etheos-starter-kit.patch for gender-specific bag outfits. Existing players are
never modified by this configuration.
"""
import argparse
import json
from pathlib import Path
import re

STARTERS = {
    'StartItems': '1,1000;144,1;21,1;453,1',
    'StartItemsMale': '1,1000;144,1;21,1;453,1',
    'StartItemsFemale': '1,1000;151,1;21,1;453,1',
    'StartSpells': '1,0',
}


def configure(runtime):
    path = Path(runtime) / 'config.local.ini'
    if path.is_symlink() or path.parent.is_symlink():
        raise ValueError('Materialize private config before writing starter rules')
    text = path.read_text()
    for key, value in STARTERS.items():
        pattern = r'^' + key + r'\s*=.*$'
        line = f'{key} = {value}'
        text = re.sub(pattern, line, text, flags=re.MULTILINE) if re.search(pattern, text, re.MULTILINE) else text.rstrip() + '\n' + line + '\n'
    path.write_text(text)
    return dict(starters=STARTERS, existing_characters_changed=False, restart_required=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    print(json.dumps(configure(parser.parse_args().runtime), indent=2))
