# Summoner pet choices — profile 5, Android 0.45.0

The Aeven Eggkeeper now sells **15 deterministic pet eggs**, beside the market
at **map 5, tile 35,46**. Only Summoners can buy and hatch them. Every appearance
also has its own monster drop source, eligible only when the normal loot winner
is a Summoner. Buying removes the dependence on a lucky drop after death;
monster eggs save the purchase cost. Hatching reveals the advertised creature,
without a random rarity roll.

| Tier | Hatch level | Choices | Gold per egg | Call TP | Upkeep / 2 seconds | Hit ceiling |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| Normal | 1 | Penguin, Goat, Fox | 100 | 10 | 1 | 82% |
| Rare | 8 | Wolf, Bat, Butterfly | 600 | 18 | 2 | 86% |
| Epic | 25 | Wurm, Baby Turtle, Skeleton | 2,000 | 30 | 3 | 90% |
| Legend | 30 | Banshi, Wraith, Dark Magician | 6,000 | 38 | 4 | 93% |
| Mythic | 40 | Drake, Phoenix, King Wurm | 12,000 | 45 | 5 | 95% |

## Why this improves the class

Previously Summoners had three appearances, no pet until level 8, and no
reliable egg replacement after death. Their personal attack budget already
assumes substantial pet damage, so an unavailable pet makes the class feel weak.
An affordable first pet and a predictable replacement shop make that identity
available throughout the main level 1–50 journey. Later tiers provide visible
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
points. Existing Wolf, Wurm and Drake egg/spell/NPC identities are preserved;
existing characters need no migration or reset.

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
| 1 | 18.26 | 5.74 | 18.08 | 19.42 |
| 8 | 38.45 | 20.64 | 43.71 | 50.08 |
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

Ancient Wraith's supplied idle and walking frames are transparent, so it was
excluded. King Wurm provides the third Mythic appearance with complete original
art. All fifteen pets have visible idle and movement frames in all directions.

## Validation and rollout

- 12 balance/content tests, 7 tier tests, 3 bond migration/contract tests and
  137 adapter state tests passed.
- The final native regression passed **515 checks** across 36 class/level builds.
- Native class signatures and mortal-bond regressions passed **39 checks**.
- The pet acceptance passed **123 checks**, buying and hatching every egg,
  summoning every appearance, checking all five upkeep/damage tiers, duplicate
  protection, raw purchase/hatch rejection, new-bond death/reconnect and actual
  skill-master release/replacement.
- The real Godot client passed **105 checks** across 15 previews and two phone
  viewports, including native shop purchase, hatching and visible summoning.
- The full native patch stack applies identically twice. Runtime configuration
  and the single merchant-map edit are also repeatable. Visual shop captures
  were inspected with the real renderer at 1280×720.

Profile 5 is live. The stopped-world backup is
`/opt/aster-vale/backups/pet-tiers-v5-20261028T060725Z`. Installation preserved
account database bytes and all runtime content outside the reviewed balance
definitions/configuration, native executable and Aeven merchant spawn. Sky Haven's
walking maps and the admin teleport source are preserved. No character migration
was run. Public TLS/WebSocket acceptance used a fresh regular developer account
to buy all five tiers, hatch/summon Penguin, verify exact TP charges, retain
spares, dismiss and reconnect. Existing player accounts were not used as fixtures.

Android **0.45.0 / code 80** is installed on the Galaxy S23 Ultra as a full signed
update, preserving app data and original install identity. Installed APK bytes
match the accepted release. Signature, 16 KB alignment and embedded catalog/map
checks passed. See the accompanying sanitized reports for exact verification
scope and startup results. Physical handset walking/pet gameplay was not repeated.

APK SHA-256: `348ce7b245816dee5aba4adecc63943e4ec8c14300d371d06762ff77cbf54fdd`.

The complete equipment, spell, egg and model guide is regenerated at
`outputs/balance-revamp/balance-guide.html`; this file can be read without Canvas.
