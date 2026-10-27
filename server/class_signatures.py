"""Profile-three professions: explicit additions, hatch rewards and coverage inputs."""
SIGNATURES = {
    2: dict(name='Renewal',description='Regenerate 2% maximum HP every 2 seconds; 4% while sitting. Half strength in PK areas.',regen_rate=.02,sitting_regen_rate=.04,regen_seconds=2),
    3: dict(name='Arcane mastery',description='Highest spell multiplier, with early and late capped area magic.',spell_multiplier=2.4),
    4: dict(name='Backstab',description='A successful adjacent attack directly behind a target deals randomly 1.5x or 2x damage with a Rogue blade. Does not stack with critical hits.',backstab_multipliers=[1.5,2.0]),
    5: dict(name='Marksmanship',description='Sustained ranged attacks and shots with a bow and arrows; AGI drives damage and accuracy.'),
    6: dict(name='Might',description='Each STR gives 0.65 base attack power, versus 0.20 for Rogue and 0.15 for Archer.',strength_damage=.65),
    7: dict(name='Spirit bond',description='Hatch monster eggs to permanently learn a spirit summon. One active pet; initial and upkeep TP limit its assistance. In PK areas, stronger spirit casting compensates for disabled pet AI.'),
}
ITEMS=[
 (544,'Stormcaller Staff',389,3,'intelligence',4),
 (545,'Veil Mail',142,4,'agility',3),(546,'Veil Mail',148,4,'agility',3),
 (547,'Trailrunner Coat',414,5,'agility',3),(548,'Trailrunner Coat',413,5,'agility',3),
]
# Clear starter identity without making a level-zero character's common kit inert.
for clas,name,male,female,role in [
 (2,'Novice Vestments',131,132,'wisdom'),(3,'Apprentice Robes',128,127,'intelligence'),
 (4,'Cutpurse Clothes',142,148,'agility'),(5,'Tracker Clothes',414,413,'agility'),
 (6,'Recruit Mail',135,138,'strength'),(7,'Initiate Spirit Robes',128,127,'charisma')]:
 for template in (male,female):ITEMS.append((549+len(ITEMS)-5,name,template,clas,role,0))
SUPPORT={}
for clas,prefix,role,hat,boots,gloves in [
 (2,'Sanctum','wisdom',187,125,49),(3,'Arcane','intelligence',173,124,49),
 (4,'Shadow','agility',188,122,267),(5,'Falcon','agility',182,123,58),
 (6,'Ironwall','strength',180,447,266),(7,'Spirit','charisma',181,126,49)]:
 for tier,label in [(2,'Adept'),(4,'Master')]:
  for slot,template in [('Hood',hat),('Boots',boots),('Gloves',gloves),('Ring',41)]:
   ident=561+len(SUPPORT);SUPPORT[ident]=dict(clas=clas,tier=tier,slot=slot)
   ITEMS.append((ident,f'{prefix} {label} {slot}',template,clas,role,tier))
EGGS={
 609:dict(name='Wolf Spirit Egg',spell_id=28,level=8,npc_id=74,chance=3,template_id=11,icon='res://icons/wolf_egg.svg'),
 610:dict(name='Wurm Spirit Egg',spell_id=33,level=25,npc_id=82,chance=1.5,template_id=11,icon='res://icons/wurm_egg.svg'),
 611:dict(name='Drake Spirit Egg',spell_id=34,level=40,npc_id=225,chance=8,template_id=11,icon='res://icons/drake_egg.svg'),
}
# Each physical class now has an ability at all six main milestones.
SPELLS={
 40:('Shieldbreaker',1,(6,),5,1,8,12,0,0,2,0,0),
 41:('Quick Cut',1,(4,),5,1,8,12,0,0,2,0,0),
 42:('Quick Shot',1,(5,),5,1,10,14,0,0,2,0,0),
 43:('Ambush',15,(4,),14,1,28,38,0,0,2,0,0),
 44:('Power Shot',15,(5,),14,1,30,40,0,0,2,0,0),
 45:('Sundering Blow',25,(6,),16,1,36,48,0,0,2,0,0),
 46:('Earthshaker',45,(6,),30,2,34,46,0,0,2,1,3),
 47:('Assassinate',45,(4,),28,1,64,82,0,0,2,0,0),
 48:('Deadeye Shot',45,(5,),28,1,68,86,0,0,2,0,0),
 49:('Arcane Burst',8,(3,),16,2,14,22,0,0,2,1,3),
 50:('Radiant Light',35,(2,),22,1,48,62,0,0,2,0,0),
}
