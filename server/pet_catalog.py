"""Pet appearances share a tier's combat budget, price and TP economy."""

TIERS = {
    'normal': dict(name='Normal',rank=0,level=1,price=100,tp=10,chant=1,upkeep=1,power=.65,accuracy=0,hit_cap=.82,color='b8c5c9'),
    'rare': dict(name='Rare',rank=1,level=8,price=600,tp=18,chant=1,upkeep=2,power=1.05,accuracy=3,hit_cap=.86,color='78b9ee'),
    'epic': dict(name='Epic',rank=2,level=25,price=2000,tp=30,chant=2,upkeep=3,power=1.20,accuracy=6,hit_cap=.90,color='bf94ef'),
    'legend': dict(name='Legend',rank=3,level=30,price=6000,tp=38,chant=2,upkeep=4,power=1.25,accuracy=9,hit_cap=.93,color='edb75b'),
    'mythic': dict(name='Mythic',rank=4,level=40,price=12000,tp=45,chant=2,upkeep=5,power=1.30,accuracy=12,hit_cap=.95,color='f08093'),
}

# Preserve the three shipped item, spell and NPC identities. New records append.
# egg, spell, pet NPC, appearance source, name, tier, source drop chance
SPECIES = [
    (609,28,306,74,'Wolf','rare',3),
    (610,33,307,82,'Wurm','epic',1.5),
    (611,34,308,225,'Drake','mythic',8),
    (612,51,309,13,'Penguin','normal',2),
    (613,52,310,7,'Goat','normal',2),
    (614,53,311,5,'Fox','normal',2),
    (615,54,312,81,'Bat','rare',2),
    (616,55,313,133,'Butterfly','rare',2),
    (617,56,314,205,'Baby Turtle','epic',1.5),
    (618,57,315,17,'Skeleton','epic',1.5),
    (619,58,316,209,'Banshi','legend',1),
    (620,59,317,113,'Wraith','legend',1),
    (621,60,318,207,'Dark Magician','legend',1),
    (622,61,319,216,'Phoenix','mythic',2),
    (623,62,320,174,'King Wurm','mythic',1),
]
EGGKEEPER = dict(id=321,name='Aeven Eggkeeper',template_id=27,map_id=5,x=35,y=46)
EGGS = {}
COMPANIONS = {}
SUMMON_SPELLS = {}
for egg,spell,npc,template,name,tier,chance in SPECIES:
    t=TIERS[tier]
    icon=f'res://icons/{tier}_egg.svg'
    EGGS[egg]=dict(name=f'{name} Spirit Egg',spell_id=spell,level=t['level'],npc_id=template,chance=chance,template_id=11,icon=icon,tier=tier,tier_name=t['name'],tier_color=t['color'],price=t['price'])
    COMPANIONS[spell]=dict(npc_id=npc,name=f'Spirit {name}',template_id=template,tier=tier,tier_name=t['name'],tier_color=t['color'],upkeep=t['upkeep'],power=t['power'],accuracy=t['accuracy'],hit_cap=t['hit_cap'])
    SUMMON_SPELLS[spell]=(f'Summon Spirit {name}',t['level'],(7,),t['tp'],t['chant'],0,0,0,1,1,0,0)
COMPANIONS[35]=dict(npc_id=-1,name='Dismiss Companion',template_id=74,upkeep=0,power=0,accuracy=0,hit_cap=.95)

def egg_stock():
    return sorted(EGGS,key=lambda ident:(TIERS[EGGS[ident]['tier']]['rank'],ident))
