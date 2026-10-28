"""Create the explicitly requested Summoner sibling in a stopped, backed-up world.

Never changes an existing character or account. Repeating a grant is refused.
"""
from collections import Counter
from contextlib import closing
import argparse,json,re,sqlite3
from pathlib import Path
from balance_model import allocation,stats

SLOTS=('boots','accessory','gloves','belt','armor','necklace','head','offhand','weapon','ring1','ring2','armlet1','armlet2','bracer1','bracer2')

def build_kit(profile):
    items=profile['items'];excluded={204,208,384,445,446,491}
    def legal(i):
        return i['id'] not in excluded and i['level_requirement']<=50 and i['class_requirement'] in (0,7) and (not i.get('allowed_classes') or 7 in i['allowed_classes'])
    # Full endgame outfit, plus common pieces for every remaining paperdoll slot.
    equipped=[606,71,607,43,503,50,605,416,494,608,608,39,39,54,54]
    assert all(legal(items[str(i)]) for i in equipped)
    collection=Counter()
    for i in items.values():
        if not legal(i):continue
        own_class=7 in i.get('allowed_classes',[])
        shared_caster=own_class and i['type']==12 and i['gender']==1
        if i['type']==10 or shared_caster or (own_class and i['type'] in (13,14,15)) or 16<=i['type']<=21:
            collection[i['id']]=2 if i['type'] in (19,20,21) else 1
    collection|=Counter(equipped)
    remaining=collection-Counter(equipped)
    bag=Counter({1:1_000_000,375:5,376:5,**{int(i):1 for i in profile['eggs']}})
    bank=Counter({375:45,376:45,624:5})
    attributes=allocation(7,50);max_weight=70+attributes['strength']
    def weight(stock):return sum(items[str(i)]['weight']*n for i,n in stock.items())
    equipped_weight=weight(Counter(equipped))
    # Keep ten weight free for loot and withdrawing a different weapon/outfit.
    for ident,amount in sorted(remaining.items(),key=lambda row:(items[str(row[0])]['type']!=10,-items[str(row[0])]['level_requirement'],row[0])):
        for _ in range(amount):
            if equipped_weight+weight(bag)+items[str(ident)]['weight']<=max_weight-10:bag[ident]+=1
            else:bank[ident]+=1
    assert len(bank)<=60 and all(n<=200 for n in bank.values()),'Test collection exceeds the fully upgraded locker'
    power=stats(7,50,attributes,[items[str(i)] for i in equipped])
    encode=lambda stock:''.join(f'{i},{n};' for i,n in sorted(stock.items()) if n)
    spells=[s['id'] for s in profile['spells'].values() if s.get('allowed_classes')==[7] and s['level_requirement']<=50 and (s.get('effect_kind')!='companion' or s.get('companion',{}).get('npc_id')==-1)]
    fields=dict(admin=0,**{'class':7},gender=1,race=0,hairstyle=5,haircolor=2,map=5,x=35,y=45,direction=0,level=50,exp=16_637_500,hp=power['max_hp'],tp=power['max_tp'],str=attributes['strength'],int=attributes['intelligence'],wis=attributes['wisdom'],agi=attributes['agility'],con=attributes['constitution'],cha=attributes['charisma'],statpoints=0,skillpoints=150,karma=1000,bankmax=7,goldbank=0,inventory=encode(bag),bank=encode(bank),paperdoll=','.join(map(str,equipped))+',',spells=''.join(f'{i},0;' for i in sorted(spells)),quest='',vars='')
    report=dict(level=50,class_name='Summoner',gold=1_000_000,allocated_attributes=attributes,skill_points_unspent=150,max_hp=power['max_hp'],max_tp=power['max_tp'],weight=equipped_weight+weight(bag),max_weight=max_weight,locker_capacity=60,locker_slots_used=len(bank),equipped=[dict(slot=slot,id=ident,name=items[str(ident)]['name']) for slot,ident in zip(SLOTS,equipped)],bag=[dict(id=i,name=items[str(i)]['name'],amount=n) for i,n in sorted(bag.items())],locker=[dict(id=i,name=items[str(i)]['name'],amount=n) for i,n in sorted(bank.items())],pet_bond_initially_empty=True,all_sixteen_eggs_available=True)
    return fields,report

def provision(database,profile,name='summontest',beside='skylar',max_characters=3):
    if not re.fullmatch('[a-z]{4,12}',name):raise ValueError('Use a valid lower-case character name')
    fields,report=build_kit(profile)
    with closing(sqlite3.connect(database)) as db,db:
        db.execute('BEGIN IMMEDIATE')
        source=db.execute('SELECT account FROM characters WHERE lower(name)=?',(beside.lower(),)).fetchall()
        if len(source)!=1 or not source[0][0]:raise ValueError('Reference character account is ambiguous or missing')
        account=source[0][0]
        if db.execute('SELECT 1 FROM characters WHERE lower(name)=?',(name,)).fetchone():raise ValueError('Character already exists; refusing to overwrite or repeat the grant')
        if db.execute('SELECT COUNT(*) FROM characters WHERE account=?',(account,)).fetchone()[0]>=max_characters:raise ValueError('The account has no free character slot')
        before=db.execute('SELECT * FROM characters ORDER BY name').fetchall();accounts=db.execute('SELECT * FROM accounts ORDER BY username').fetchall()
        fields=dict(name=name,account=account,**fields);columns=list(fields)
        db.execute('INSERT INTO characters ('+','.join('"'+k+'"' for k in columns)+') VALUES ('+','.join('?' for _ in columns)+')',tuple(fields[k] for k in columns))
        assert db.execute('SELECT * FROM characters WHERE name<>? ORDER BY name',(name,)).fetchall()==before
        assert db.execute('SELECT * FROM accounts ORDER BY username').fetchall()==accounts
    return dict(result='passed',character_name=name,same_account_as=beside,existing_characters_and_accounts_unchanged=True,**report)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--world-stopped',required=True,action='store_true');p.add_argument('--name',default='summontest');p.add_argument('--beside',default='skylar');a=p.parse_args()
    print(json.dumps(provision(a.runtime/'database.sdb',json.loads((a.runtime/'data/balance-profile.json').read_text()),a.name,a.beside),indent=2))
