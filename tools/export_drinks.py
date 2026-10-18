"""Export the original Fairy Soda drunk emote sheet without rebuilding other art."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from import_eo import PEBitmaps, read_member, write_json


def export(archive, out):
    out = Path(out); manifest = json.loads((out / 'manifest.json').read_text())
    with zipfile.ZipFile(archive) as source:
        original = read_member(source, 'gfx/gfx002.egf')
        image = PEBitmaps(original).image(38)
    path = out / 'gfx/002_00038.png'; image.save(path)
    manifest['graphics']['2:38'] = dict(path='res://content/gfx/002_00038.png', width=image.width, height=image.height)
    manifest['drinks'] = dict(emote_sheet='2:38', drunk_set=10, sets=15, frames=4,
                             frame_seconds=.24, source_sha256=hashlib.sha256(original).hexdigest())
    write_json(out / 'manifest.json', manifest)
    return manifest['drinks']


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--output', type=Path, default=Path('client/content'))
    a = p.parse_args(); print(json.dumps(export(a.archive, a.output)))
