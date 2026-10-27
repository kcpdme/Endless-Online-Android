"""Coverage and role comparisons from installed definitions and real acquisition routes."""
from balance_model import benchmarks,loadout
from balance_profile import LEVELS
SLOTS={10:'weapon',12:'body',13:'head',14:'boots',15:'gloves',19:'ring'}

def legal(item,clas,level,gender=None):
    return item['level_requirement']<=level and (not item.get('allowed_classes') or clas in item['allowed_classes']) and (item['type']!=12 or gender is None or item['gender']==gender)

def obtainable(item):return any(item.get('acquisition',{}).get(k) for k in ('buy','craft','drop'))

def audit(profile):
    coverage=[];issues=[]
    for clas in range(2,8):
        for level in LEVELS:
            slots={}
            for typ,name in SLOTS.items():
                available=[i for i in profile['items'].values() if i['type']==typ and legal(i,clas,level) and obtainable(i)]
                slots[name]=dict(total=len(available),exclusive=sum(i.get('allowed_classes')==[clas] for i in available),purchased=sum(bool(i.get('acquisition',{}).get('buy')) for i in available),crafted=sum(bool(i.get('acquisition',{}).get('craft')) for i in available),dropped=sum(bool(i.get('acquisition',{}).get('drop')) for i in available))
                if not available:issues.append(f"{clas}/{level}: no obtainable {name}")
            for gender in (0,1):
                if not any(i['type']==12 and legal(i,clas,level,gender) and obtainable(i) for i in profile['items'].values()):issues.append(f'{clas}/{level}: no body for gender {gender}')
            for item in loadout(profile,clas,level):
                if not obtainable(item):issues.append(f"{clas}/{level}: benchmark {item['name']} has no acquisition route")
            known=[s for s in profile['spells'].values() if clas in s.get('allowed_classes',[]) and s['level_requirement']<=level]
            if not any(s['type']==1 and s.get('effect_kind')!='companion' for s in known):issues.append(f'{clas}/{level}: no offensive ability')
            coverage.append(dict(class_id=clas,class_name=profile['classes'][str(clas)]['name'],level=level,slots=slots,skills=len(known),signature=profile['classes'][str(clas)]['signature']))
    return dict(version=profile['version'],result='passed' if not issues else 'failed',issues=issues,coverage=coverage,benchmarks=benchmarks(profile),comparison_scope='Matched level and 60/25/15 attributes, obtainable main gear plus five supporting slots. Front-facing burst, conditional backstab and passive regeneration are reported separately; range, party support and area damage are advantages, not a claim of identical DPS.')

if __name__=='__main__':
    import argparse,json
    from pathlib import Path
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    report=audit(json.loads((a.runtime/'data/balance-profile.json').read_text()));a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(result=report['result'],issues=report['issues'],builds=len(report['coverage']))));raise SystemExit(bool(report['issues']))
