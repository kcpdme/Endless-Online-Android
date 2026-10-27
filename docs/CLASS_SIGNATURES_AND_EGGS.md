# Class signatures, egg hatching and complete progression

Profile 3 expands the class restrictions and native companions in profile 2.
The main journey remains levels 1–50, with milestones at 1, 8, 15, 25, 35 and 45.
Accounts, levels, EXP, existing item ownership and learned skills are retained.
Power is assessed through damage, defence, recovery, resource cost, range,
positioning and party utility together.

## Six useful professions

- **Warrior — Might.** STR contributes 0.65 attack power per point, compared
  with Rogue's 0.20 STR contribution and Archer's 0.15. Warrior keeps the largest
  HP/armour foundation. Its six abilities cover every main milestone, from
  Shieldbreaker and Power Strike through Whirlwind, Sundering Blow, Brutal
  Strike and Earthshaker. Targeted melee strikes require an adjacent opponent.
- **Rogue — Backstab.** A Rogue using a blade must stand directly behind the
  opponent, based on the opponent's actual facing. A successful basic or
  single-target blade skill deals randomly 1.5× or 2× damage. This does not
  stack with a critical hit or apply to area skills. Front and side attacks
  receive no rear multiplier. Other classes no longer receive the old free
  side/rear critical bonus. Evasion, Quick Cut, Twin Strike, Ambush, Hidden
  Strike, Blade Dance and Assassinate complete its progression. Hidden Blade
  remains a skill/TP choice; Mitova now has an obtainable crafting upgrade.
- **Archer — Marksmanship.** Native ranged attacks and offensive shots require
  a bow and arrows. AGI drives attack and accuracy. Quick Shot, Aimed Shot,
  Power Shot, Piercing Shot, Arrow Volley and Deadeye Shot span all milestones.
  Shots use the native five-tile range; reliable distance damage is its core
  advantage. Volley is a limited area escape/clearing option.
- **Magician — Arcane mastery.** Spell attack scaling rises from 1.9 to 2.4,
  rewarding INT and paying for casting time and targeting effort. Arcane Burst
  provides level-8 area magic; Ice Blast, Fire Blast and Frost Nova provide
  larger capped areas later. Damage charges TP once per area, limits targets
  and preserves normal native kill/reward handling. Mage has the strongest
  broad clearing budget and a smaller HP/armour foundation.
- **Priest / High Priest — Renewal.** Automatically recover 2% maximum HP
  every two seconds while standing and 4% while sitting. This costs no TP,
  stops when leaving the profession and cannot revive a dead character or
  exceed maximum HP. In PK areas the regeneration rate is halved. Priest keeps
  exclusive healing magic, party support and viable solo holy attacks;
  Radiant Light adds a level-35 offensive upgrade.
- **Summoner — Spirit bond.** Hatch a monster egg once to permanently learn
  its summon. One active spirit assists the monster the owner is actively
  fighting; its attacks never refresh that command. Initial and upkeep TP are
  the ongoing limits: the former fixed 90-second expiry is removed. Pets still
  dismiss on travel, death, logout, class changes, mana exhaustion or excessive
  distance. The learned summon remains owned. Pets are PvE assistants, cannot
  tank or farm unattended, and cannot stack in PK areas. Summoner's spell
  multiplier rises from 1.2 to 1.8 in PK areas to compensate for unavailable
  pet AI; its client preview reflects the applicable multiplier.

Every class has its own permissions and signature. Starter tools and ordinary
accessories remain common. Previously learned off-class skills remain owned
and locked. Equipment is checked again on use and stat calculation, and
incompatible worn equipment returns to its owner's bag on class changes.

## What was found in the supplied resources

The supplied `trunk 305 EODelta` source contains `HatchPet`, pet ownership,
following/commands and an item-use hook configured by `ID.hatchnpc`. Its sample
`data/extras/items.ini` uses ordinary potion IDs 15, 9 and 10 for hatching.
Neither that sample PUB nor the current item list defines named spirit eggs.
The old fork is reference evidence; its executable, database, configuration
and entire pet subsystem are not substituted into the current server.

This implementation extends the current native companion system. Three new
item definitions reuse a compatible original native item graphic and include
three original SVG egg icons for Android inventory and ground rendering.
The existing learned-spell record provides permanent ownership, so hatching
does not require a separate pet database or a class-switch loophole.

## Eggs and acquisition

- **Wolf Spirit Egg, item 609:** hatch at Summoner level 8 to learn Summon
  Spirit Wolf. Wolfman NPC 74 gains a base 3% drop-table entry. Craft at the
  Aeven Staff Smith from five Wolfman Furs, five Snake Teeth and 100 Gold.
  Calling the spirit costs 18 TP; upkeep is 2 TP every two seconds.
- **Wurm Spirit Egg, item 610:** hatch at level 25 to learn Summon Spirit Wurm.
  Wurm NPC 82 gains a base 1.5% entry. Craft from six Wurm Heads, three Worm
  Segments and 200 Gold. Calling costs 30 TP; upkeep is 3 TP every two seconds.
- **Drake Spirit Egg, item 611:** hatch at level 40 to learn Summon Spirit Drake.
  Dragon NPC 225 gains a base 8% entry. Craft from two Dragon Claws, two Dragon
  Wings and 200 Gold. Calling costs 45 TP; upkeep is 4 TP every two seconds.

These are base table entries. The native weighted drop mode and configured
world rate determine effective odds. Original drop entries remain intact.
The material recipes provide a reliable alternative to rare egg drops.

A valid hatch consumes exactly one egg and grants exactly one learned skill.
Hatching itself does not spawn a free extra pet or pay its summoning/upkeep
cost. Duplicate, wrong-class, under-level or unavailable hatching preserves the
egg. Spare eggs remain tradeable. Existing learned summons are honoured;
new characters obtain the three summon skills through eggs rather than the
ordinary skillmaster purchase list. Dismiss Companion remains available at
skillmasters, as do the class's offensive spirit abilities.

## Equipment and ability coverage

The catalog now has **611 items, 452 equipment definitions and 50 skills**.
There are 65 additional equipment definitions and three eggs beyond profile 2:

- A level-35 Stormcaller Staff fills the Mage weapon gap.
- Level-25 Veil Mail and Trailrunner Coats give Rogue and Archer specialist
  alternatives to common Oron, with equal male/female budgets.
- Twelve starter outfits give all six professions a visible first identity.
- Forty-eight head, boot, glove and ring definitions provide class-focused
  level-15 and level-35 upgrades. Common belts, necklaces and bracers remain
  supporting choices. Both ring slots are included in comparison builds.
- Mitova now crafts from Hidden Blade, ten Dark Rags and 200 Gold at NPC 87.
  Craft-only definitions keep a bounded edge over ordinary purchased items.
- Eleven added abilities fill early/mid/late physical-class gaps, add early
  Mage area damage and give Priest a later solo attack.

The audit checks all six classes at all six milestones. Each build must have
an obtainable weapon, body, head item, boots, gloves, ring and offensive skill;
usable clothes must exist for both genders. Every comparison loadout needs a
real shop, crafting or monster-drop route. Missing acquisition routes fail the
audit rather than being counted as theoretical options.

The searchable [guide](../outputs/balance-revamp/balance-guide.html) contains
all definitions, the coverage matrix and role comparisons. The model uses
matching levels and a 60/25/15 primary/CON/secondary split, native formulas,
weapon/body plus five supporting slots and basic Archer arrows. It reports
front-facing burst, conditional rear damage, pet damage and Priest recovery
separately. It does not treat paper burst as measured sustained farming speed.
Pathing, casting downtime, incoming attacks, party support and positioning
still require real play-session evidence for further tuning.

## Implementation and verification

`server/class_signatures.py` defines the added content and role metadata.
`server/balance_audit.py` checks coverage. `server/configure_balance.py` builds
versioned PUB, shops, drops, skills and configuration from preserved originals.
`server/patches/etheos-class-signatures.patch` follows the earlier native patches.
The same normal native damage, item-use, inventory and learned-skill paths
remain authoritative; the adapter provides early errors and synchronized UI.

Reproduce the checks with:

```sh
python3 -m unittest discover -s server -p test_balance.py
python3 -m unittest discover -s server -p 'test_*state.py'
python3 server/balance_audit.py --runtime work/balance-v3/runtime \
  --report work/balance-v3/coverage-report.json
python3 server/test_class_signatures_live.py
python3 server/test_balance_live.py \
  --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64
```

Native tests create disposable accounts and databases. Guaranteed drop chances,
fixed damage and harmless stationary targets exist only in those fixtures.
Live rollout requires a stopped-world private backup, accepted binary/content
hashes, preservation of accounts/progression/ownership and verified service
health. The signed Android update synchronizes the catalog and interface.

## Released and verified

Profile 3 is installed on the live world. The stopped-world backup is
`/opt/aster-vale/backups/balance-v3-20261027T222738Z`. Migration preserved all
accounts, progression, learned skills, unrelated settings and total ownership;
no additional worn items needed moving. All three services and public HTTPS
health passed. Public WSS acceptance hatched an egg on a newly created dev
character, checked permanent learning, summoned the real pet, observed initial
and upkeep TP charges, rejected a retained Priest heal and dismissed the pet.
Existing player accounts were not used as fixtures.

Verification passed 12 content/migration unit tests, 137 adapter state tests,
515 native acceptance checks including 36 class/level builds, 24 dedicated
class-signature checks and 24 Godot client checks. The full native patch stack
reapplies identically. An unused operator connection logged a keepalive timeout
in the long acceptance harness; all gameplay assertions and client checks
completed successfully. Reports are saved beside this document under
`class-signatures-*-report.json`.

The signed Android release is **0.43.0 (75)**. Its signing certificate and
embedded catalog match the accepted build. The APK is available locally at
`builds/aster-vale-0.43.0-release.apk`. No physical Android device was connected,
so installation and touch gameplay on a handset remain untested for this build.

The level-45 comparison puts front-facing, single-target burst within about
20% across professions, while reporting backstab, regeneration and pet output
explicitly. These are role-aware starting budgets. Equal overall usefulness
still needs live farming, boss and party-session measurements; this release
does not claim identical strength in every encounter.
