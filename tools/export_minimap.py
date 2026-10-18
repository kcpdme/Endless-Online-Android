"""Export the original GFX2:45 nine-cell minimap atlas for the Android HUD."""
import argparse
import json
from pathlib import Path
import zipfile
from import_eo import PEBitmaps,read_member,write_json

def add_atlas(atlas,out,manifest):
    if atlas.width%9:raise ValueError('Original minimap atlas must contain nine cells')
    atlas.save(out/'gfx/002_00045.png')
    manifest['graphics']['2:45']=dict(path='res://content/gfx/002_00045.png',width=atlas.width,height=atlas.height)
    manifest['minimap']=dict(atlas='2:45',cells=9,tile_width=28,tile_height=14,
                              source='EndlessClient MiniMapRenderer.cs / original GFX2:45')
    return dict(width=atlas.width,height=atlas.height,cells=9)

def export(graphics,out):
    out=Path(out)
    with zipfile.ZipFile(graphics) as archive:
        atlas=PEBitmaps(read_member(archive,'gfx/gfx002.egf')).image(45)
    manifest=json.loads((out/'manifest.json').read_text())
    report=add_atlas(atlas,out,manifest)
    write_json(out/'manifest.json',manifest)
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--graphics',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'))
    a=p.parse_args();print(json.dumps(export(a.graphics,a.output)))
