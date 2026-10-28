# Pet and class balance, profile 9

Android 0.47.0 (code 84) uses the same release signer and preserves saved login.
The complete equipment, spell, tier and level-by-level comparison is in
[the balance guide](../outputs/balance-revamp/balance-guide.html).

## Combat and progression

- Egg chances for eligible Summoners: Normal/Rare/Epic **2%**, Legend **1%**,
  Mythic **0.5%**, on their species' source monsters and with normal loot rights.
  These are independent percentage rolls, unaffected by ordinary global drop
  multipliers, and use the existing single-item loot slot. Eggs remain bound.
- A pet rolls its owner's current equipped attack and multiplies by **0.45 / 0.7 /
  1 / 1.2 / 1.5**, before enemy defence and tier accuracy. Fractional results use
  unbiased rounding: attack 10 gives Normal 4 or 5, averaging 4.5, and Mythic 15.
  The old independent level/CHA/INT pet damage budget is disabled.
- All five tiers spend **2 / 5 / 7 / 9 / 12 TP every two seconds** while called.
  Mythic eggs cost **100,000 Gold**. Call costs and level gates stay unchanged.
- Pets retaliate after an aggressive monster actually hurts a surviving owner.
  They do not start unprovoked fights. Monsters cannot target pets. Owner death
  breaks the bond; dismissal, logout, travel and TP exhaustion preserve it.
- Red Bow fires at **×1**, Crossbow **×1.2**, Scav/Dawn **×1.5**. Scav/Dawn get
  **×2** against a combat target within **two tiles directly ahead**. Hunting Bow
  stays ×1; Reinforced Hunting Bow and Longbow are ×1.1. Existing shot impact,
  range and elemental-arrow bonuses remain. The native wall clock owns cadence.
- Rogues walk **twice as fast**: client prediction uses 0.21 versus 0.42 seconds
  per tile; the native execution queue enforces 0.20 versus 0.40. Network arrivals
  remain queued. This never doubles attack speed. Remote players interpolate
  using the moving character's duration.
- Magician area magic gains **25% damage**: radius-one power is 100%, radius-two
  75%, with existing target caps, TP costs and casting time. Single-target scaling
  stays 2.4. Summoner PvE spell scaling is 1.15 alongside its revised pet damage.
- Priest keeps **2% maximum HP every two seconds standing**, 4% sitting, halved in
  PK areas. WIS-scaled self, targeted and party healing remains Priest-only.

The guide separates front-facing output, conditional Rogue backstabs, close bow
fire and fully populated area spells. It does not treat those as universally
available sustained damage. At level 35, the matched equipment model gives about
104 Summoner DPS including its pet, 120 Scav basic DPS at range or 160 nearby,
217 conditional rear Rogue DPS, and 312 total Magician area DPS across five
available targets. Priest's best targeted heal at that level restores 222 HP;
free standing renewal is 7 HP every two seconds. These figures include the
published cast/attack timing and target defence assumptions, not measured farming
rates or guaranteed PvP parity.

The level-50 prepared Summoner still has 1,108 maximum TP in its original kit.
A Mythic call spends 45, then upkeep spends 12 per two seconds while standing
recovery adds 4. With no attacks/spells/potions and ideal timer alignment, that
suggests roughly **4 minutes 26 seconds** from full TP after calling. Native
checks observed both tick streams over 12 seconds; full depletion was not timed.

## Touch controls

Inventory is back on the lower-right row, beside Sit and the Summoner paw button.
Conversations remains beside the bottom message field. Hold the new smile button
right of Send, drag through five translucent vertical emotes, and release to
activate. Releasing outside cancels. The picker fits above the keyboard; original
EO emote artwork and nearby native broadcasts are used. Desktop numpad emotes
remain available.

## Deployment and verification

The guarded rollout backed up the runtime and adapter, verified content hashes,
repeated the installer identically, and preserved unrelated maps/settings. Only
`summontest.admin` changed to 4 on Skylar's account; no character stats, inventory,
Gold, spells or bank contents were reset. Relog to refresh admin access.

Checks completed: 29 Python unit tests; 60 native combat/range/recovery/movement
checks; 515 native balance checks; 140 pet-tier checks; 31 owner-damage,
retaliation, egg-roll and native-emote checks; 134 real Godot pet/UI checks; and
14 client movement/cadence checks. The complete 22-patch stack reproduces the
compiled native source. The signed APK's embedded catalog, manifest and Aeven map
match the accepted build. Public HTTPS/WSS checks use a fresh regular development
character and verify persistence through the production native world.

Machine-readable evidence is in `pet-owner-*-report.json` beside this document.

The connected Samsung S23 Ultra received the complete signed update, entered
`summontest` with its saved login, displayed the admin crown, opened Inventory
from the lower-right bag button, and displayed Happy above the character after a
real hold/drag/release gesture. No scoped Godot/Android runtime errors appeared.
