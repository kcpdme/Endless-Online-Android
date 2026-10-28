# Summoner eggs and living pet bonds — profile 4

Profile 6 retains mortal bonds and offers a shop with sixteen pet choices across
five tiers. Its current acquisition and combat values are documented in
[Summoner pet tiers](SUMMONER_PET_TIERS.md). The drop-only rules and three-pet
values below describe the historical profile-4 release.

This replaces profile 3's permanent summon unlocks. Eggs are consumable pet
bonds, exclusive to Summoners. The Android client is 0.44.0 / code 78.

## Acquisition and ownership

Wolfman (NPC 74) drops Wolf Spirit Egg 609; Wurm (82) drops Wurm Spirit Egg
610; Dragon (225) drops Drake Spirit Egg 611. Base table entries remain 3%,
1.5% and 8%; native drop mode and world multipliers determine effective odds.
Normal loot-sharing rules first select the winning character. An egg is eligible
only if that winner is currently a Summoner and the killed NPC is its configured
source. Other classes roll the ordinary table without egg entries. Party
membership alone does not grant every member a separate egg.

Eggs use native Lore restrictions: no player trading, ground dropping or shared
chest deposit. A dropped egg is also claimed by its winner's character name,
so expired protection or recycled session IDs cannot transfer it to another
Summoner. Private character storage remains allowed. Egg crafting recipes are
removed; there is no shop route. Previously owned eggs remain owned and become
bound under the new rules. Off-class owners can keep them but cannot hatch them.

## One living bond

A Summoner can hatch one bond at a time: Wolf at level 8, Wurm at 25, Drake at
40. Hatching consumes exactly one egg and grants the corresponding summon skill.
That learned skill is the persistent record of the **living pet**, not an
unlimited permanent unlock. Cast it to call the pet. Existing initial TP costs
(18/30/45) and upkeep (2/3/4 TP every two seconds) still apply.

The pet's life is linked to its owner. Owner death removes the pet and the
bond, including when the pet was dismissed, absent due to TP exhaustion, or
hidden by switching class. The owner must hatch another egg before summoning
again. Spare inventory eggs, offensive skills and other possessions remain
under their usual rules. Death is saved immediately with the normal respawn
state, so reconnecting cannot restore the old bond.

Travel, logout, normal dismissal, distance and insufficient TP remove the
visible pet without breaking its bond. It can be called again for TP without
another egg. Only one pet can be visible. It assists active fights, cannot
autonomously select enemies or tank, and does not produce separate EXP/loot.
Its real damage goes through its owner's normal native combat/reward handling.
To replace a living bond voluntarily, release its summon at a skillmaster and
hatch the desired egg; the old egg is not refunded.

## Damage budget

Pet attack before the native damage/armour/hit formula is:

`floor((10 + level × 0.5 + CHA × 0.55 + INT × 0.2) × species power) ± 2`

Species power is 1.0 / 1.15 / 1.3. Attacks occur at most once a second while
adjacent to the commanded enemy. The prior formula was
`floor((5 + level × 0.3 + CHA × 0.22 + INT × 0.12) × species power) ± 2`.
Pet attack grows with the owner's build rather than receiving a flat boss-sized
attack value at low levels.

To fund that stronger pet, the caster's CHA/INT basic-attack contribution is
0.20/0.10 and its PvE spell multiplier is 1.0. Pets contribute approximately
45–55% of the modeled combined single-target output at levels 8–45. At level
45 the matched-loadout model gives Summoner 182.40 combined DPS, including
95.95 from the pet; Magician gives 181.44 and Warrior 168.08. These are
pre-critical, adjacent-target expectations with sufficient TP, not measured
farming rates. Pathing, casting, survival, areas and party support affect play.

Pets remain disabled in PK/arena areas. The caster's PK spell multiplier is
2.8 to offset both the unavailable pet and its reduced personal attack stats.
This is a compensation budget, not evidence of identical PvP outcomes.

Mortal bonds cannot consume permanent skill-training points. Offensive and
support abilities retain their existing training progression.

## Existing characters and rollout

The stopped-world, transactional migration retains the highest-tier legacy
summon as the one living bond. Each extra legacy summon becomes one bound egg;
all former summon-training points are refunded and the retained bond starts
at rank zero. Non-pet skills, character progression, currency and unrelated
items are preserved. An independent migration marker prevents repeat refunds.
Malformed character data rolls the entire bond migration back.

The native patch is `server/patches/etheos-mortal-spirit-eggs.patch`, following
the profile 3 patch. `configure_balance.py` requires its binary marker before
writing profile 4 content. Apply character migrations only with the world
stopped and backed up, using `--migrate-characters`. Keep native, adapter,
content and client metadata together. Historical profile 3 reports describe
the former rules; the current rules are documented here.

## Verification and live release

Profile 4 is live. The stopped-world backup is
`/opt/aster-vale/backups/mortal-eggs-v4-20261028T043758Z`. The rollout verified
all unrelated tables, account/authentication state, non-pet skills and character
progression. Item ownership plus already-spent egg bonds is conserved. Eight
characters received a total of 24 refunded summon-training points; no extra
legacy bonds needed conversion to spare eggs in this database.

Verification passed 12 balance/content tests, three migration/adapter contract
tests, 137 adapter state tests, 37 native signature/lifecycle checks and 514
native regression checks across 36 class/level builds. The real Godot client
passed 30 live catalog/preview checks and all six class descriptions passed 60
layout checks. Raw packets tested other-class/source drop rejection, permanent
owner-only pickup, trading, ground drops, shared chests, legacy training refunds,
lethal spikes, reconnect persistence and the off-class/absent-pet death bypass.
Test-only guaranteed drops and spike/chest fixtures never modified the public
world. The complete native patch stack applies identically twice.

Public TLS/WebSocket acceptance used a fresh developer account to verify the
accepted profile, bound-egg metadata, hatching, duplicate preservation, visible
native pets, exact initial/upkeep TP, dismissal and bond/spare-egg persistence
across reconnect. The public HTTPS health endpoint and all three services pass.
Reports beside this document record the validation, deployment and public scope.

The signed 0.44.0 / code 78 update is installed on the connected Galaxy S23
Ultra. Installed bytes match the accepted APK and the original installation
record is preserved. Startup logs contain no script/parse/fatal errors. The
phone is at its lock screen, so physical gameplay interaction was not repeated
for this release; see `mortal-eggs-phone-report.json` for that limitation.
