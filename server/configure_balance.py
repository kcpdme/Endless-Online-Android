"""Install the versioned level 1–50 profile into a backed-up, stopped runtime."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sqlite3
from contextlib import closing

from eo_session import Reader, number
from combat_progression import TP_RECOVERY, BOWS, ARROWS, SHIELDS, item_traits
from balance_profile import VERSION, LEVELS, ATTRIBUTES, CLASSES, SPELLS, WEAPON_TIERS, BODY_TIERS, NEW_ITEMS, NEW_ITEM_TIERS, ENCOUNTERS, COMPANIONS
from class_identity import allowed_classes, role_for, vary_stats, recipe_sources
from class_signatures import SIGNATURES, SUPPORT, EGGS
from pet_catalog import TIERS, ROSTER, EGGKEEPER, egg_stock

STAT_FIELDS = {'hp':(5,2),'tp':(7,2),'min_damage':(9,2),'max_damage':(11,2),'accuracy':(13,2),'evade':(15,2),'armor':(17,2),**{k:(20+i,1) for i,k in enumerate(ATTRIBUTES)}}
INPUTS = ('data/pub/dat001.eif','data/pub/dat001.ecf','data/pub/dsl001.esf','data/pub/dtn001.enf','data/aster-vale-shops.ini','data/quests/00004.eqf','data/aster-vale-drops.ini')

def digest(data): return hashlib.sha256(data).hexdigest()

def records(data, signature, size, names=1):
    r=Reader(data)
    if r.take(3)!=signature: raise ValueError('Unexpected PUB signature')
    r.take(4);count=r.num(2);r.num();result=[]
    for ident in range(1,count+1):
        lengths=[r.num() for _ in range(names)]
        text=[r.take(n).decode('latin1') for n in lengths]
        result.append(dict(id=ident,names=text,fields=bytearray(r.take(size))))
    if r.rest() or (signature!=b'ECF' and result[-1]['names'][0].lower()!='eof'):raise ValueError('Unrecognized PUB record layout')
    return result

def encode_pub(original, rows):
    body=b''.join(b''.join(number(len(s.encode('latin1')),1) for s in row['names'])+b''.join(s.encode('latin1') for s in row['names'])+bytes(row['fields']) for row in rows)
    if body==original[10:]:return original
    return original[:3]+number(int.from_bytes(hashlib.sha256(body).digest()[:4],'little')%253**4,4)+number(len(rows),2)+original[9:10]+body

def num(f,start,size=1):return Reader(bytes(f[start:start+size])).num(size)
def put(f,start,value,size=1):f[start:start+size]=number(int(value),size)
def decode_item(row):
    f=row['fields']
    return dict(id=row['id'],name=row['names'][0],type=num(f,2),subtype=num(f,3),special=num(f,4),graphic=num(f,0,2),doll_graphic=num(f,32,3),gender=num(f,35),weight=num(f,55),level_requirement=num(f,37,2),class_requirement=num(f,39,2),**{k:num(f,*v) for k,v in STAT_FIELDS.items()},**{k+'_requirement':num(f,41+j*2,2) for j,k in enumerate(ATTRIBUTES)})

def item_role(i):
    name=i['name'].lower()
    if i['subtype']==1 or any(s in name for s in ('bow','crossbow','dagger','katana','ninch','sai','whip','twin','fan','rogue','archery','ninja','thief','stalker','ranger','oron')):return 'agility'
    if any(s in name for s in ('bazar','sanctum','priest','cleric','holy','healer','oracle')):return 'wisdom'
    if any(s in name for s in ('spirit','sceptre')):return 'charisma'
    if any(s in name for s in ('staff','robes','wizzard','enchanted','magical','tempest')):return 'intelligence'
    return 'strength'

def tier_for(i):
    table=WEAPON_TIERS if i['type']==10 else BODY_TIERS if i['type']==12 else {}
    for tier,ids in table.items():
        if i['id'] in ids:return tier
    if i['type'] in (10,12):return 2
    if i['id'] in (447,453):return 1 if i['id']==447 else 0
    if i['id'] in (310,426,424,425):return 3
    if i['id'] in (298,315,268,276,378,379,380,416,417):return 2
    return 0

def gear_stats(i,tier,role):
    t=i['type']; result={k:0 for k in STAT_FIELDS}
    if t==10:
        low=(1,4,8,13,19,27)[tier];high=(3,7,12,19,28,38)[tier]
        result.update(min_damage=low,max_damage=high,accuracy=(1,3,5,8,11,14)[tier])
        result[role]=(0,1,2,4,6,9)[tier]
        if role in ('intelligence','wisdom','charisma'):
            result['min_damage']=max(1,round(low*.75));result['max_damage']=max(2,round(high*.75));result['tp']=(5,12,22,38,55,80)[tier]
        if i['name'].lower() in ('flute','guitar','harp'):return {k:0 for k in STAT_FIELDS}
    elif t==12:
        armor=(1,3,5,8,12,17)[tier];hp=(0,12,24,40,65,95)[tier]
        result.update(armor=armor,hp=hp,evade=(1,2,3,5,7,10)[tier])
        result[role]=(0,1,2,4,6,9)[tier]
        if role=='strength':result.update(armor=round(armor*1.35),hp=round(hp*1.15))
        elif role=='agility':result.update(accuracy=(0,1,3,5,8,11)[tier],evade=(1,3,5,7,10,14)[tier],armor=max(1,round(armor*.8)))
        else:result.update(tp=(5,14,28,48,75,110)[tier],armor=max(1,round(armor*.65)))
    elif t==11:
        if i['subtype']==2:result.update(min_damage=(0,0,1,2,3,4)[tier],max_damage=(1,2,3,4,5,6)[tier],accuracy=1+tier)
        else:result.update(armor=1+2*tier,hp=5+8*tier,constitution=min(3,tier))
    elif t==13:result.update(hp=3+4*tier,armor=1+tier,**{role:min(4,tier+1)})
    elif t==14:result.update(evade=1+tier,armor=1+tier,hp=3*tier)
    elif t==15:result.update(accuracy=1+tier,**{role:1+tier})
    elif t==16:result.update(hp=3) # appearance accessories intentionally remain peers
    elif t in (17,18,19,20,21):result.update(hp=5+4*tier,tp=5+5*tier,**{role:1+tier})
    return result

def build_items(original, shops=""):
    sources=recipe_sources(shops)
    rows=records(original,b'EIF',58)
    if rows[490]['names'][0]!="Skylar's Admin Blade" or rows[491]['names'][0]!='Baru Flock':raise ValueError('Expected operator blade and restored Flock identities')
    metadata={}
    for row in rows[:-1]:
        i=decode_item(row);ident=i['id'];t=i['type'];f=row['fields']
        if not 10<=t<=21 or ident in (204,208,384,445,446,491):continue
        tier=tier_for(i);role=role_for(i,item_role(i));stats=gear_stats(i,tier,role)
        if ident in (390,436):role='wisdom' if ident==390 else 'agility';stats=gear_stats(i,tier,role)
        if ident in (127,128):tier=1;stats=gear_stats(i,tier,role)
        if ident==149:tier=2;stats=gear_stats(i,tier,role)
        if ident in (413,414):tier=2;stats=gear_stats(i,tier,role)
        if ident in (460,465):stats.update(hp=50,min_damage=1,max_damage=1,accuracy=7,evade=6,armor=8,strength=1,agility=7)
        if ident in (430,431):stats.update(hp=110,min_damage=2,max_damage=2,accuracy=11,evade=12,armor=24,strength=4,agility=11)
        if ident in (458,459):stats.update(hp=85,armor=20,evade=5,strength=6)
        if ident in (387,388):stats.update(hp=80,armor=18,evade=6,strength=6,accuracy=5,min_damage=2,max_damage=2)
        crafted=bool(sources.get(ident,{}).get('craft')) and not sources.get(ident,{}).get('buy')
        if ident in SHIELDS:stats["armor"]=SHIELDS[ident]
        stats,style=vary_stats(i,stats,tier,crafted)
        allowed=allowed_classes(i)
        for key,(start,size) in STAT_FIELDS.items():put(f,start,stats[key],size)
        put(f,37,LEVELS[tier] if tier else 0,2);put(f,39,allowed[0] if len(allowed)==1 else 0,2)
        for a in range(6):put(f,41+a*2,0,2)
        # Instruments and appearance accessories have no combat level gate.
        cosmetic=t==16 or i['name'].lower() in ('flute','guitar','harp')
        if cosmetic:put(f,37,0,2)
        metadata[str(ident)]=dict(tier=tier,role=role,cosmetic=cosmetic,allowed_classes=list(allowed),archetype=style,crafted=crafted,acquisition=sources.get(ident,{}))
    for ident,name,template,clas,role in NEW_ITEMS:
        if ident!=len(rows):raise ValueError('New item ID already occupied or nonconsecutive')
        template_row=rows[template-1];f=bytearray(template_row['fields']);i=dict(decode_item(template_row),id=ident,name=name)
        tier=NEW_ITEM_TIERS.get(ident,5)
        stats=gear_stats(i,tier,role)
        if 499<=ident<=510:
            # A rare class outfit must win its own role against all-round Baru.
            stats[role]=12 if role=='strength' or role in ('intelligence','wisdom','charisma') else 13
            if role=='strength':stats.update(hp=135,armor=30,constitution=3,accuracy=5)
            elif role=='agility':stats.update(hp=105,armor=18,accuracy=14,evade=20)
            else:stats['tp']=130
        if ident in SUPPORT:
            stats[role]=2 if tier==2 else 4
            if role in ('wisdom','intelligence','charisma'):stats['tp']+=12 if tier==2 else 28
            elif clas==4:stats['evade']+=2 if tier==2 else 4
            elif clas==5:stats['accuracy']+=2 if tier==2 else 4
            else:stats['hp']+=6 if tier==2 else 14;stats['armor']+=1 if tier==2 else 2
        crafted=bool(sources.get(ident,{}).get('craft')) and not sources.get(ident,{}).get('buy')
        stats,style=vary_stats(i,stats,tier,crafted)
        for key,(start,size) in STAT_FIELDS.items():put(f,start,stats[key],size)
        put(f,37,LEVELS[tier],2);put(f,39,clas,2);put(f,4,3)
        for a in range(6):put(f,41+a*2,0,2)
        if i['type']==12:put(f,35,1 if ident%2 else 0)
        rows.insert(-1,dict(id=ident,names=[name],fields=f))
        metadata[str(ident)]=dict(tier=tier,role=role,template_id=template,cosmetic=False,allowed_classes=[clas],archetype=style,crafted=crafted,acquisition=sources.get(ident,{}))
    for ident,egg in EGGS.items():
        if ident!=len(rows):raise ValueError('Egg definition ID collision')
        f=bytearray(rows[egg['template_id']-1]['fields'])
        for key,(offset,size) in STAT_FIELDS.items():put(f,offset,0,size)
        put(f,2,23);put(f,3,0);put(f,4,4);put(f,5,0,2);put(f,37,egg['level'],2);put(f,39,7,2);put(f,55,1)
        rows.insert(-1,dict(id=ident,names=[egg['name']],fields=f))
        metadata[str(ident)]=dict(template_id=egg['template_id'],hatch_spell=egg['spell_id'],allowed_classes=[7],bound=True,drop_class=7,bond_lost_on_death=True,pet_tier=egg['tier'],tier_name=egg['tier_name'],tier_color=egg['tier_color'],icon=egg['icon'],ground=egg['icon'],acquisition=sources.get(ident,{}))
    # Recovery quantities fit the new 1–50 HP/TP pools; retain native item types.
    for ident,hp,tp in [(2,35,0),(3,0,45),(4,85,0),(5,0,110),(375,170,0),(376,0,220),(377,120,140)]:
        f=rows[ident-1]['fields']
        if num(f,2)!=3:raise ValueError('Recovery item changed type')
        put(f,5,hp,2);put(f,7,tp,2)
    definitions={str(r['id']):dict(decode_item(r),**metadata.get(str(r['id']),{})) for r in rows[:-1]}
    for item in definitions.values():
        item.update(item_traits(item['id']))
        if item['type']==10:item['backstab']=item['id']==21 or item.get('allowed_classes')==[4]
    assert rows[490]['fields']==records(original,b'EIF',58)[490]['fields']
    return encode_pub(original,rows),definitions

def build_classes(original):
    rows=records(original,b'ECF',14);result={}
    for ident,p in CLASSES.items():
        row=rows[ident-1]
        if row['names'][0]!=p['name']:raise ValueError('Class identity changed')
        put(row['fields'],1,p['family'])
        for a,key in enumerate(ATTRIBUTES):put(row['fields'],2+a*2,p['base_attributes'][key],2)
        result[str(ident)]=dict(id=ident,name=p['name'],base=num(row['fields'],0),type=p['family'],build_hint=p['hint'],spell_scale=p['spell_scale'],heal_wis=p['heal_wis'],heal_int=p['heal_int'],heal_cha=p['heal_cha'],base_attributes=p['base_attributes'])
    result['3']['area_multiplier']=CLASSES[3]['area_multiplier']
    result['7']['pk_spell_scale']=CLASSES[7]['pk_spell_scale']
    for ident,signature in SIGNATURES.items():result[str(ident)]['signature']=signature
    result['8']['signature']=SIGNATURES[2]
    result['0']=dict(result['1'],id=0)
    return encode_pub(original,rows),result

def build_spells(original):
    rows=records(original,b'ESF',51,2);result={}
    if len(rows)!=32:raise ValueError('Expected the original 31 spell identities')
    for ident in range(32,max(SPELLS)+1):
        rows.insert(-1,dict(id=ident,names=['Skill','skill'],fields=bytearray(rows[15]['fields'])))
    for ident,p in SPELLS.items():
        name,level,classes,tp,chant,low,high,hp,target,restrict,radius,cap=p;row=rows[ident-1];f=row['fields']
        row['names'][0]=name;row['names'][1]=name.lower()
        for start,value,size in [(4,tp,2),(8,chant,1),(11,2 if ident==17 else 0 if hp else 1,1),(17,restrict,1),(18,target,1),(23,low,2),(25,high,2),(34,hp,2)]:put(f,start,value,size)
        result[str(ident)]=dict(id=ident,name=name,shout=name.lower(),tp=tp,cast_time=chant,type=num(f,11),restrict=restrict,target=target,min_damage=low,max_damage=high,hp=hp,level_requirement=level,allowed_classes=list(classes),area_radius=radius,area_targets=cap,area_scale=((.8 if radius==1 else .6)*CLASSES[3]['area_multiplier'] if classes==(3,) else .8 if radius==1 else .6) if radius else 1,max_level=10,training_bonus=2)
        if classes in ((4,),(6,)) and not radius:result[str(ident)]['range']=1
        if classes==(5,):result[str(ident)].update(requires_bow=True,range=10,weapon_range=True)
        if ident in {e['spell_id'] for e in EGGS.values()}:result[str(ident)].update(learn_source='Hatch a bound egg from Aeven Eggkeeper or its monster; your death breaks the pet bond',max_level=0,bond_lost_on_death=True)
        if ident>=32:result[str(ident)]['template_id']=16
        if ident in COMPANIONS:result[str(ident)].update(effect_kind='companion',companion=COMPANIONS[ident],duration=0,upkeep_seconds=2)
    return encode_pub(original,rows),result

def build_npcs(original):
    rows=records(original,b'ENF',39)
    for ident,(level,hp,lo,hi,accuracy,evade,armor,exp) in ENCOUNTERS.items():
        f=rows[ident-1]['fields']
        if num(f,7,2) not in (1,2):raise ValueError('Refusing to change a protected service NPC')
        for start,value,size in [(11,hp,3),(16,lo,2),(18,hi,2),(20,accuracy,2),(22,evade,2),(24,armor,2),(36,exp,3)]:put(f,start,value,size)
    definitions={}
    if len(rows)!=306:raise ValueError('Expected 305 existing NPC definitions')
    additions={p['npc_id']:p for p in COMPANIONS.values() if p['npc_id']>0}
    additions[EGGKEEPER['id']]=dict(EGGKEEPER,npc_id=EGGKEEPER['id'])
    for ident,p in sorted(additions.items()):
        f=bytearray(rows[p['template_id']-1]['fields'])
        if ident==EGGKEEPER['id']:
            if ident!=len(rows):raise ValueError('Eggkeeper NPC definition ID collision')
            put(f,9,ident,2)
            rows.insert(-1,dict(id=ident,names=[p['name']],fields=f))
            definitions[str(ident)]=dict(id=ident,name=p['name'],graphic=num(f,0,2),type=6,vendor_id=ident,template_id=p['template_id'])
            continue
        for offset,value,size in [(3,0,2),(5,0,2),(7,0,2),(9,0,2),(11,1,3),(16,0,2),(18,0,2),(20,0,2),(22,0,2),(24,0,2),(36,0,3)]:put(f,offset,value,size)
        ident=p['npc_id']
        if ident!=len(rows):raise ValueError('Pet NPC definition ID collision')
        rows.insert(-1,dict(id=ident,names=[p['name']],fields=f))
        definitions[str(ident)]=dict(id=ident,name=p['name'],graphic=num(f,0,2),type=0,hp=1,boss=0,child=0,vendor_id=0,min_damage=0,max_damage=0,accuracy=0,evade=0,armor=0,exp=0,template_id=p['template_id'],is_companion=True)
    return encode_pub(original,rows),definitions

def formulas(original):
    text=original.decode('latin1')
    # The native RPN evaluator pops operands in reverse order. These fractions
    # deliberately encode denominator before numerator.
    replacements={'hit_rate':'10 accuracy 0.5 * target_evade + + accuracy / 0.35 max 0.95 min', 'damage':'100 target_armor 2 * + 100 / damage * 1 max 1 1.5 critical ? * modifier *'}
    for key,value in replacements.items():text=re.sub(r'^'+key+r'\s*=.*$',f'{key} = {value}',text,flags=re.M)
    for p in CLASSES.values():
        for field in ('damage','accuracy','evade','defence','hp','tp'):
            key=f"class.{p['family']}.{field}";line=f'{key} = '+p[field]
            if re.search(r'^'+re.escape(key)+r'\s*=',text,re.M):text=re.sub(r'^'+re.escape(key)+r'\s*=.*$',line,text,flags=re.M)
            else:text+='\n'+line+'\n'
    return text.encode('latin1')

def build_skills():
    lines=['# Level 1–50 class progression. Native NPC identities retained.','Version = 1']
    offers=[]
    for ident,p in SPELLS.items():
        name,level,classes,*_=p
        if classes==(-1,) or ident==17 or ident in {e['spell_id'] for e in EGGS.values()}:continue
        for cls in classes if len(classes)==1 else (0,):
            cost=0 if level==1 else {8:200,15:600,25:1600,30:2200,35:3000,40:4000,45:5000}.get(level,120)
            offers.extend([ident,cost,level,cls,0,0,0,0,0,0,0,0,0,0])
    for ident,name in [(116,'Aeven Class Skillmaster'),(124,'Anundo Class Skillmaster'),(144,'Padu Class Skillmaster')]:
        lines.extend([f'{ident}.name = {name}',f'{ident}.learn = '+','.join(map(str,offers))])
    lines.extend(['162.name = Bard','162.learn = 17,120,2,0,0,0,0,0,0,0,0,0,0,0'])
    return ('\n'.join(lines)+'\n').encode()

def build_shops(original):
    text=original.decode('latin1')
    def replace(key,value):
        nonlocal text
        pattern=r'^'+re.escape(key)+r'\s*=.*$';line=key+' = '+value
        text=re.sub(pattern,line,text,flags=re.M) if re.search(pattern,text,re.M) else text+'\n'+line+'\n'
    # Keep existing stocks and recipes. Aeven provides affordable starter roles.
    match=re.search(r'^15\.trade\s*=\s*(.*)$',text,re.M);a=list(map(int,match[1].split(',')));stock={a[j]:a[j:j+3] for j in range(0,len(a),3)}
    for ident,price in [(21,50),(29,50),(33,50),(297,100),(423,50),(511,600),(512,1800)]:stock.setdefault(ident,[ident,price,max(1,price//10)])
    replace('15.trade',','.join(str(n) for offer in stock.values() for n in offer))
    match=re.search(r'^33\.trade\s*=\s*(.*)$',text,re.M);existing=match[1].strip() if match else ''
    additions=[]
    for ident in range(513,543):
        if ident==533:continue
        tier=NEW_ITEM_TIERS[ident];price=(100,600,1800,4000,10000)[tier]
        additions.extend([ident,price,price//10])
    for ident,name,template,clas,role in NEW_ITEMS:
        if ident<544:continue
        tier=NEW_ITEM_TIERS[ident];price=100 if tier==0 else 900 if ident in SUPPORT and tier==2 else 5000 if ident in SUPPORT else 10000 if tier==4 else 4000
        additions.extend([ident,price,max(1,price//10)])
    # Reliable first upgrades; preserve rare crafted weapons as recipe rewards.
    for ident,price in [(35,600),(329,1800),(406,1800),(156,1800),(135,600),(155,1800)]:
        old=list(map(int,existing.split(','))) if existing else []
        if ident not in old[::3]:additions.extend([ident,price,price//10])
    replace('33.trade',existing+(',' if existing else '')+','.join(map(str,additions)))
    replace('304.craft','430,460,1,492,6,0,0,0,0,431,465,1,492,6,0,0,0,0')
    for npc,ids in [(36,list(range(493,496))+list(range(499,505))),(87,list(range(496,499))+list(range(505,511)))]:
        match=re.search(r'^'+str(npc)+r'\.craft\s*=\s*(.*)$',text,re.M);existing=match[1].strip() if match else ''
        new=[]
        for ident in ids:
            template=next(t for n,_,t,_,_ in NEW_ITEMS if n==ident)
            ingredient=template if ident<499 else 460 if ident%2 else 465
            new.extend([ident,ingredient,1,469,2,470,2,1,200 if ident<499 else 150])
        replace(f'{npc}.craft',existing+(',' if existing else '')+','.join(map(str,new)))
    for vendor,recipe in [(87,'533,38,1,253,10,278,4,1,150,436,533,1,278,10,1,200,0,0'),(15,'543,511,1,299,8,308,3,1,100')]:
        match=re.search(r'^'+str(vendor)+r'\.craft[ \t]*=[ \t]*(.*)$',text,re.M);existing=match[1].strip() if match else ''
        replace(f'{vendor}.craft',existing+(',' if existing else '')+recipe)
    replace(f"{EGGKEEPER['id']}.name",'Aeven Eggkeeper - bound spirit eggs')
    replace(f"{EGGKEEPER['id']}.trade",','.join(str(n) for ident in egg_stock() for n in (ident,EGGS[ident]['price'],0)))
    # Buying provides reliable death replacement; earned monster eggs remain bound.
    # Native recipe amounts are unsigned bytes and use EO char encoding.
    for value in re.findall(r'^\d+\.craft[ \t]*=[ \t]*(.*)$',text,re.M):
        if not value.strip():continue
        parts=list(map(int,value.split(',')))
        if len(parts)%9:raise ValueError('Invalid crafting recipe width')
        if any(not 0<=parts[j]<=252 for start in range(0,len(parts),9) for j in range(start+2,start+9,2)):
            raise ValueError('Craft ingredient count exceeds native wire capacity')
    return text.encode('latin1')

def build_drops(original):
    text=original.decode('latin1')
    for ident,egg in EGGS.items():
        key=str(egg['npc_id']);pattern=r'^'+key+r'[ \t]*=[ \t]*(.*)$';match=re.search(pattern,text,re.M)
        old=match[1].strip() if match else ''
        line=key+' = '+old+(', ' if old else '')+f"{ident},1,1,{egg['chance']}"
        text=re.sub(pattern,line,text,flags=re.M) if match else text+'\n'+line+'\n'
    return text.encode('latin1')

def drop_sources(text):
    result={}
    for npc,raw in re.findall(r'^(\d+)[ \t]*=[ \t]*(.*)$',text,re.M):
        if not raw.strip():continue
        values=[v.strip() for v in raw.split(',')]
        if len(values)%4:raise ValueError('Invalid monster drop width')
        for offset in range(0,len(values),4):
            if float(values[offset+3])>0:result.setdefault(int(values[offset]),[]).append(int(npc))
    return result

def build_quest(original):
    text=original.decode('latin1')
    text=text.replace('This is a temporary menu to set your class thru the quest-engine, will be better later on.','Choose your profession. Rebuild attributes free at a skill master; learned spells and earned points are kept.')
    choices=[('Priest','Priest: WIS healing and Holy Light'),('Magician','Magician: INT burst and area spells'),('Rogue','Rogue: AGI precision and evasion'),('Archer','Archer: AGI ranged attacks'),('Warrior','Warrior: STR and CON front line')]
    for key,label in choices:text=text.replace('Make me '+key,label)
    text=text.replace('rule \t\tInputNpc( 1 ) goto Priest','action AddNpcInput(4, 6, "Summoner: CHA spirit attacks and companions");\n    rule InputNpc(6) goto Summoner\n\n\trule \t\tInputNpc( 1 ) goto Priest')
    if 'goto Summoner' not in text:raise ValueError('Class quest layout changed')
    text+='\nstate Summoner\n{\n    action SetClass(7);\n    action Reset();\n}\n'
    return text.encode('latin1')

def configure(runtime):
    runtime=Path(runtime)
    if any((runtime/r).is_symlink() for r in ('data','data/pub')):raise ValueError('Materialize runtime data directories first')
    if any(marker not in (runtime/'etheos').read_bytes() for marker in (b'PetEggTiers',b'CombatProgression',b'OwnerScaledPets',b'ClassMobility')):raise ValueError('Install the combat-progression-capable native binary first')
    baseline=runtime/'data/balance-v1-baseline';manifest_path=runtime/'data/balance-v1-manifest.json'
    old_manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    if old_manifest:
        for rel,expected in old_manifest['installed'].items():
            if digest((runtime/rel).read_bytes())!=expected:raise ValueError('Balanced content changed since installation: '+rel)
    originals={rel:(baseline/rel).read_bytes() if (baseline/rel).exists() else (runtime/rel).read_bytes() for rel in INPUTS}
    originals['data/formulas.ini']=(baseline/'data/formulas.ini').read_bytes() if (baseline/'data/formulas.ini').exists() else (runtime/'data/formulas.ini').read_bytes()
    shops=build_shops(originals['data/aster-vale-shops.ini'])
    drops=build_drops(originals['data/aster-vale-drops.ini'])
    item_bytes,items=build_items(originals['data/pub/dat001.eif'],shops.decode('latin1'))
    for ident,npcs_dropping in drop_sources(drops.decode('latin1')).items():
        if str(ident) in items:items[str(ident)].setdefault('acquisition',{})['drop']=npcs_dropping
    npc_bytes,npcs=build_npcs(originals['data/pub/dtn001.enf'])
    class_bytes,classes=build_classes(originals['data/pub/dat001.ecf'])
    spell_bytes,spells=build_spells(originals['data/pub/dsl001.esf'])
    proposed={'data/aster-vale-drops.ini':drops,'data/pub/dat001.eif':item_bytes,'data/pub/dat001.ecf':class_bytes,'data/pub/dsl001.esf':spell_bytes,'data/pub/dtn001.enf':npc_bytes,'data/formulas.ini':formulas(originals['data/formulas.ini']),'data/aster-vale-skills.ini':build_skills(),'data/aster-vale-shops.ini':shops,'data/quests/00004.eqf':build_quest(originals['data/quests/00004.eqf'])}
    profile=dict(version=VERSION,levels=LEVELS,max_skill_level=10,classes=classes,spells=spells,items=items,npcs=npcs,class_identity=True,class_signatures=True,mortal_spirit_bonds=True,companions=COMPANIONS,eggs=EGGS,pet_tiers=TIERS,pet_roster=ROSTER,eggkeeper=EGGKEEPER)
    proposed['data/balance-profile.json']=(json.dumps(profile,indent=2)+'\n').encode()
    cfg=(runtime/'config.local.ini').read_text()
    values={'ClassMobility':'yes','OwnerScaledPets':'yes','CombatProgression':'yes','PetEggTiers':'yes','MortalSpiritBonds':'yes','ClassSignatureRules':'yes','PriestRegenRate':'0.02','PriestSittingRegenRate':'0.04','CompanionLifetimeSeconds':'0','ClassIdentityRules':'yes','BalanceRevamp':'yes','UseClassFormulas':'yes','MaxSkillLevel':'10','SkillsFile':'./data/aster-vale-skills.ini'}
    for ident,rate in TP_RECOVERY.items():
        values[f'Balance.{ident}.tp_regen']=str(rate)
    for ident,traits in BOWS.items():
        for key,value in traits.items():values[f'BalanceItem.{ident}.{key}']=str(value)
    for ident,bonus in ARROWS.items():values[f'BalanceItem.{ident}.range_bonus']=str(bonus)
    for ident in SHIELDS:values[f'BalanceItem.{ident}.warrior_shield']='yes'
    for ident,p in CLASSES.items():
        for key in ('spell_scale','heal_wis','heal_int','heal_cha'):values[f'Balance.{ident}.{key}']=str(p[key])
    values['Balance.3.area_multiplier']=str(CLASSES[3]['area_multiplier'])
    values['Balance.7.pk_spell_scale']=str(CLASSES[7]['pk_spell_scale'])
    for ident,p in SPELLS.items():
        _,level,allowed,*_,radius,cap=p
        for key,value in [('level',level),('classes',','.join(map(str,allowed))),('radius',radius),('targets',cap)]:values[f'BalanceSpell.{ident}.{key}']=str(value)
    for ident,item in items.items():
        values[f'BalanceItem.{ident}.backstab']='yes' if item.get('backstab') else 'no'
        values[f'BalanceItem.{ident}.classes']=','.join(map(str,item.get('allowed_classes',[])))
    for ident,pet in COMPANIONS.items():
        for key in ('npc_id','upkeep','power','accuracy','hit_cap'):values[f'BalancePetSpell.{ident}.{key}']=str(pet[key])
    for ident,egg in EGGS.items():
        values[f'BalanceEgg.{ident}.spell']=str(egg['spell_id'])
        values[f'BalanceEgg.{ident}.npc']=str(egg['npc_id'])
        values[f'BalanceEgg.{ident}.chance']=str(egg['chance'])
        values[f'BalancePetSpell.{egg["spell_id"]}.egg']=str(ident)
    for key,value in values.items():
        pattern=r'^'+re.escape(key)+r'\s*=.*$';line=f'{key} = {value}'.rstrip()
        cfg=re.sub(pattern,line,cfg,flags=re.M) if re.search(pattern,cfg,re.M) else cfg.rstrip()+'\n'+line+'\n'
    before={rel:(runtime/rel).read_bytes() if (runtime/rel).exists() else None for rel in proposed}
    before['config.local.ini']=(runtime/'config.local.ini').read_bytes()
    def write(rel,content):
        p=runtime/rel;p.parent.mkdir(parents=True,exist_ok=True);temp=p.with_suffix(p.suffix+'.balance-pending');temp.write_bytes(content);temp.chmod(0o600 if rel=='config.local.ini' else 0o644);temp.replace(p)
    try:
        for rel,content in originals.items():
            p=baseline/rel
            if not p.exists():p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(content)
        for rel,content in proposed.items():write(rel,content)
        write('config.local.ini',cfg.encode())
        manifest=dict(version=VERSION,installed={rel:digest(content) for rel,content in proposed.items()},original={rel:digest(content) for rel,content in originals.items()},new_item_ids=[i[0] for i in NEW_ITEMS]+list(EGGS),equipment_definitions=sum(10<=i['type']<=21 for i in items.values()),database_modified=False)
        write('data/balance-v1-manifest.json',(json.dumps(manifest,indent=2)+'\n').encode())
    except BaseException:
        for rel,content in before.items():
            if content is None:(runtime/rel).unlink(missing_ok=True)
            else:write(rel,content)
        raise
    return manifest

def migrate_pet_bonds(database):
    """Keep one legacy bond, return extra unlocks as bound eggs, refund training."""
    egg_by_spell={e['spell_id']:ident for ident,e in EGGS.items()}
    rank={e['spell_id']:e['level'] for e in EGGS.values()}
    report=dict(characters_changed=0,extra_bonds_returned_as_eggs=0,skill_points_refunded=0)
    with closing(sqlite3.connect(database)) as db,db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('CREATE TABLE IF NOT EXISTS aster_spirit_bond_migrations(version INTEGER PRIMARY KEY)')
        if db.execute('SELECT 1 FROM aster_spirit_bond_migrations WHERE version=?',(VERSION,)).fetchone():return dict(already_applied=True,**report)
        for name,raw_spells,inventory,points in db.execute('SELECT name,spells,inventory,skillpoints FROM characters').fetchall():
            spells=[tuple(map(int,p.split(','))) for p in (raw_spells or '').split(';') if p]
            if any(len(s)!=2 or s[0]<=0 or s[1]<0 for s in spells):raise ValueError('Malformed spell data; bond migration refused')
            bonds=[s for s in spells if s[0] in egg_by_spell]
            if not bonds:continue
            if len({s[0] for s in spells})!=len(spells):raise ValueError('Duplicate spell data; bond migration refused')
            keep=max(bonds,key=lambda s:rank[s[0]])[0]
            refunded=sum(s[1] for s in bonds)
            bag=Counter()
            for p in (inventory or '').split(';'):
                if not p:continue
                ident,amount=map(int,p.split(','))
                if ident<=0 or amount<=0:raise ValueError('Malformed inventory; bond migration refused')
                bag[ident]+=amount
            for ident,_ in bonds:
                if ident!=keep:bag[egg_by_spell[ident]]+=1
            if points+refunded>64000:raise ValueError('Skill point refund exceeds native capacity')
            replacement=''.join(f'{ident},{0 if ident in egg_by_spell else level};' for ident,level in spells if ident not in egg_by_spell or ident==keep)
            if len(bonds)>1 or refunded:
                db.execute('UPDATE characters SET spells=?,inventory=?,skillpoints=? WHERE name=?',(replacement,''.join(f'{i},{n};' for i,n in bag.items()),points+refunded,name))
                report['characters_changed']+=1;report['extra_bonds_returned_as_eggs']+=len(bonds)-1;report['skill_points_refunded']+=refunded
        db.execute('INSERT INTO aster_spirit_bond_migrations VALUES (?)',(VERSION,))
    return dict(already_applied=False,**report)

def migrate_equipment(database, profile):
    """Stopped-world, retry-safe movement of newly ineligible worn gear to bags."""
    items=profile['items'];classes=profile['classes'];changed=0
    with closing(sqlite3.connect(database)) as db, db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('CREATE TABLE IF NOT EXISTS aster_balance_migrations (version INTEGER PRIMARY KEY, moved_items INTEGER NOT NULL)')
        if db.execute('SELECT 1 FROM aster_balance_migrations WHERE version=?',(VERSION,)).fetchone():return dict(already_applied=True,moved_items=0)
        for name,level,clas,gender,admin,inv,doll in db.execute('SELECT name,level,class,gender,admin,inventory,paperdoll FROM characters').fetchall():
            if admin>0:continue
            bag=Counter()
            for part in (inv or '').split(';'):
                if part:
                    ident,amount=map(int,part.split(','))
                    if ident<=0 or amount<=0:raise ValueError('Malformed inventory; migration refused')
                    bag[ident]+=amount
            worn=list(map(int,doll.rstrip(',').split(',')))
            if len(worn)!=15:raise ValueError('Malformed equipment; migration refused')
            before=bag+Counter(i for i in worn if i);moved=False;base=classes.get(str(clas),{}).get('base',0)
            for n,ident in enumerate(worn):
                if not ident:continue
                i=items.get(str(ident))
                if not i:raise ValueError('Unknown worn item; migration refused')
                req=i['class_requirement'];allowed=i.get('allowed_classes',[])
                if (allowed and clas not in allowed and base not in allowed) or level<i['level_requirement'] or (req and req not in (clas,base)) or (i['type']==12 and i['gender']!=gender):
                    bag[ident]+=1;worn[n]=0;moved=True;changed+=1
            if before!=bag+Counter(i for i in worn if i):raise AssertionError('Item conservation failed')
            if moved:
                db.execute('UPDATE characters SET inventory=?,paperdoll=? WHERE name=?',(''.join(f'{i},{a};' for i,a in bag.items()),','.join(map(str,worn)),name))
        db.execute('INSERT INTO aster_balance_migrations VALUES (?,?)',(VERSION,changed))
    return dict(already_applied=False,moved_items=changed)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',required=True,type=Path);p.add_argument('--world-stopped',required=True,action='store_true');p.add_argument('--migrate-characters',action='store_true');a=p.parse_args()
    result=configure(a.runtime)
    if a.migrate_characters:
        result['migration']=migrate_equipment(a.runtime/'database.sdb',json.loads((a.runtime/'data/balance-profile.json').read_text()))
        result['pet_bond_migration']=migrate_pet_bonds(a.runtime/'database.sdb')
    print(json.dumps(result,indent=2))
