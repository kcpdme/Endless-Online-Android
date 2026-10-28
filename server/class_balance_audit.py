"""Full-slot, weight-valid class comparisons. Estimates, not simulated player skill."""
import math
from balance_model import stats,allocation,spell_preview,hit_chance,expected_hit,pet_expected_damage,loadout,sustained_damage
from balance_audit import legal,obtainable,audit
from combat_progression import TP_RECOVERY
from balance_profile import CLASSES,ENCOUNTERS,LEVELS
SLOTS={'weapon':10,'armor':12,'head':13,'boots':14,'gloves':15,'offhand':11,'accessory':16,'belt':17,'necklace':18,'ring1':19,'ring2':19,'armlet1':20,'armlet2':20,'bracer1':21,'bracer2':21}

def metrics(profile,clas,level,gear,trained=0,armor=None,evade=None):
    s=stats(clas,level,allocation(clas,level),gear);weapon=next((i for i in gear if i['type']==10),{})
    armor=level*.4 if armor is None else armor;evade=level*.6 if evade is None else evade
    hit=hit_chance(s['accuracy'],evade);shot=weapon.get('shot_power',1);speed=weapon.get('attack_speed',1)
    basic=expected_hit(max(0,int(s['min_damage']*shot)),max(1,int(s['max_damage']*shot)),armor)*hit/(.5/speed)
    candidates=[];areas=[];heals=[]
    for spell in profile['spells'].values():
        if clas not in spell.get('allowed_classes',[]) or spell['level_requirement']>level or spell.get('effect_kind')=='companion':continue
        power=spell_preview(clas,spell,s,trained);cycle=max(.96,spell['cast_time']*.48+.48)
        if spell['type']==0:
            heals.append(dict(id=spell['id'],heal=power['heal'],cycle=cycle,tp=spell['tp']));continue
        if spell['type']!=1:continue
        dps=expected_hit(power['min_damage'],power['max_damage'],armor)*hit/cycle
        row=dict(id=spell['id'],dps=dps,cycle=cycle,tp=spell['tp'])
        if spell.get('area_radius'):areas.append(dict(row,total=dps*spell['area_targets'],targets=spell['area_targets']))
        else:candidates.append(row)
    best=max(candidates,key=lambda a:a['dps'],default=dict(id=0,dps=0,cycle=.96,tp=0))
    regen=max(1,int(s['max_tp']*TP_RECOVERY[clas]))/2 if clas in TP_RECOVERY else s['max_tp']*.1/90
    eligible=[(spell_id,pet) for spell_id,pet in profile['companions'].items() if pet['npc_id']>0 and profile['spells'][str(spell_id)]['level_requirement']<=level]
    spell_id,pet=max(eligible,key=lambda a:a[1]['power'],default=(0,dict(power=0,upkeep=0)))
    pet_dps=0;call=0;pet_uptime=0
    if clas==7 and pet['power']:
        pet_dps=pet_expected_damage(s['min_damage'],s['max_damage'],pet['power'],armor)*min(pet['hit_cap'],hit_chance(s['accuracy']+pet['accuracy'],evade))
        call=profile['spells'][str(spell_id)]['tp'];net=pet['upkeep']/2-regen
        pet_uptime=min(60,max(0,(s['max_tp']-call)/net)) if net>0 else 60
    sustained=sustained_damage(basic,best['dps'],best['tp'],best['cycle'],s['max_tp'],regen,pet_dps,call,pet['upkeep'] if pet_dps else 0)
    tp_budget=sustained['tp_available_for_offense_in_60'];spell_seconds=sustained['spell_seconds_in_60'];pet_uptime=sustained['pet_uptime_in_60']
    burst=max(basic,best['dps'])+pet_dps
    heal60=max((h['heal']*min(60/h['cycle'],(s['max_tp']+60*regen)/h['tp'])/60 for h in heals if h['tp']),default=0)
    enemy_id,(enemy_level,enemy_hp,enemy_low,enemy_high,enemy_acc,enemy_evade,enemy_armor,_) = max(((i,e) for i,e in ENCOUNTERS.items() if e[0]<=level),key=lambda a:(a[1][0],-a[1][1]))
    incoming=expected_hit(enemy_low,enemy_high,s['armor'])*hit_chance(enemy_acc,s['evade'])
    hp_regen=max(1,int(s['max_hp']*.02)) if clas==2 else 0
    ehp=s['max_hp']/max(.01,incoming)
    return dict(**s,burst_dps=round(burst,2),basic_dps=round(basic,2),sustained_60_dps=sustained['sustained_60_dps'],conditional_rear_dps=round(burst*1.75,2) if clas==4 and weapon.get('backstab') else 0,close_basic_dps=round(basic*weapon.get('close_attack_speed',speed)/speed,2),area_total_dps=round(max((a['total'] for a in areas),default=0),2),area_targets=max((a['targets'] for a in areas),default=0),passive_hp_per_second=hp_regen,healing_60_hps=round(heal60,2),incoming_hit_damage=round(expected_hit(enemy_low,enemy_high,s['armor']),2),incoming_hit_chance=round(hit_chance(enemy_acc,s['evade']),4),incoming_dps_one_attack_per_second=round(incoming,2),survival_seconds_without_healing=round(ehp,2),model_enemy_id=enemy_id,spell_id=best['id'],spell_dps=round(best['dps'],2),spell_seconds_in_60=round(spell_seconds,2),tp_available_for_offense_in_60=round(tp_budget,2),pet_dps=round(pet_dps,2),pet_uptime_in_60=round(pet_uptime,2),tp_regen_per_second=regen,weight=sum(i['weight'] for i in gear),capacity=min(250,70+allocation(clas,level)['strength']))

def compatible(rows):
    weapon=rows.get('weapon',{});offhand=rows.get('offhand',{})
    if weapon.get('subtype')==1:return offhand.get('subtype')==2
    if offhand.get('subtype')==2:return False
    return weapon.get('subtype')!=4 or not offhand or offhand.get('subtype')==3

def full_loadout(profile,clas,level):
    base=loadout(profile,clas,level);rows={}
    types={v:k for k,v in SLOTS.items()}
    for i in base:
        slot=types[i['type']]
        if i['type']==19:slot='ring1' if 'ring1' not in rows else 'ring2'
        rows[slot]=i
    for slot,typ in SLOTS.items():
        choices=[i for i in profile['items'].values() if i['type']==typ and legal(i,clas,level,1) and obtainable(i)]
        if slot not in rows:
            choices=[i for i in choices if i['subtype']!=2] if slot=='offhand' and clas!=5 else choices
            rows[slot]=max(choices,key=lambda i:(i['hp']+i['tp'],i['armor']),default={})
    return {k:v for k,v in rows.items() if v}

def optimized(profile,clas,level,objective):
    rows=full_loadout(profile,clas,level)
    # Coordinate ascent through every obtainable slot; repeated rings/bracers are legal.
    # It is an outlier search, not a claim of exhaustive global optimization.
    def score(r):
        gear=list(r.values());m=metrics(profile,clas,level,gear)
        if not compatible(r) or m['weight']>m['capacity']:return -1
        return m['sustained_60_dps'] if objective=='damage' else m['survival_seconds_without_healing']
    value=score(rows)
    for _ in range(3):
        changed=False
        for slot,typ in SLOTS.items():
            candidates=[i for i in profile['items'].values() if i['type']==typ and legal(i,clas,level,1) and obtainable(i)]
            if slot=='offhand':candidates=[{}]+candidates
            for item in candidates:
                trial=dict(rows)
                if item:trial[slot]=item
                else:trial.pop(slot,None)
                v=score(trial)
                if v>value+1e-7:rows=trial;value=v;changed=True
        if not changed:break
    return rows

def review(profile):
    rows=[];issues=[]
    for level in LEVELS:
        for clas in range(2,8):
            for build in ('standard','damage','defence'):
                equipment=full_loadout(profile,clas,level) if build=='standard' else optimized(profile,clas,level,build)
                m=metrics(profile,clas,level,list(equipment.values()))
                if m['weight']>m['capacity']:issues.append(f'{clas}/{level}/{build}: overweight comparison kit')
                rows.append(dict(class_id=clas,role=CLASSES[clas]['name'],level=level,build=build,equipment={k:i['id'] for k,i in equipment.items()},**m))
    progression=[]
    for clas in range(2,8):
        prev=None
        for level in LEVELS:
            row=next(r for r in rows if r['class_id']==clas and r['level']==level and r['build']=='damage')
            if prev and row['sustained_60_dps']<=prev['sustained_60_dps']:issues.append(f'{clas}/{level}: sustained progression regressed')
            prev=row
    dominance=[]
    for level in (15,25,35,45):
        cohort=[r for r in rows if r['level']==level and r['build']=='damage']
        for a in cohort:
            for b in cohort:
                axes=('sustained_60_dps','survival_seconds_without_healing','area_total_dps','healing_60_hps','passive_hp_per_second')
                if a['class_id']!=b['class_id'] and all(a[k]>=b[k] for k in axes) and any(a[k]>b[k] for k in axes):dominance.append(dict(level=level,stronger=a['role'],other=b['role'],scope='stationary damage build only; excludes range, walking speed, conditional backstabs, shields selected for defence, and pet retaliation'))
    return dict(version=profile['version'],result='passed' if not issues else 'failed',issues=issues,builds=rows,stationary_dominance_observations=dominance,scope='108 full-slot standard/damage/defence builds, levels 1/8/15/25/35/45, male body, 60/25/15 allocation, untrained spells. Coordinate ascent is an outlier search, not an exhaustive optimum. Common items, shields, two rings, two armlets and two bracers are included. Weight must fit. Sustained 60s uses full starting TP, standing recovery and pet call/upkeep; offensive casting and healing budgets are alternatives, not simultaneous. Damage/area calculations use reference armour/evasion; defence uses a level-appropriate installed encounter at one incoming attack per second. Movement, range, misses in player targeting and time reaching enemies are not simulated.')

if __name__=='__main__':
    import argparse,json
    from pathlib import Path
    p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=review(json.loads((a.runtime/'data/balance-profile.json').read_text()));a.report.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(dict(result=r['result'],issues=r['issues'],builds=len(r['builds']))));raise SystemExit(bool(r['issues']))
