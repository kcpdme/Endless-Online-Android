# Class combat and mobile controls — profile 8, Android 0.46.0

## Summoner controls

Summoners have a paw button in the former bottom Inventory position. It reads
**Summon** when there is a living bond and no active pet, and **Dismiss** while
the native server reports an active pet. With no bond, it opens Inventory and
explains hatching. It casts the existing class summon/dismiss skills with their
normal TP cost, chant, cooldown, class and level checks. Dismissal keeps the bond;
recall consumes TP rather than another egg. Hatching still uses the chosen egg.

Inventory occupies the former Conversations position on the top row for all
classes. Conversations now sits immediately left of the bottom message composer,
including its unread indicator. It moves with the keyboard layout. The pet
button is hidden for other classes and during modal screens. Dismiss Spirit is
a free baseline Summoner control, available when joining/changing to the class.

## TP recovery

| Class | Max TP recovered every 2 seconds | While sitting |
| --- | ---: | ---: |
| Magician | 0.8% | 1.6% |
| Summoner | 0.4% | 0.8% |
| Priest / High Priest | 0.3% | 0.6% |

These pulses **replace** the ordinary 90-second TP pulse for those classes.
There is no double recovery from both systems. Each pulse is floored, with a
minimum of one TP, and capped at the character’s maximum. PK maps, arenas and
global PK halve the rate before rounding. Dead/absent characters do not receive
these fast pulses. Changing class immediately changes recovery eligibility.
Other classes retain ordinary recovery. Priest HP renewal keeps its existing
2% standing / 4% sitting rate and its PK reduction.

For summontest’s equipped **1,108 TP**, this means **4 TP every two seconds**
standing and **8 TP sitting**. A Mythic pet still costs 45 TP to call and 5 TP
at each upkeep check, configured every two seconds and processed on its AI tick.
The native test observed the exact call/upkeep deductions and new recovery over
12 seconds. Full depletion was not measured. The older 13–17 minute estimate
from profile 7 is superseded. At an exact two-second upkeep cadence, pet-only
standing use would last about 35 minutes; actual AI spacing can extend that.
Sitting can sustain an idle pet, but pets cannot hunt unattended. Attack spells
remain the main extra TP expense in active combat.

The ordering gives Magicians the strongest recovery for their TP-dependent
casting, keeps Summoner pet upkeep meaningful, and supports Priest healing
without removing its TP costs. All damage/heal costs remain unchanged.

## Bow and arrow progression

The existing red starter bow is named **Bow**, item 297; its art/name is retained.
Rates below multiply the original basic attack rate. Native base attack delay is
0.5 seconds, so Crossbow uses 0.333 seconds and Scav Bow uses 0.25. The mobile
client keeps a small timing allowance: 0.52 / 0.347 / 0.26 seconds respectively.

| Bow | Level | Base range, tiles | Fire rate | Basic shot impact |
| --- | ---: | ---: | ---: | ---: |
| Bow (red starter) | 0 | 3 | ×1 | 100% |
| Hunting Bow | 8 | 3 | ×1 | 100% |
| Reinforced Hunting Bow, crafted | 8 | 4 | ×1.25 | 95% |
| Longbow | 15 | 4 | ×1.25 | 95% |
| Crossbow | 25 | 5 | ×1.5 | 85% |
| Scav Bow | 35 | 7 | ×2 | 70% |
| Dawn Longbow, crafted | 45 | 8 | ×2 | 70% |

Normal Arrows add **0 tiles**. Frost and Fire Arrows each add **2 tiles**.
Scav plus elemental arrows reaches 9 tiles; Dawn reaches 10. Basic shots retain
the existing facing/straight-line rules and stop at walls. Targeted Archer
skills use the current combined range and recheck it on release. Area shots
retain their published self-centred radius and target cap. Bow/arrow class and
level requirements still apply; a shield cannot replace arrows for shooting.

Faster basic shots use the listed fraction of the total pre-armour attack roll.
This keeps twice the firing rate from doubling the entire Archer damage budget;
Archer spells retain their original damage and chant cadence. In the matched
level-35/45 model, Archer basic DPS becomes **159.60 / 199.33**, versus prior
**114.86 / 143.72**. The best other class single-target burst at those milestones
is **142.93 / 182.40**. Archer therefore gains a distinct sustained ranged role,
while other classes retain area attacks, healing, pets, backstabs or durability.
These are model expectations with an available target, rather than measured
farming/PvP equivalence.

Native timestamp validation follows weapon cadence. A separate server wall-clock
check prevents forged timestamps or rapid packets from exceeding it; changing
weapons does not reset an outstanding basic attack cooldown. Both PvE and PK use
the equipped range. Animation/cooldown display and item/shop descriptions expose
the same public values.

## Warrior shields

Thirteen real shield definitions now have deliberate defence budgets. For
example, Oak Shield provides **4 armour**, Kite Shield **5**, Dark Protector **6**,
Chalybs **12**, Quaria **14**, and Royal Protector **16**. Warriors receive double
the shield’s own armour: Royal Protector contributes **32 armour** to a Warrior,
and 16 to another eligible class. Shield HP, CON and other equipment bonuses are
added normally. The multiplier does not double total character armour. Bags,
wings and arrows do not count as real shields. Item requirements and ordinary
shared ownership remain intact.

## Verification and release

- 26 unit tests passed, including strict preservation of unrelated item fields.
- 49 native combat checks passed for range boundaries, elemental arrows, walls,
  firing order, forged packet limits, standing/sitting/PK recovery, class changes,
  Warrior-only shield doubling, and actual extended-range PK damage.
- 515 broader native balance checks passed, including 36 normal class/level stat
  builds, class locks, spells, healing, area limits, rebuilding and ownership.
  Exact spell-cost fixtures disable periodic recovery to isolate the debit;
  recovery itself is covered by the new live combat tests.
- 135 native pet checks and 120 real Godot pet/HUD checks passed, including the
  dedicated button’s summon/dismiss/recall flow and retained bond.
- Summon and Dismiss HUD previews were inspected with the real renderer at
  1280×720 and 1544×720. Public HTTPS/WebSocket checks passed with a fresh regular
  developer fixture, including actual class TP recovery and Wraith lifecycle.
- The complete native patch stack reconstructs from the pinned source. The
  runtime installer is repeatable and requires the new native capability.

Profile 8 is live. Stopped-world backup:
`/opt/aster-vale/backups/combat-progression-v8-20261028T081130Z`.
The install preserved account database bytes, maps, admin teleport, all egg/bond
IDs/values/levels and unrelated configuration. No character migration was run.
Skylar and summontest were not used as fixtures.

Android **0.46.0 / code 83** is installed on the Galaxy S23 Ultra, preserving app
data and install identity. Signature, 16 KB alignment, embedded catalog/map and
installed APK byte checks passed. The app process started; a system overlay
covered the display during inspection, so handset gameplay is not claimed.

APK SHA-256: `f0bf981c56c4aa550c9327e4526d84ae61902728e22d5b0ee5cf475a8a3f4250`.
Native SHA-256: `ab1b444355d36686139f2f9c8833f8b0ce66ee0a38306ce3df17fcad77e075ce`.
Sanitized `combat-progression-*` JSON reports record validation scope. The complete
HTML equipment guide includes bow range, arrow bonus, fire rate, basic shot
impact and Warrior shield armour columns.
