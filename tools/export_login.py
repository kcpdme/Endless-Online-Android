"""Export an original EO title-screen illustration from the supplied client pack."""
import argparse,json,zipfile
from pathlib import Path
from import_eo import PEBitmaps,read_member,write_json

def add_art(image,out,manifest):
    (out/'ui').mkdir(exist_ok=True);image.save(out/'ui/login-original.png')
    manifest['login_art']=dict(path='res://content/ui/login-original.png',source='Original GFX1:31 / EndlessClient BaseControlSet.cs',width=image.width,height=image.height)

def export(archive,out):
    out=Path(out);manifest=json.loads((out/'manifest.json').read_text())
    with zipfile.ZipFile(archive) as source:image=PEBitmaps(read_member(source,'gfx/gfx001.egf')).image(31,transparent=False)
    add_art(image,out,manifest);write_json(out/'manifest.json',manifest)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--graphics',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'));a=p.parse_args();export(a.graphics,a.output)
