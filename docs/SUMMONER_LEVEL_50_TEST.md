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

## Current TP recovery — profile 8

The same equipped character retains **1,108 TP**. Standing now restores **4 TP
every two seconds**, and sitting restores **8 TP**. These fast class pulses
replace the old 90-second TP recovery. PK halves the recovery rate before
rounding. A Mythic call still costs 45 TP, and upkeep still costs 5 TP per
configured two-second check, processed on the pet’s AI tick. The current native
test observed those costs and the 4-TP pulses over 12 seconds.

The older profile-7 13–17 minute standing estimate is superseded. Exact two-second
pet upkeep would give roughly 35 minutes of pet-only standing uptime; actual AI
spacing can extend it. Sitting can sustain idle upkeep. Full depletion has not
been timed. Spirit Bolt (5 TP), Lance (14), Grasp (22), Storm (32) and Dark Bite
(38) consume TP on top of upkeep. Basic attacks have no TP cost. Leave potions
unused and note spells cast when timing a combat session.

The **Summon/Dismiss paw button** replaces the old bottom Inventory position.
Inventory is now on the top row and Conversations is beside the message field.
See [Combat progression](COMBAT_PROGRESSION.md) for all current class changes.

## Release and verification

Original character provisioning: profile **7**, Android **0.45.2 / code 82**.
Current installed release: profile **8**, Android **0.46.0 / code 83**. The new gates are enforced by native
handlers as well as adapter/client checks. Native acceptance passed 135 checks;
Godot passed 111 checks; 26 unit tests passed. The balance install was repeated
with identical results. A stopped-world backup was taken before adding the
character. Every existing character/account and all other database rows were
preserved. Public-server acceptance used a separate fresh developer fixture.

The signed phone update preserved app data and installed bytes match the release.
The app process started, but the phone display was dozing, so handset gameplay
was not verified. Select summontest after reconnecting to start the manual test.
