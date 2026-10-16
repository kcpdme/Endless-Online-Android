#!/usr/bin/env python3
"""Install a verified pure-Python websockets wheel into isolated local state, without global pip."""
import argparse,hashlib,pathlib,sys,urllib.request,zipfile
VERSION='17.2'
URL='https://files.pythonhosted.org/packages/8a/58/835cd51934d6780fa586f275b5d9901eead6d81569b4343b3767cdbaae4c/websockets-17.2-py3-none-any.whl'
SHA256='6aa59f0ef92e796b2db6f5f26550c4713c0e4036899fadf02f55e2ed4db0b7ae'
DEFAULT_TARGET=pathlib.Path(__file__).resolve().parent/'.local/python'
def install(target):
    if sys.version_info<(3,11):raise RuntimeError('websockets17.2 requires Python3.11 or newer')
    target=pathlib.Path(target).resolve();target.mkdir(parents=True,exist_ok=True);archive=target.parent/'websockets-17.2-py3-none-any.whl'
    if not archive.exists():urllib.request.urlretrieve(URL,archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:raise RuntimeError('Pinned websockets wheel SHA256 mismatch')
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            name=pathlib.PurePosixPath(info.filename)
            if name.is_absolute() or '..' in name.parts:raise RuntimeError('Unsafe dependency archive path')
        z.extractall(target)
    return target

def load(target=DEFAULT_TARGET):
    sys.path.insert(0,str(pathlib.Path(target).resolve()))
    import websockets
    if websockets.__version__!=VERSION:raise RuntimeError(f'Run bootstrap_ws.py first; exact websockets{VERSION} required')
    return websockets
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target',type=pathlib.Path,default=DEFAULT_TARGET);a=p.parse_args()
    target=install(a.target);load(target);print('Verified websockets'+VERSION+' installed at '+str(target))
