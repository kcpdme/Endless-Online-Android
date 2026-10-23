"""Export the original GFX2:68 quest progress/history icons."""
import argparse,json,zipfile
from pathlib import Path
from import_eo import PEBitmaps,read_member,write_json

def add_atlas(atlas,out,manifest):
    if atlas.width<120 or atlas.height<30:raise ValueError('Original quest atlas must contain eight 15-pixel icons and the counter marker')
    atlas.save(out/'gfx/002_00068.png')
    manifest['graphics']['2:68']=dict(path='res://content/gfx/002_00068.png',width=atlas.width,height=atlas.height)
    manifest['quest_journal']=dict(atlas='2:68',icon_size=15,icons=8,source='EndlessClient QuestStatusListDialogItem.cs / original GFX2:68')
    return dict(width=atlas.width,height=atlas.height,icons=8)

def export(graphics,out):
    out=Path(out)
    with zipfile.ZipFile(graphics) as archive:atlas=PEBitmaps(read_member(archive,'gfx/gfx002.egf')).image(68)
    manifest=json.loads((out/'manifest.json').read_text());report=add_atlas(atlas,out,manifest);write_json(out/'manifest.json',manifest);return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--graphics',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args();print(json.dumps(export(a.graphics,a.output)))
