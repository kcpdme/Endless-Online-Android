"""Explicit class ownership and bounded equipment archetypes for profile two."""
from collections import defaultdict
import re

# Common starter tools, clothes, jewellery, costumes and instruments remain useful.
# Everything specialised has an explicit owner; names never grant permissions.
WEAPONS = {
    2: (23,33,362,390,455,495,534),
    3: (205,206,224,270,272,290,389,493),
    4: (25,26,38,238,269,327,366,436,468,497,533),
    5: (297,316,365,457,496,511,512,543),
    6: (18,19,22,24,27,28,30,31,32,34,36,37,207,225,245,271,281,282,283,284,285,286,287,288,317,325,328,351,352,360,361,363,391,393,420,421,433,434,435,444,454,456,498),
    7: (35,329,494,513,514),
}
BODIES = {
    2: (47,139,149,406,499,500,519,520,525,526,531,532),
    3: (127,128,156,324,407,409,410,501,502,521,522,523,524),
    4: (136,140,142,148,157,372,505,506,527,528,539,540),
    5: (413,414,507,508,529,530,541,542),
    6: (59,60,135,138,141,143,145,154,155,158,168,169,170,274,275,311,312,342,343,364,387,388,422,458,459,466,509,510),
    7: (503,504,515,516,517,518,535,536,537,538),
}
OWNERS = {ident:(clas,) for groups in (WEAPONS,BODIES) for clas,ids in groups.items() for ident in ids}
OWNERS.update({ident:(5,) for ident in (423,424,425)})
OWNERS.update({ident:(2,3,7) for ident in (131,132)})
OWNERS.update({ident:(3,) for ident in (173,174,175,176,177,178,124,125,126)})
OWNERS.update({ident:(6,) for ident in (180,196,246,247,289,330,385,386,426,447,266)})
OWNERS.update({267:(4,),187:(2,3,7),181:(7,)})

ROLES={2:'wisdom',3:'intelligence',4:'agility',5:'agility',6:'strength',7:'charisma'}

def allowed_classes(item):
    return OWNERS.get(item['id'], ())

def role_for(item, fallback):
    classes=allowed_classes(item)
    return ROLES[classes[0]] if len(classes)==1 else fallback

def recipe_sources(text):
    sources=defaultdict(lambda:dict(buy=[],craft=[]))
    for vendor,kind,raw in re.findall(r'^(\d+)\.(trade|craft)[ \t]*=[ \t]*(.*)$',text,re.M):
        if not raw.strip():continue
        parts=list(map(int,raw.split(',')));width=3 if kind=='trade' else 9
        if len(parts)%width:raise ValueError('Invalid shop record')
        for start in range(0,len(parts),width):
            if kind=='trade' and parts[start+1]<=0:continue
            sources[parts[start]]['buy' if kind=='trade' else 'craft'].append(int(vendor))
    return dict(sources)

def vary_stats(item, stats, tier, crafted=False):
    """Small, deliberate tradeoffs inside a tier; no random/unbounded affixes."""
    result=dict(stats);name=item['name'].lower();role=role_for(item,'strength')
    style='balanced'
    if item['type']==10 and tier:
        if any(k in name for k in ('axe','mace','hammer','chopper','saw','flail')):
            style='heavy';result['max_damage']+=2+tier;result['accuracy']=max(0,result['accuracy']-2)
        elif item['id'] in WEAPONS[4]:
            style='precision';result['accuracy']+=2;result['evade']+=1+tier//2
            result['max_damage']=max(result['min_damage'],result['max_damage']-1)
        elif any(k in name for k in ('spear','pole','trident')):
            style='reach';result['max_damage']+=2;result['accuracy']+=1
        elif role in ('wisdom','intelligence','charisma'):
            style='focus';result['tp']+=3*tier
        if crafted:
            result['min_damage']+=1;result['max_damage']+=2;result[role]+=1
    elif item['type']==12 and tier:
        if item['id'] in BODIES[6]:
            style='bulwark';result['constitution']+=max(1,tier//2);result['hp']+=4*tier
        elif item['id'] in BODIES[4]:
            style='skirmisher';result['evade']+=tier;result['accuracy']+=1
        elif item['id'] in BODIES[5]:
            style='marksman';result['accuracy']+=tier;result['hp']+=2*tier
        elif role in ('wisdom','intelligence','charisma'):
            style='focus';result['tp']+=4*tier
        if crafted:result['armor']+=2;result['hp']+=8
    elif item['type']==11 and crafted:
        if item['subtype']==2:result['max_damage']+=2
        else:result['armor']+=2
    if crafted and item['type'] in (13,14,15):
        result['armor']+=1;result['hp']+=5
    if item['id']==533:
        # Hidden Blade favours skill use and evasion; Twin Blades keeps the
        # higher direct hit. Same tier and recipe effort, different purpose.
        result['min_damage']=max(1,result['min_damage']-1)
        result['max_damage']=max(result['min_damage'],result['max_damage']-1)
        result['accuracy']+=3;result['evade']+=3;result['tp']+=12
    return result,style
