"""Versioned, shared design inputs for the native level 1–50 balance profile."""

VERSION = 3
LEVELS = (1, 8, 15, 25, 35, 45)
ATTRIBUTES = ('strength', 'intelligence', 'wisdom', 'agility', 'constitution', 'charisma')
CLASSES = {
    1: dict(name='Peasant', family=4, damage='str 0.35 * agi 0.15 * +', accuracy='10 level 0.4 * + agi 0.7 * +', evade='5 agi 0.4 * +', defence='con 0.35 *', hp='35 level 3 * + con 4 * +', tp='20 level 2 * + int 2 * + wis 2 * +', spell_scale=1.0, heal_wis=.2, heal_int=.1, heal_cha=0, hint='Choose a class at the Wise Man. Use potions for recovery; only Priests cast heals.'),
    2: dict(name='Priest', family=5, damage='wis 0.4 * int 0.2 * +', accuracy='12 level 0.5 * + wis 0.8 * +', evade='5 agi 0.35 * + wis 0.1 * +', defence='con 0.4 *', hp='35 level 2.8 * + con 4 * +', tp='45 level 3 * + int 2 * + wis 4 * +', spell_scale=1.9, heal_wis=1.2, heal_int=.3, heal_cha=0, hint='WIS first, then CON and INT. Fast passive HP regeneration, holy attacks and strongest party healing.'),
    3: dict(name='Magician', family=2, damage='int 0.35 * wis 0.1 * +', accuracy='12 level 0.5 * + int 0.8 * +', evade='5 agi 0.35 * +', defence='con 0.3 *', hp='30 level 2.5 * + con 3.5 * +', tp='40 level 3 * + int 3 * + wis 2 * +', spell_scale=2.4, heal_wis=.35, heal_int=.15, heal_cha=0, hint='INT first, then CON and WIS. Highest spell power; early and late area magic spend TP.'),
    4: dict(name='Rogue', family=1, damage='agi 0.45 * str 0.2 * +', accuracy='12 level 0.5 * + agi 0.9 * +', evade='8 agi 0.75 * +', defence='con 0.35 *', hp='35 level 3 * + con 4 * +', tp='25 level 1.5 * + int 1.5 * + wis 1.5 * +', spell_scale=1.6, heal_wis=.2, heal_int=.1, heal_cha=0, hint='AGI first, then CON and STR. Evasion and blade backstabs: strike directly from behind for 1.5x or 2x.'),
    5: dict(name='Archer', family=3, damage='agi 0.5 * str 0.15 * +', accuracy='14 level 0.5 * + agi 0.9 * +', evade='6 agi 0.5 * +', defence='con 0.35 *', hp='35 level 3 * + con 4 * +', tp='25 level 1.5 * + wis 2 * +', spell_scale=1.6, heal_wis=.2, heal_int=.1, heal_cha=0, hint='AGI first, then CON and some STR. Equip a bow and arrows; use range and Aimed Shot.'),
    6: dict(name='Warrior', family=0, damage='str 0.65 * agi 0.1 * +', accuracy='10 level 0.5 * + agi 0.75 * + str 0.15 * +', evade='5 agi 0.35 * +', defence='con 0.6 *', hp='45 level 3.5 * + con 5 * +', tp='20 level 1.5 * + int 1.5 * + wis 1.5 * +', spell_scale=1.4, heal_wis=.2, heal_int=.1, heal_cha=0, hint='STR and CON, with some AGI. Highest STR attack scaling and durability; melee and Whirlwind.'),
    7: dict(name='Summoner', family=6, damage='cha 0.35 * int 0.2 * +', accuracy='12 level 0.5 * + cha 0.7 * + int 0.2 * +', evade='6 agi 0.35 * + cha 0.15 * +', defence='con 0.4 *', hp='35 level 3 * + con 4 * +', tp='40 level 3 * + cha 3 * + int 2 * + wis 1.5 * +', spell_scale=1.2, pk_spell_scale=1.8, heal_wis=0, heal_int=0, heal_cha=0, hint='CHA first, then CON and INT. Hatch monster eggs to learn permanent summons. One spirit assists active fights; upkeep spends TP.'),
}
CLASSES[8] = dict(CLASSES[2], name='High Priest')

# ID: name, learning level, classes (empty = shared; -1 = admin), TP, chant ticks, base low,
# base high, healing, target type, restriction, area radius, target cap.
SPELLS = {
    1: ('Heal Self', 1, (2,), 6, 1, 0, 0, 14, 1, 1, 0, 0),
    2: ('Small Heal', 1, (2,), 8, 1, 0, 0, 24, 0, 1, 0, 0),
    3: ('Group Heal', 15, (2,), 28, 2, 0, 0, 32, 3, 1, 0, 0),
    4: ('Small Fire', 1, (3,), 5, 1, 8, 12, 0, 0, 2, 0, 0),
    5: ('Small Thunder', 8, (3,), 8, 1, 14, 20, 0, 0, 2, 0, 0),
    6: ('Admin Heal', 1, (-1,), 2, 1, 0, 0, 5000, 0, 1, 0, 0),
    7: ('Medium Heal', 15, (2,), 16, 1, 0, 0, 55, 0, 1, 0, 0),
    8: ('Large Heal', 30, (2,), 28, 2, 0, 0, 100, 0, 1, 0, 0),
    9: ('Ultima Blast', 45, (3,), 38, 1, 64, 84, 0, 0, 2, 0, 0),
    10: ('Fire Ball', 15, (3,), 14, 1, 24, 34, 0, 0, 2, 0, 0),
    11: ('Mending Light', 8, (2,), 10, 1, 0, 0, 36, 1, 1, 0, 0),
    12: ('Twin Strike', 8, (4,), 12, 1, 20, 28, 0, 0, 2, 0, 0),
    13: ('Aimed Shot', 8, (5,), 12, 1, 22, 30, 0, 0, 2, 0, 0),
    14: ('Ice Blast', 25, (3,), 30, 2, 22, 32, 0, 0, 2, 2, 5),
    15: ('Energy Ball', 25, (3,), 20, 1, 34, 46, 0, 0, 2, 0, 0),
    16: ('Whirlwind', 15, (6,), 22, 1, 10, 16, 0, 0, 2, 1, 3),
    17: ('Bard', 2, (), 0, 1, 0, 0, 0, 0, 1, 0, 0),
    18: ('Healing Aura', 25, (2,), 38, 2, 0, 0, 65, 3, 1, 0, 0),
    19: ('Boulders', 35, (3,), 28, 1, 46, 60, 0, 0, 2, 0, 0),
    20: ('Heaven', 45, (2,), 48, 2, 0, 0, 160, 0, 1, 0, 0),
    21: ('Frost Nova', 40, (3,), 44, 2, 35, 48, 0, 0, 2, 2, 5),
    22: ('Holy Light', 1, (2,), 5, 1, 8, 12, 0, 0, 2, 0, 0),
    23: ('Spirit Bolt', 1, (7,), 5, 1, 8, 12, 0, 0, 2, 0, 0),
    24: ('Spirit Lance', 15, (7,), 14, 1, 26, 36, 0, 0, 2, 0, 0),
    25: ('Fire Blast', 30, (3,), 25, 2, 24, 36, 0, 0, 2, 2, 5),
    26: ('Spirit Grasp', 25, (7,), 22, 1, 38, 50, 0, 0, 2, 0, 0),
    27: ('Spirit Storm', 35, (7,), 32, 2, 28, 40, 0, 0, 2, 2, 4),
    28: ('Summon Spirit Wolf', 8, (7,), 18, 1, 0, 0, 0, 1, 1, 0, 0),
    29: ('Dark Bite', 45, (7,), 38, 1, 56, 74, 0, 0, 2, 0, 0),
    30: ('Hidden Strike', 25, (4,), 18, 1, 36, 48, 0, 0, 2, 0, 0),
    31: ('Green Flame', 50, (-1,), 40, 2, 50, 60, 0, 0, 2, 0, 0),
    32: ('Power Strike', 8, (6,), 10, 1, 20, 28, 0, 0, 2, 0, 0),
    33: ('Summon Spirit Wurm', 25, (7,), 30, 2, 0, 0, 0, 1, 1, 0, 0),
    34: ('Summon Spirit Drake', 40, (7,), 45, 2, 0, 0, 0, 1, 1, 0, 0),
    35: ('Dismiss Companion', 1, (7,), 0, 1, 0, 0, 0, 1, 1, 0, 0),
    36: ('Piercing Shot', 25, (5,), 18, 1, 36, 48, 0, 0, 2, 0, 0),
    37: ('Arrow Volley', 35, (5,), 30, 2, 20, 28, 0, 0, 2, 2, 3),
    38: ('Brutal Strike', 35, (6,), 20, 1, 42, 56, 0, 0, 2, 0, 0),
    39: ('Blade Dance', 35, (4,), 26, 1, 18, 26, 0, 0, 2, 1, 3),
}
for _class_id,_profile in CLASSES.items():
    _profile['damage']=_profile['damage']+(' 3 +' if _class_id in (4,5,6) else ' 2 +')
    _primary,_secondary={1:('strength','agility'),2:('wisdom','intelligence'),3:('intelligence','wisdom'),4:('agility','strength'),5:('agility','strength'),6:('strength','agility'),7:('charisma','intelligence'),8:('wisdom','intelligence')}[_class_id]
    _profile['base_attributes']={k:3 if k==_primary else 2 if k=='constitution' else 1 if k==_secondary else 0 for k in ATTRIBUTES}

WEAPON_TIERS = {
    0: (20,21,29,33,297),
    1: (18,19,22,23,24,25,26,27,28,30,31,32,34,35,36,205,206,207,283),
    2: (37,38,238,245,269,270,271,272,282,284,285,286,288,290,317,325,329,351,352,360,361,362,363,365,366,393,420,421,433,434,435),
    3: (287,316,327,328,389,444,454),
    4: (281,390,391,436,455,457),
    5: (456,),
}
BODY_TIERS = {
    0: (47,48,127,128,129,130,131,132,134,136,144,150,151,153,159,160,161,162,171,199,200,201,202,203,324,332,333,334,346,347,348,381,407),
    1: (135,137,139,140,142,143,145,146,148,149,154,166,168,169,170,172),
    2: (59,60,133,138,141,147,152,155,156,157,158,163,164,165,167,222,223,274,275,279,280,311,312,342,343,344,345,368,369,370,371,372,373,406,415,461),
    3: (413,414,428,429,460,465),
    4: (387,388,458,459,462,463,464),
    5: (430,431),
}

# Appended definitions reuse existing art. ID, name, template, class, role.
NEW_ITEMS = [
    (493,'Tempest Staff',389,3,'intelligence'),(494,'Spirit Sceptre',455,7,'charisma'),
    (495,'Sanctum Staff',390,2,'wisdom'),(496,'Dawn Longbow',457,5,'agility'),
    (497,'Shadow Fang',327,4,'agility'),(498,'Titan Blade',281,6,'strength'),
    (499,'Oracle Robes',406,2,'wisdom'),(500,'Oracle Robes',128,2,'wisdom'),
    (501,'Tempest Robes',128,3,'intelligence'),(502,'Tempest Robes',127,3,'intelligence'),
    (503,'Spirit Vestments',132,7,'charisma'),(504,'Spirit Vestments',131,7,'charisma'),
    (505,'Stalker Mail',142,4,'agility'),(506,'Stalker Mail',148,4,'agility'),
    (507,'Ranger Coat',414,5,'agility'),(508,'Ranger Coat',413,5,'agility'),
    (509,'Guardian Plate',387,6,'strength'),(510,'Guardian Plate',388,6,'strength'),
    (511,'Hunting Bow',297,5,'agility'),(512,'Longbow',297,5,'agility'),
    (513,'Spirit Wand',455,7,'charisma'),(514,'Spirit Staff',455,7,'charisma'),
    (515,'Spirit Robes',132,7,'charisma'),(516,'Spirit Robes',131,7,'charisma'),
    (517,'Elder Spirit Robes',132,7,'charisma'),(518,'Elder Spirit Robes',131,7,'charisma'),
    (519,'Sanctum Vestments',406,2,'wisdom'),(520,'Sanctum Vestments',127,2,'wisdom'),
    (521,'Arcane Robes',128,3,'intelligence'),(522,'Arcane Robes',127,3,'intelligence'),
    (523,'Rune Robes',128,3,'intelligence'),(524,'Rune Robes',127,3,'intelligence'),
    (525,'Cleric Vestments',406,2,'wisdom'),(526,'Cleric Vestments',127,2,'wisdom'),
    (527,'Shadow Mail',142,4,'agility'),(528,'Shadow Mail',148,4,'agility'),
    (529,'Windrunner Coat',414,5,'agility'),(530,'Windrunner Coat',413,5,'agility'),
    (531,'Acolyte Robes',139,2,'wisdom'),(532,'Acolyte Robes',149,2,'wisdom'),
    (533,'Hidden Blade',38,4,'agility'),(534,'Blessed Staff',390,2,'wisdom'),
    (535,'Spirit Apprentice Robes',128,7,'charisma'),(536,'Spirit Apprentice Robes',127,7,'charisma'),
    (537,'Spirit Adept Robes',156,7,'charisma'),(538,'Spirit Adept Robes',127,7,'charisma'),
    (539,'Scout Mail',142,4,'agility'),(540,'Scout Mail',148,4,'agility'),
    (541,'Hunter Leather',414,5,'agility'),(542,'Hunter Leather',413,5,'agility'),
    (543,'Reinforced Hunting Bow',511,5,'agility'),
]
NEW_ITEM_TIERS = {511:1,512:2,513:3,514:4,515:3,516:3,517:4,518:4,519:4,520:4,521:4,522:4,523:3,524:3,525:3,526:3,527:4,528:4,529:4,530:4,531:1,532:1,533:3,534:3,535:1,536:1,537:2,538:2,539:2,540:2,541:1,542:1,543:1}

# Defined progression encounters. Other original NPCs keep their identity/stats.
# NPC: recommended level, HP, min/max attack, accuracy, evade, armour, base EXP.
ENCOUNTERS = {
    1:(1,12,1,3,9,3,0,8),2:(1,18,2,4,10,4,0,10),3:(1,22,2,5,11,4,1,12),
    4:(5,55,4,8,16,6,2,24),8:(8,95,7,12,20,8,3,40),
    82:(8,105,8,13,22,10,3,45),83:(8,90,7,12,20,9,2,40),
    117:(15,230,13,21,30,14,6,85),232:(20,340,17,26,38,18,8,115),
    182:(25,520,23,34,46,22,12,180),216:(30,720,30,44,54,26,15,250),
    9:(25,650,27,39,50,24,12,220),118:(30,3200,36,52,62,28,18,950),
    149:(30,2400,34,50,60,28,17,700),174:(35,5200,43,62,72,32,22,1400),
    142:(40,8200,52,74,85,38,27,2200),225:(45,11000,62,88,96,44,32,3000),
    129:(50,18000,74,104,112,50,40,4500),
}

# Summoned creatures use already-exported original art, neutral ENF types and
# native ownership. They never have loot/EXP or autonomous target selection.
COMPANIONS = {
    28: dict(npc_id=306,name='Spirit Wolf',template_id=74,upkeep=2,power=1.0),
    33: dict(npc_id=307,name='Spirit Wurm',template_id=82,upkeep=3,power=1.15),
    34: dict(npc_id=308,name='Spirit Drake',template_id=225,upkeep=4,power=1.3),
    35: dict(npc_id=-1,name='Dismiss Companion',template_id=74,upkeep=0,power=0),
}

from class_signatures import ITEMS as SIGNATURE_ITEMS, SPELLS as SIGNATURE_SPELLS
NEW_ITEMS.extend((ident,name,template,clas,role) for ident,name,template,clas,role,tier in SIGNATURE_ITEMS)
NEW_ITEM_TIERS.update({ident:tier for ident,name,template,clas,role,tier in SIGNATURE_ITEMS})
SPELLS.update(SIGNATURE_SPELLS)
