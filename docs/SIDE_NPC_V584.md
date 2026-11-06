# Side-approaching NPCs and adjacent Archer damage — Android 0.58.4

The movement fix is in Android 0.58.4, version code 110. The adjacent damage
bonus is enforced by the native server and described in its public metadata.

## Movement

The old client deferred any step whose destination had an NPC within one tile.
An NPC approaching the road from the side therefore caused an extra native
confirmation wait even though the intended tile was empty. The client now
predicts those clear-road steps normally. It still defers destinations occupied
by an NPC's displayed movement, and native occupancy remains authoritative.

If an NPC actually claims a predicted destination, presentation pauses until
clearance or native correction. Corrections stop and reconcile the predicted
walk while retaining the held key or joystick; death, map transition, forced
stops and disconnect still cancel their controls. Input release prevents further
retries and finishes only an already committed step. Actual walls and occupied
NPC/player tiles retain their collision checks and player ghosting rules.

## Archer

For an Archer using a ranged weapon, a basic hit on the combat NPC directly
adjacent in the attack direction multiplies the rolled basic damage by **6/5**,
using integer rounding before the normal armor/critical/hit calculations.
The branch requires CombatProgression and affects the actual adjacent victim,
rather than checking whether any unrelated NPC happens to be nearby.

Farther NPC hits, unarmed/nonranged attacks, other classes, PvP and spell damage
are unchanged. Miss chance does not improve. The native basic attack minimum is
still 600 ms, with 620 ms client timing. No close-range speed bonus is restored.
The milestone and full-equipment models report the NPC bonus separately as
`close_basic_dps`; their ordinary sustained estimates remain based on normal
ranged hits. Native item stats and the Dragon Warrior recipes are unchanged.

## Verification

- 96 movement cases cover four headings, both sides, stationary/approaching NPCs,
  keyboard/joystick input and 30/60/120 FPS. They assert first-frame movement and
  continuous travel past nearby NPCs. Collision races check presentation braking,
  authoritative correction, retained input, first-clear-frame retry and release.
  All 6,826 assertions pass; the previous client fails this suite.
- The existing 24 collision checks, 120 NPC-clearance assertions, movement
  reconciliation, continuous walking at 15–144 FPS, 32 turn/input combinations
  and 180 actual joystick touch traces pass.
- 27 native combat scenarios pass locally and against a private copy of the
  deployed runtime using the new binary. They cover all seven bows next to and
  farther from an NPC, distance-two exclusions, non-Archer classes, barehanded
  Archer, adjacent PvP and disabled progression. Actual hit values match the
  expected integer damage ranges. Forged rapid packets still respect cadence.
- The previous binary, with identical test metadata, fails exactly the seven
  adjacent-bow cases; all its other scenarios pass. This isolates the new effect.
- All 15 balance tests, two timing/metadata tests, four class-audit tests and
  21 adapter-state tests pass. All 30 native patches reproduce the final source.
- Signed APK export passes. ADB installation verifies version/code and the full
  installed APK hash, while retaining the original installation timestamp.

Detailed logs, baseline results and deployment receipts are under
`work/side-npc-v584/`, excluded from source control.

Deployment backed up the previous binary/modules and a read-only SQLite snapshot
under `/opt/aster-vale/backups/side-npc-v584-20261106T092021Z`, then restarted the
native world and both connection services. It preserved all 303 checked maps,
PUB definitions, drop/shop/formula/skill files and the native configuration.
Production player data was not replaced or migrated. All services passed health
checks. Public WSS registration, login, character entry, adjacent-damage metadata,
unchanged Dragon recipes, normal Peasant combat timing and disconnect passed.
