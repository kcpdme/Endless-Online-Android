"""Deterministic balance probes, matching native reversed-operand RPN rules.

Models are pre-critical expectations, not measurements of player farming time.
Real native-session checks independently exercise the same class and spell paths.
"""
import math
from balance_profile import ATTRIBUTES, CLASSES

def evaluate(expr, values):
    stack=[]
    for token in expr.split():
        if token in ('+','-','*','/','max','min','?'):
            args=[stack.pop() for _ in range(3 if token=='?' else 2)]
            stack.append({'+':lambda:args[0]+args[1],'-':lambda:args[0]-args[1],'*':lambda:args[0]*args[1],'/':lambda:args[0]/args[1],'max':lambda:max(args),'min':lambda:min(args),'?':lambda:args[1] if args[0] else args[2]}[token]())
        else:stack.append(float(values[token]) if token in values else float(token))
    if len(stack)!=1:raise ValueError('RPN expression did not resolve')
    return stack[0]

def allocation(clas, level):
    primary,secondary={2:('wisdom','intelligence'),3:('intelligence','wisdom'),4:('agility','strength'),5:('agility','strength'),6:('strength','agility'),7:('charisma','intelligence')}[clas]
    total=level*3;result={a:0 for a in ATTRIBUTES}
    result[primary]=math.floor(total*.6);result['constitution']=math.floor(total*.25);result[secondary]=total-result[primary]-result['constitution']
    return result

def stats(clas,level,base,equipment):
    attributes={k:base.get(k,0)+CLASSES[clas]['base_attributes'].get(k,0)+sum(i.get(k,0) for i in equipment) for k in ATTRIBUTES}
    values=dict(zip(('str','int','wis','agi','con','cha'),(attributes[k] for k in ATTRIBUTES)),level=level)
    p=CLASSES[clas];out=dict(attributes)
    for key,formula in [('min_damage','damage'),('max_damage','damage'),('accuracy','accuracy'),('evade','evade'),('armor','defence'),('max_hp','hp'),('max_tp','tp')]:
        item_key={'max_hp':'hp','max_tp':'tp'}.get(key,key)
        out[key]=int(evaluate(p[formula],values))+sum(i.get(item_key,0) for i in equipment)
    if not out['max_damage']:out['max_damage']=1
    return out

def spell_preview(clas,spell,s,trained=0):
    p=CLASSES[clas];bonus=2*min(10,trained)
    if spell['type']==0:
        return dict(heal=spell['hp']+int(s['wisdom']*p['heal_wis']+s['intelligence']*p['heal_int']+s['charisma']*p['heal_cha'])+bonus)
    return {k:int((int(s[key]*p['spell_scale'])+spell[k]+bonus)*spell.get('area_scale',1)) for k,key in [('min_damage','min_damage'),('max_damage','max_damage')]}

def hit_chance(accuracy,evade):return min(.95,max(.35,accuracy/(10+accuracy*.5+evade)))
def expected_hit(low,high,armor):return sum(max(1,int(n*100/(100+2*armor))) for n in range(low,high+1))/(high-low+1)

GEAR = {
    2:([33,23,362,534,390,495],[131,531,406,525,519,499]),
    3:([29,205,290,389,389,493],[132,128,156,523,521,501]),
    4:([21,26,238,327,436,497],[144,142,539,460,527,505]),
    5:([297,511,512,316,457,496],[144,541,414,460,529,507]),
    6:([21,19,37,287,281,498],[144,135,155,460,387,509]),
    7:([29,35,329,513,514,494],[132,535,537,515,517,503]),
}

def benchmarks(profile):
    items=profile['items'];spells=profile['spells'];rows=[]
    for index,level in enumerate((1,8,15,25,35,45)):
        for clas in (2,3,4,5,6,7):
            weapon,body=(arr[index] for arr in GEAR[clas]);gear=[items[str(weapon)],items[str(body)]]
            if clas==5:gear.append(items['423'])
            if any(i['level_requirement']>level or i['class_requirement'] not in (0,clas) for i in gear):raise ValueError(f'Invalid benchmark loadout {clas}/{level}')
            s=stats(clas,level,allocation(clas,level),gear)
            target_armor=level*.4;target_evade=level*.6
            basic=expected_hit(s['min_damage'],s['max_damage'],target_armor)*hit_chance(s['accuracy'],target_evade)/.5
            ident={2:22,3:4 if level<8 else 5 if level<15 else 10 if level<25 else 15 if level<35 else 19 if level<45 else 9,4:12 if level<25 else 30,5:13 if level<25 else 36,6:32 if level<35 else 38,7:23 if level<15 else 24 if level<25 else 26 if level<45 else 29}[clas]
            spell=spells[str(ident)];power=spell_preview(clas,spell,s,0)
            legal=spell['level_requirement']<=level
            cycle=max(.96,spell['cast_time']*.48+.48)
            spell_dps=expected_hit(power['min_damage'],power['max_damage'],target_armor)*hit_chance(s['accuracy'],target_evade)/cycle if legal else 0
            heal=spell_preview(clas,spells['1'],s)['heal'] if clas==2 else 0
            pet_power=1 if level<25 else 1.15 if level<40 else 1.3
            pet_base=int((5+level*.3+s['charisma']*.22+s['intelligence']*.12)*pet_power)
            pet_dps=expected_hit(max(1,pet_base-2),pet_base+2,target_armor)*hit_chance(s['accuracy'],target_evade) if clas==7 and level>=8 else 0
            rows.append(dict(class_id=clas,role=CLASSES[clas]['name'],level=level,weapon_id=weapon,body_id=body,**s,basic_dps=round(basic,2),spell_dps=round(spell_dps,2),burst_dps=round(max(basic,spell_dps)+pet_dps,2),companion_dps=round(pet_dps,2),spell_id=ident,spell_tp=spell['tp'],spell_casts_from_full=s['max_tp']//spell['tp'],heal_self=heal,model='Weapon/body plus basic Archer arrows, 60/25/15 stat split; target armour 0.4×level and evade 0.6×level; no criticals, buffs, kiting or other slots. Summoner includes an adjacent, commanded spirit; burst assumes TP is available; it is not sustained DPS or farming speed.'))
    return rows
