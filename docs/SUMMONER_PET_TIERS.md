# Summoner pet choices — profile 7, Android 0.45.2

The Aeven Eggkeeper now sells **16 deterministic pet eggs**, beside the market
at **map 5, tile 35,46**. Only Summoners can buy and hatch them. Every appearance
also has its own monster drop source, eligible only when the normal loot winner
is a Summoner. Buying removes the dependence on a lucky drop after death;
monster eggs save the purchase cost. Hatching reveals the advertised creature,
without a random rarity roll.

| Tier | Hatch level | Choices | Gold per egg | Call TP | Upkeep / 2 seconds | Hit ceiling |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| Normal | 5 | Penguin, Fox, Goat | 100 | 10 | 1 | 82% |
| Rare | 10 | Wolf, Butterfly, Skeleton | 600 | 18 | 2 | 86% |
| Epic | 20 | Carnivo, Cursed Mask, Headless Hunter | 2,000 | 30 | 3 | 90% |
| Legend | 30 | Twin Demon, Dark Magician, Reaper | 6,000 | 38 | 4 | 93% |
| Mythic | 40 | Banshi, Drake, King Wurm, Wraith | 12,000 | 45 | 5 | 95% |

## Why this improves the class

Previously Summoners had three appearances, no pet until level 8, and no
reliable egg replacement after death. Their personal attack budget already
assumes substantial pet damage, so an unavailable pet makes the class feel weak.
An affordable first pet and a predictable replacement shop make that identity
available from level 5 in the main level 1–50 journey. Later tiers provide visible
goals inside the player's expected level range.

Within each tier, appearances have identical attack power, accuracy, hit ceiling,
attack interval, TP costs and effects. Flying art does not bypass terrain; every
pet uses the same movement and combat rules. No species has hidden healing,
area damage, tanking or stat buffs. The shop shows tier-coloured egg icons, the
actual creature preview, prices, costs and bond rules. Inventory and skill
details use the same installed definitions.

Tier attack multipliers are **0.65 / 1.05 / 1.20 / 1.25 / 1.30**. Before target
armour, native attack power is:

`floor((10 + level × 0.5 + CHA × 0.55 + INT × 0.2) × tier power) ± 2`

Tier accuracy adds **0 / 3 / 6 / 9 / 12** to owner accuracy. The native hit formula
still considers the target's evade, then applies the tier's hit ceiling. The
ceiling is not a guaranteed hit percentage. Higher tiers improve both accuracy
and the ceiling while retaining misses. The attack interval remains one second.
Initial cast times are 0.48 seconds for Normal/Rare and 0.96 for higher tiers.

TP, level gates and replacement Gold remain meaningful costs. All tier upgrades
use ordinary in-game Gold. Eggs have no resale offer and remain untradeable,
undroppable and excluded from shared chests. They can be kept privately as spares.
Buying a future-tier egg is allowed for Summoners; its hatch level still applies.

## Bond and class rules

There is still **one living bond and one visible pet**. Hatching consumes one
egg; duplicate hatching preserves the spare. Cast the granted summon to call it.
Owner death destroys the bond even if the pet is dismissed, out of TP or hidden
by switching class. Spare eggs survive. Travel, logout, dismissal
and TP exhaustion preserve the bond and allow another TP-funded call.

To change appearance, forget the old summon at a skill master and hatch another
egg. Forgetting now immediately dismisses the active pet and cancels its pending
summon. The old egg is not returned. Pet bonds cannot spend permanent training
points. Existing egg and bond slots keep their tier, price, TP costs and combat budget.
Profile 7 changes the hatch and summon levels to 5 / 10 / 20 / 30 / 40. The revised appearances replace old ones within
those slots; no account migration or reset is required.

| Previous appearance | Revised appearance | Preserved tier |
| --- | --- | --- |
| Wurm | Carnivo | Epic |
| Bat | Skeleton | Rare |
| Baby Turtle | Cursed Mask | Epic |
| Skeleton | Headless Hunter | Epic |
| Banshi | Reaper | Legend |
| Wraith | Twin Demon | Legend |
| Phoenix | Banshi | Mythic |

Other existing slots retain their appearances. The new sixteenth egg adds Mythic
Wraith. Owned inventory eggs, private storage and learned living bonds retain
their IDs and quantities, so replacement value is preserved. Level access now
follows the profile-7 gates above.
Monster drop sources now follow the revised appearances.

Pets assist the monster their owner actively attacks and stop after five seconds
without a command. They cannot farm unattended, tank, earn independent rewards or
enter PK/arena combat. The existing stronger Summoner PK spell scale is retained.
Other classes cannot summon pets or acquire their restricted spell/equipment
bonuses by changing class. Purchase restrictions also run in the native server,
independently of the mobile UI and adapter.

## Balance check

The existing six-class, matched-loadout model now includes the best available
pet tier at each milestone. It counts caster and pet together:

| Level | Summoner combined DPS | Pet contribution | Magician DPS | Warrior DPS |
| --- | ---: | ---: | ---: | ---: |
| 1 | 12.52 | 0.00 | 18.08 | 19.42 |
| 8 | 29.78 | 11.97 | 43.71 | 50.08 |
| 15 | 77.56 | 34.23 | 78.62 | 72.38 |
| 25 | 113.33 | 54.36 | 107.61 | 105.57 |
| 35 | 141.45 | 76.63 | 142.93 | 141.64 |
| 45 | 182.40 | 95.95 | 181.44 | 168.08 |

These are pre-critical single-target expectations with sufficient TP and a pet
adjacent to its commanded target. Movement, pathing, upkeep, cast time, range,
backstabs, healing and area attacks change actual results. This is evidence for
the combined budget, not a claim of identical farming or PvP performance. The
main endgame budget stays close to profile 4; variety and reliable access make
the class more attractive without adding another full damage dealer for free.

All sixteen pets use complete original idle, movement and attack art in all
four directions. Eggkeeper stock follows the requested tier and creature order.

## Validation and rollout

Profile 7 changes pet hatch and summon levels to **5 / 10 / 20 / 30 / 40**.
Tier prices, accuracy, damage and TP costs retain their profile-6 values. Native
executable, original equipment, non-pet spells, classes, skillmaster offers,
Eggkeeper and maps retain their installed definitions. Level 1 has no pet, and
level 8 now uses Normal; those early model budgets are consequently lower.

- 12 balance/content tests, 11 tier tests and 3 provisioning tests passed.
- Native pet acceptance passed **135 checks**, including rejection one level
  below each tier and successful hatching at its exact required level.
- The real Godot client passed **111 checks**, including sixteen previews,
  two phone viewports, native purchase, hatching and summoning.
- A native level-50 kit test confirmed 1,108 TP, 579 HP and weight 60/70.
  During 96 seconds it observed 42 Mythic upkeep deductions and one 110-TP
  standing recovery pulse. Full depletion was not observed.
- The exact 39-slot locker collection loaded in native Aeven Bank; spare
  clothes could be withdrawn and deposited within the weight limit.
- Public TLS/WebSocket acceptance passed with a fresh regular developer fixture.

Profile 7 is live. The stopped-world backup is
`/opt/aster-vale/backups/summoner-50-v7-20261028T071540Z`. The balance installer
preserved database bytes. A separate transaction then added the requested
**summontest** character beside Skylar on the same account, preserving every
existing character, every account and all other database tables. Existing player
characters were not used as test fixtures.

Android **0.45.2 / code 82** is installed on the Galaxy S23 Ultra as a full signed
update with app data and original install identity preserved. Signature, 16 KB
alignment, embedded catalog/map and installed byte checks passed. The app process
started; the screen was dozing, so physical handset gameplay was not verified.
Sanitized `summoner-50-*` reports record the scope of verification.

APK SHA-256: `163ba238e19b8cba5abf44d6ae3e00d4411b42e443129aae81e51ac60d4b65b4`.

See [Level-50 Summoner test](SUMMONER_LEVEL_50_TEST.md) for the prepared character,
locker contents, and TP-duration estimates. The complete equipment, spell, egg
and model guide is regenerated at `outputs/balance-revamp/balance-guide.html`.
