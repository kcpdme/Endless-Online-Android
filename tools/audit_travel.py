"""Read-only audit of exported map entrances and legacy destination problems."""
import argparse,collections,json
from pathlib import Path

def audit(content):
    maps={int(p.stem):json.loads(p.read_text()) for p in (Path(content)/'maps').glob('*.json')}
    solid={mid:set(map(tuple,m['server_blocked'])) for mid,m in maps.items()}
    issues=[];counts=collections.Counter();warps=0
    for mid,m in sorted(maps.items()):
        for warp in m['warps']:
            warps+=1;reasons=[];target=maps.get(warp['map']);dx,dy=warp['destination']
            if (warp['x'],warp['y']) in solid[mid]: reasons.append('source_solid')
            if target is None: reasons.append('missing_destination_map')
            elif not (0<=dx<target['width'] and 0<=dy<target['height']): reasons.append('destination_out_of_bounds')
            elif (dx,dy) in solid[warp['map']]: reasons.append('destination_solid')
            if reasons:
                counts.update(reasons)
                issues.append(dict(source=[mid,warp['x'],warp['y']],destination=[warp['map'],dx,dy],issues=reasons))
    return dict(maps_checked=len(maps),warps_checked=warps,issue_counts=dict(counts),issues=issues,
                scope='Static tile/warp audit; a solid landing with a clear neighbor may still be escapable. Quest gates and intended destination replacements are not inferred.')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--content',type=Path,default=Path('client/content'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();result=audit(a.content);a.report.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='issues'}))
