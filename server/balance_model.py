"""Deterministic balance probes, matching native reversed-operand RPN rules.

Models are pre-critical expectations, not measurements of player farming time.
Real native-session checks independently exercise the same class and spell paths.
"""
import math
from balance_profile import ATTRIBUTES, CLASSES
from class_signatures import SUPPORT

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
        if key=='armor' and clas==6:out[key]+=sum(i.get('armor',0) for i in equipment if i.get('warrior_shield_multiplier')==2)
    if not out['max_damage']:out['max_damage']=1
    return out

def spell_preview(clas,spell,s,trained=0):
    p=CLASSES[clas];bonus=2*min(10,trained)
    if spell['type']==0:
        return dict(heal=spell['hp']+int(s['wisdom']*p['heal_wis']+s['intelligence']*p['heal_int']+s['charisma']*p['heal_cha'])+bonus)
    return {k:int((int(s[key]*p['spell_scale'])+spell[k]+bonus)*spell.get('area_scale',1)*(p.get('single_target_multiplier',1) if not spell.get('area_radius') else 1)) for k,key in [('min_damage','min_damage'),('max_damage','max_damage')]}

def hit_chance(accuracy,evade):return min(.95,max(.35,accuracy/(10+accuracy*.5+evade)))
def expected_hit(low,high,armor):return sum(max(1,int(n*100/(100+2*armor))) for n in range(low,high+1))/(high-low+1)

def pet_expected_damage(low,high,power,armor):
    values=[]
    for roll in range(low,high+1):
        scaled=max(0,roll)*power;whole=math.floor(scaled);fraction=scaled-whole
        values.append(expected_hit(whole,whole,armor)*(1-fraction)+expected_hit(whole+1,whole+1,armor)*fraction)
    return sum(values)/len(values)

def sustained_damage(basic,spell_dps,spell_tp,cycle,max_tp,regen,pet_dps=0,pet_call=0,pet_upkeep=0):
    net=pet_upkeep/2-regen
    uptime=min(60,max(0,(max_tp-pet_call)/net)) if pet_dps and net>0 else 60 if pet_dps else 0
    budget=max(0,max_tp+60*regen-pet_call-uptime*pet_upkeep/2)
    spell_seconds=min(60,budget/spell_tp*cycle) if spell_tp else 0
    return dict(sustained_60_dps=round(basic+max(0,spell_dps-basic)*spell_seconds/60+pet_dps*uptime/60,2),spell_seconds_in_60=round(spell_seconds,2),tp_available_for_offense_in_60=round(budget,2),pet_uptime_in_60=round(uptime,2))

GEAR = {
    2:([33,23,362,534,390,495],[549,531,406,525,519,499]),
    3:([29,205,290,389,544,493],[551,128,156,523,521,501]),
    4:([21,26,238,327,436,497],[553,142,539,545,527,505]),
    5:([297,511,512,316,457,496],[555,541,414,547,529,507]),
    6:([21,19,37,287,281,498],[557,135,155,460,387,509]),
    7:([29,35,329,513,514,494],[559,535,537,515,517,503]),
}

def loadout(profile,clas,level,index=None):
    index=(1,8,15,25,35,45).index(level) if index is None else index
    ids=[arr[index] for arr in GEAR[clas]]
    if clas==5:ids.append(423)
    tier=4 if level>=35 else 2 if level>=15 else 0
    if tier:
        supporting=[ident for ident,entry in SUPPORT.items() if entry['clas']==clas and entry['tier']==tier]
        ids+=supporting+[supporting[-1]] # Both ring slots use the same legal definition.
    else:ids += [182,80,58,41,41] # Ordinary, obtainable starter accessories.
    return [profile['items'][str(ident)] for ident in ids]

def benchmarks(profile):
    spells=profile['spells'];rows=[]
    for level in (1,8,15,25,35,45):
        for clas in (2,3,4,5,6,7):
            gear=loadout(profile,clas,level);weapon,body=gear[:2]
            if any(i['level_requirement']>level or (i.get('allowed_classes') and clas not in i['allowed_classes']) for i in gear):raise ValueError(f'Invalid benchmark loadout {clas}/{level}')
            s=stats(clas,level,allocation(clas,level),gear)
            target_armor=level*.4;target_evade=level*.6
            shot=weapon.get('shot_power',1);speed=weapon.get('attack_speed',1)
            basic=expected_hit(max(0,int(s['min_damage']*shot)),max(1,int(s['max_damage']*shot)),target_armor)*hit_chance(s['accuracy'],target_evade)/(.5/speed)
            candidates=[]
            for spell in spells.values():
                if spell['type']!=1 or spell.get('effect_kind')=='companion' or spell.get('area_radius') or clas not in spell.get('allowed_classes',[]) or spell['level_requirement']>level:continue
                power=spell_preview(clas,spell,s,0);cycle=max(.96,spell['cast_time']*.48+.48)
                dps=expected_hit(power['min_damage'],power['max_damage'],target_armor)*hit_chance(s['accuracy'],target_evade)/cycle
                candidates.append((dps,spell['id']))
            spell_dps,ident=max(candidates) if candidates else (0,0)
            spell=spells.get(str(ident),dict(tp=0))
            heal=spell_preview(clas,spells['1'],s)['heal'] if clas==2 else 0
            heals=[(spell_preview(clas,h,s)['heal'],h['id'],h['tp']) for h in spells.values() if h['type']==0 and clas in h.get('allowed_classes',[]) and h['level_requirement']<=level and h['target'] == 0] if clas==2 else []
            party_heal,heal_id,heal_tp=max(heals) if heals else (0,0,0)
            area=[]
            for a in spells.values():
                if clas not in a.get('allowed_classes',[]) or a['level_requirement']>level or not a.get('area_radius'):continue
                power=spell_preview(clas,a,s,0)
                per_target=expected_hit(power['min_damage'],power['max_damage'],target_armor)*hit_chance(s['accuracy'],target_evade)/max(.96,a['cast_time']*.48+.48)
                area.append((per_target*a['area_targets'],a['id'],a['area_targets']))
            area_dps,area_id,area_targets=max(area) if area else (0,0,0)
            close_basic=basic*weapon.get('close_attack_speed',speed)/speed
            walking_multiplier=2 if clas==4 else 1
            eligible=[pet for spell_id,pet in profile['companions'].items() if pet['npc_id']>0 and profile['spells'][str(spell_id)]['level_requirement']<=level]
            pet=max(eligible,key=lambda p:(p['power'],p.get('accuracy',0)),default=dict(power=0))
            pet_power=pet['power']
            pet_damage=pet_expected_damage(s['min_damage'],s['max_damage'],pet_power,target_armor)
            pet_hit=min(pet.get('hit_cap',.95),hit_chance(s['accuracy']+pet.get('accuracy',0),target_evade))
            pet_dps=pet_damage*pet_hit if clas==7 and pet_power else 0
            burst=max(basic,spell_dps)+pet_dps
            from combat_progression import TP_RECOVERY
            regen=max(1,int(s['max_tp']*TP_RECOVERY[clas]))/2 if clas in TP_RECOVERY else s['max_tp']*.1/90
            call=profile['pet_tiers'][pet['tier']]['tp'] if clas==7 and pet_power else 0
            sustained=sustained_damage(basic,spell_dps,spell['tp'],max(.96,spell.get('cast_time',1)*.48+.48),s['max_tp'],regen,pet_dps,call,pet.get('upkeep',0) if pet_dps else 0)
            rows.append(dict(**sustained,class_id=clas,role=CLASSES[clas]['name'],level=level,weapon_id=weapon['id'],body_id=body['id'],equipment_ids=[i['id'] for i in gear],**s,basic_dps=round(basic,2),spell_dps=round(spell_dps,2),burst_dps=round(burst,2),backstab_dps=round(burst*1.75,2) if clas==4 else 0,passive_hp_per_second=max(1,int(s['max_hp']*.02)) if clas==2 else 0,companion_dps=round(pet_dps,2),spell_id=ident,spell_tp=spell['tp'],spell_casts_from_full=s['max_tp']//spell['tp'] if spell['tp'] else 0,heal_self=heal,heal_other=party_heal,heal_other_spell_id=heal_id,heal_other_tp=heal_tp,close_basic_dps=round(close_basic,2),area_total_dps=round(area_dps,2),area_spell_id=area_id,area_targets=area_targets,walking_multiplier=walking_multiplier,model='Weapon/body, head, boots, gloves and two rings, plus basic Archer arrows; 60/25/15 allocation. Target armour 0.4xlevel and evade 0.6xlevel. Front-facing single-target expectations, no criticals or kiting; Summoner has an adjacent commanded spirit. Backstab is separate and conditional. Burst assumes TP available; it is not sustained farming DPS.'))
    return rows
