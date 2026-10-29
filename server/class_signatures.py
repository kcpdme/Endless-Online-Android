"""Profile-three professions: explicit additions, hatch rewards and coverage inputs."""
SIGNATURES = {
    2: dict(name='Renewal',description='Regenerate 2% maximum HP every second; 4% while sitting. Half strength in PK areas. Recover 0.3% max TP every 2 seconds; double while sitting, half in PK.',regen_rate=.02,sitting_regen_rate=.04,regen_seconds=1),
    3: dict(name='Arcane mastery',description='Single-target spell hits gain x1.5; area magic uses normal mastery. Recover 0.8% max TP every 2 seconds; double while sitting, half in PK.',spell_multiplier=2.4,area_multiplier=1.0,single_target_multiplier=1.5),
    4: dict(name='Backstab',description='Move twice as fast. A successful adjacent attack directly behind a target deals randomly 1.5x or 2x damage with a Rogue blade. Does not stack with critical hits.',backstab_multipliers=[1.5,2.0],walking_multiplier=2),
    5: dict(name='Marksmanship',description='Red Bow fires at x1, Crossbow x1.2, Scav/Dawn x1.5 or x2 with a target within 2 tiles ahead. Fire/Frost arrows add 2 tiles. Rapid bows trade per-shot impact for cadence; AGI drives damage and accuracy.'),
    6: dict(name='Might',description='Each STR gives 0.65 base attack power, versus 0.20 for Rogue and 0.15 for Archer. Real shields grant double their armour value to Warriors.',strength_damage=.65),
    7: dict(name='Spirit bond',description='Choose from 16 pets at the Aeven Eggkeeper or earn bound eggs from monsters. Five tiers multiply your equipped attack by 0.45/0.7/1.0/1.2/1.5. Pets retaliate when an aggressive monster hurts you; higher tiers spend more TP. Hatched pets stay in a permanent collection. Bind one at a time; dismissal, TP exhaustion and death start a shared five-minute recovery. Travel and logout keep the collection and do not start recovery. Recover 0.4% max TP every 2 seconds; double sitting, half in PK. PK areas use stronger spirit casting instead of pets.'),
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
from pet_catalog import EGGS
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

from combat_progression import TP_RECOVERY
for clas,rate in TP_RECOVERY.items():
 if clas in SIGNATURES:SIGNATURES[clas].update(tp_regen_rate=rate,tp_regen_seconds=2,tp_regen_sitting_multiplier=2,tp_regen_pk_multiplier=.5)
