"""Pet appearances share a tier's combat budget, price and TP economy."""

TIERS = {
    'normal': dict(name='Normal',rank=0,level=5,price=100,tp=10,chant=1,upkeep=2,power=.45,accuracy=0,hit_cap=.82,color='b8c5c9'),
    'rare': dict(name='Rare',rank=1,level=10,price=6000,tp=18,chant=1,upkeep=5,power=.70,accuracy=3,hit_cap=.86,color='78b9ee'),
    'epic': dict(name='Epic',rank=2,level=20,price=20000,tp=30,chant=2,upkeep=7,power=1.0,accuracy=6,hit_cap=.90,color='bf94ef'),
    'legend': dict(name='Legend',rank=3,level=30,price=60000,tp=38,chant=2,upkeep=9,power=1.2,accuracy=9,hit_cap=.93,color='edb75b'),
    'mythic': dict(name='Mythic',rank=4,level=40,price=100000,tp=45,chant=2,upkeep=12,power=1.5,accuracy=12,hit_cap=.95,color='f08093'),
}

# Appearance IDs and combat stay stable; profile 11 revises the egg economy.
DROP_CHANCES = dict(normal=5.0, rare=2.0, epic=1.0, legend=.5, mythic=.1)
for tier, values in TIERS.items():
    values['sell_price'] = values['price'] * 40 // 100
    values['drop_chance'] = DROP_CHANCES[tier]
# Keep the merchant's shipped NPC 321; the sixteenth pet appends at NPC 322.
# egg, spell, pet NPC, appearance source, name, tier
SPECIES = [
    (609,28,306,74,'Wolf','rare'),
    (610,33,307,121,'Carnivo','epic'),
    (611,34,308,225,'Drake','mythic'),
    (612,51,309,13,'Penguin','normal'),
    (613,52,310,7,'Goat','normal'),
    (614,53,311,5,'Fox','normal'),
    (615,54,312,17,'Skeleton','rare'),
    (616,55,313,133,'Butterfly','rare'),
    (617,56,314,134,'Cursed Mask','epic'),
    (618,57,315,138,'Headless Hunter','epic'),
    (619,58,316,9,'Reaper','legend'),
    (620,59,317,140,'Twin Demon','legend'),
    (621,60,318,207,'Dark Magician','legend'),
    (622,61,319,209,'Banshi','mythic'),
    (623,62,320,174,'King Wurm','mythic'),
    (624,63,322,113,'Wraith','mythic'),
]
ROSTER = {
    'normal': ('Penguin','Fox','Goat'),
    'rare': ('Wolf','Butterfly','Skeleton'),
    'epic': ('Carnivo','Cursed Mask','Headless Hunter'),
    'legend': ('Twin Demon','Dark Magician','Reaper'),
    'mythic': ('Banshi','Drake','King Wurm','Wraith'),
}
EGGKEEPER = dict(id=321,name='Aeven Eggkeeper',template_id=27,map_id=5,x=35,y=46)
EGGS = {}
COMPANIONS = {}
SUMMON_SPELLS = {}
for egg,spell,npc,template,name,tier in SPECIES:
    t=TIERS[tier]
    chance=DROP_CHANCES[tier]
    icon=f'res://icons/{tier}_egg.svg'
    EGGS[egg]=dict(name=f'{name} Spirit Egg',species=name,spell_id=spell,level=t['level'],npc_id=template,chance=chance,template_id=11,icon=icon,tier=tier,tier_name=t['name'],tier_color=t['color'],price=t['price'],sell_price=t['sell_price'])
    COMPANIONS[spell]=dict(npc_id=npc,name=f'Spirit {name}',template_id=template,tier=tier,tier_name=t['name'],tier_color=t['color'],upkeep=t['upkeep'],upkeep_seconds=2,power=t['power'],damage_basis='owner_attack',accuracy=t['accuracy'],hit_cap=t['hit_cap'])
    SUMMON_SPELLS[spell]=(f'Summon Spirit {name}',t['level'],(7,),t['tp'],t['chant'],0,0,0,1,1,0,0)
COMPANIONS[35]=dict(npc_id=-1,name='Dismiss Companion',template_id=74,upkeep=0,power=0,accuracy=0,hit_cap=.95)

def egg_stock():
    return sorted(EGGS,key=lambda ident:(TIERS[EGGS[ident]['tier']]['rank'],ROSTER[EGGS[ident]['tier']].index(EGGS[ident]['species'])))
