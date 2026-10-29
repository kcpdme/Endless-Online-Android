# Classic Peasant foundation and measured encounter tuning

Server profile **14** works with the existing Android **0.50.1** client. Reconnect
to receive the new native stats and entry catalog; no APK update is required.

## Newborn and Peasant correction

An isolated comparison against the saved classic PUB/formula baseline reproduced
the reported problem: a level-zero character in the original chest outfit had
10 accuracy, 6 evade and 1 armour, rather than 0 accuracy, 1 evade and 1 armour.
The outfit's protection was correct; free class-formula bonuses were responsible
for the difference. Unarmed damage was 2–2 and maximum HP 35 instead of 0–1 and 10.

Unassigned class 0 and Peasant class 1 now share the classic foundation:

- Bare birth: current/maximum HP 10, current/maximum TP 10, damage 0–1,
  zero accuracy, evade, armour and all six attributes.
- No starting items, equipment, Gold or spells; original island house remains
  map 192 at 7,6.
- Earned attribute bonuses: STR/2 damage, AGI/2 accuracy and evade, CON/2 armour,
  using native integer truncation and original base damage handling.
- The saved original HP/TP formulas govern Peasant progression.
- Dagger #21 and Peasant outfits #144/#151 retain their complete original native
  records. The two-Goat-Horn recipe remains unchanged. Clothes provide armour 1
  and evade 1; the Dagger supplies damage 1–2 and accuracy 1.

The original hit/damage formulas apply when either combat participant is a
class-0/1 character, including incoming NPC hits and PK. NPC markers distinguish
creatures from characters with class zero. All professional-class and pet combat
keeps the modern formulas. The native evaluator's named `lte` operator avoids
its single-character `<` parsing rule. No new binary patch is needed.

Changing profession automatically recalculates the appropriate foundation.
Existing character level, EXP, invested attributes, equipment ownership, learned
skills and pets are preserved. Native login recalculation clamps current HP/TP
to the corrected maximum when necessary; no character-row migration is run.

## Monster adjustment

Fourteen selected progression encounters with recommended level 8 or higher gain
15% HP and approximately 10% minimum/maximum damage over profile 13, rounded to
whole native values. Attack cadence, accuracy, evasion and armour are unchanged.
For example, King Wurm changes from 5,200 HP and 43–62 base damage to 5,980 HP and
47–68 base damage. This increases fight duration and resource pressure without
invalidating evasion, shields or range through a universal speed increase.

Crow, Rat and Blob return to their original low-level combat fields. All island
NPC records retain their original combat stats. Service NPCs, pets, original
maps, boat/Aeven level gates, quest rewards, drops and all 305 original NPC EXP
fields are preserved. Global EXP/item/Gold rates remain ×1.

## Verification

`test_peasant_live.py` compiles the actual pinned C++ RPN evaluator and checks
8,000 incoming/outgoing/PK formula cases across every class and NPC markers,
including zero stats, armour and sitting. Native character creation/login then
compares 26 configurations against a disposable classic-reference world: both
genders, classes 0/1, levels 0/4/10, earned attributes, outfits and Dagger.

The class encounter harness uses fresh regular characters per scenario, so TP
exhaustion and persistent pet recovery from an earlier fight cannot contaminate
the next scenario. It measures native damage, healing, TP upkeep, survival and
actual potion use. Its arena copies use King Wurm stats; no player hits or monster
damage are forced. These are small randomized comparisons, not proof that every
class or player has the same win rate.

All six killed the 5,980-HP target in the stationary and positioning scenarios.
With normal retaliation and no potions, Priest, Rogue and Warrior survived;
Magician, Archer and Summoner died in this stationary controller's runs. In the
prepared scenario all six survived with at most five Big Health Potions each.
The prepared Summoner reserved TP for 60 seconds of net pet upkeep, rather than
spending all TP on attack spells and losing its pet. Its kill took 45.4 seconds
with five potions; Magician took 26.3 seconds with three. Rogue rear access cut
its separate stationary kill from 45.8 to 27.7 seconds; Archer close positioning
cut its separate stationary kill from 40.7 to 32.4 seconds. These measured
advantages have different survival and resource costs; they are not universal
damage multipliers.

Reports live beside this document as `peasant-v14-*-report.json`. The guarded
deployment checks tested content hashes and preserves the account database
byte-for-byte before restarting services. Existing clients receive actual
progression NPC metadata at entry, as well as Peasant item/class updates.
