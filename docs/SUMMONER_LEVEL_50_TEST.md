# Level-50 Summoner test character

**summontest** is the second character on Skylar’s existing account. Log out to
character selection, or reconnect, and choose him. He is a regular level-50
Summoner at the Aeven Eggkeeper (map 5, tile 35,45).

## Ready to test

- **1,000,000 Gold** in the bag; no Gold in the bank.
- **579 HP and 1,108 TP**, initially full, with the prepared equipment.
- Base attributes: **90 CHA / 37 CON / 23 INT**. This uses the ordinary 150-point
  level-50 budget. The character has no admin powers or inflated attributes.
- All 15 equipment slots filled. Main gear: Spirit Sceptre, Spirit Vestments,
  Spirit Master Hood, Boots, Gloves and two Spirit Master Rings. The remaining
  slots use common compatible accessories and a Royal Protector offhand.
- All legal Summoner/common weapons, male Summoner/shared caster clothes and
  compatible accessories through level 50 are supplied. Weight **60/70** leaves
  room to withdraw a different outfit. The private locker is fully expanded:
  **39/60 slots** used by the overflow collection.
- One of every **16 egg appearances** in the bag; five spare Wraith eggs in the
  locker. Five Big HP and five Big TP potions in the bag, plus 45 of each in the
  locker. Each potion type totals 50.
- All six eligible offensive/dismiss skills learned without training investment;
  **150 skill points unspent**. No pet bond is pre-hatched.

The exact equipped, bag and locker item list is in
[summoner-50-character-kit-report.json](summoner-50-character-kit-report.json).
Use a locker in Aeven Bank to collect overflow items. Native testing loaded the
whole collection and successfully withdrew and deposited spare clothes.

## Calling a pet

Use one egg from inventory to hatch it, then cast the granted summon from Skills.
For example, use **Wraith Spirit Egg**, then cast its Wraith summon. Only one
living bond is allowed. To try another species while alive, release/forget the
current summon at a skill master, then hatch another egg. The old egg is not
refunded. Owner death breaks the bond; hatch a spare egg to replace it. Dismissal,
travel, logout and running out of TP preserve the bond, so another call needs
TP, rather than another egg.

| Tier | Hatch and summon level | Call TP | Upkeep TP per 2-second check |
| --- | ---: | ---: | ---: |
| Normal | 5 | 10 | 1 |
| Rare | 10 | 18 | 2 |
| Epic | 20 | 30 | 3 |
| Legend | 30 | 38 | 4 |
| Mythic | 40 | 45 | 5 |

## TP measurement

The isolated native world used this exact gear and attributes. It confirmed
**1,108 maximum TP**, the Mythic **45 TP** call, **42 deductions of 5 TP** during
96 seconds, and one standing recovery pulse of **110 TP**. Average observed
upkeep spacing was **2.238 seconds**; the configured check is due every two
seconds, processed on the pet’s AI tick. Timing varies with the world loop.
The full depletion time was **not measured**.

A simple event simulation with no offensive spells, potions, dismissals or extra
summon calls estimates **13–17 minutes of standing Mythic-pet uptime** from a
full bar. It uses 2.0–2.238 second upkeep spacing and the phase of the shared
90-second recovery clock. This is a timing estimate for this loadout, not a
promise of a particular combat session length. Without any TP recovery, the
configured two-second rate alone gives about **7 minutes** after the call.

Standing recovers floor(max TP × 10%) every 90 seconds: **110 TP** for this kit.
Sitting recovers floor(max TP × 20%): **221 TP**. Sitting can nearly or fully
cover idle Mythic upkeep depending on AI timing. Attack spells consume TP on top
of pet upkeep: Spirit Bolt costs 5, Spirit Lance 14, Spirit Grasp 22, Spirit
Storm 32 and Dark Bite 38. Basic attacks have no TP cost. Keep potions unused
when measuring the natural duration, and note which attack spells you cast.

## Release and verification

Profile **7**, Android **0.45.2 / code 82**. The new gates are enforced by native
handlers as well as adapter/client checks. Native acceptance passed 135 checks;
Godot passed 111 checks; 26 unit tests passed. The balance install was repeated
with identical results. A stopped-world backup was taken before adding the
character. Every existing character/account and all other database rows were
preserved. Public-server acceptance used a separate fresh developer fixture.

The signed phone update preserved app data and installed bytes match the release.
The app process started, but the phone display was dozing, so handset gameplay
was not verified. Select summontest after reconnecting to start the manual test.
