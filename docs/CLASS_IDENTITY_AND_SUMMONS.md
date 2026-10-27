# Class identity, companions and equipment choices

Profile 2 closes the original class-switch exploit. A character can retain a
learned skill, but its current class must own that skill to train or cast it.
The native server checks again when a cast executes. The client shows retained
skills as locked. Switching from Archer to Warrior moves the bow, arrows and
Archer armour into the bag and recalculates attack from the Warrior formula.
Their former bonuses cannot survive the switch. At the bag's hard per-item cap,
a worn copy is retained inert, preserving ownership without granting power.

## Each profession has a job

- Warrior: STR/CON front line, heavy weapons and armour, Cleave, Whirlwind and
  Brutal Strike. Reliable melee and the highest defensive foundation.
- Rogue: AGI/STR precision attacks, evasive clothes, Twin Strike, Hidden Strike
  and Blade Dance. Hidden Blade is a level-25 crafted Rogue weapon. Compared
  with Twin Blades it trades one point from each damage endpoint for three
  accuracy, three evade and twelve TP, supporting a different build.
- Archer: AGI/STR ranged combat. Only Archers use bows, guns and arrows. Aimed
  Shot, Piercing Shot and a capped Arrow Volley give its own progression.
- Magician: INT/WIS damage magic, elemental attacks and bounded area damage.
  No healing spells. Equipment favours spell power and mana.
- Priest / High Priest: WIS/INT holy attacks plus self, targeted and party
  healing. Healing spells belong exclusively to this profession, apart from
  administrator tools. Holy Light keeps solo progression useful.
- Summoner: CHA/INT spirit attacks and one real native creature assistant.
  Its caster multiplier is reduced from 1.8 to 1.2 so pet damage occupies part
  of the class's combined budget. Spirit attacks remain usable without a pet.

Starter tools, ordinary jewellery and accessories, costumes, instruments and
selected hybrid armour remain common. Oron/Orona at 25 and Baru/Baruta at 45
are flexible common choices; specialist outfits offer stronger role bonuses.
Class changes and stat rebuilding remain free. Learned skills, levels, EXP and
item ownership are preserved. Potions provide recovery for every class.

## What a Summoner actually summons

Learn these at the existing class skillmasters:

- Level 8: Summon Spirit Wolf, 18 TP, then 2 TP every two seconds.
- Level 25: Summon Spirit Wurm, 30 TP, then 3 TP every two seconds; 1.15 power.
- Level 40: Summon Spirit Drake, 45 TP, then 4 TP every two seconds; 1.3 power.
- Level 1: Dismiss Companion, free.

A summoned NPC visibly follows its owner for up to 90 seconds. Only one can
exist per character. Replacing it validates the new spawn before dismissing
the old one. Its damage scales with level, CHA and INT and uses normal hit,
armour, aggro, quest, loot and party EXP handling attributed to its owner.

The spirit assists only a monster explicitly attacked by the owner in the
previous five seconds. Its own attacks never extend this command. It does not
find new targets or farm for an idle player. It is an untargetable spirit,
not a tank. Pets cannot fight in PK areas or arenas. Travel, death, logout,
class changes, insufficient upkeep mana, expiration or exceeding the leash
remove it. No pet item, permanent pet inventory or autonomous economy is added.
These limits make a useful first implementation without allowing free tanks
or unattended farming. Creature art reuses existing native graphics.

## Gear variety and crafting

Every equipment definition now carries explicit class access where specialised.
Weapons and armour receive bounded differences within their progression tier:
heavy weapons sacrifice accuracy for top-end damage; precision weapons add
accuracy/evasion; caster foci add TP; heavy armour adds CON/HP; Rogue clothes
add evade; Archer clothes add accuracy; caster robes support mana and their
primary attribute. Cosmetic equivalents deliberately remain equal.

Craft-only definitions receive a small edge: weapons gain damage and one
primary attribute; bodies gain two armour and eight HP; supporting slots get
smaller bonuses. A definition sold and crafted under the same item ID keeps
identical stats because the server does not store per-instance affixes.

Two clear recipe rewards are now available:

- Hidden Blade (Rogue, 25), at NPC 87: one Dark Katana, ten Snake Teeth,
  four Dark Rags and 150 Gold.
- Reinforced Hunting Bow (Archer, 8), at NPC 15: one Hunting Bow,
  eight Bird Feathers, three Wolfman Furs and 100 Gold.

Early Summoner robes, Rogue Scout Mail, Archer Hunter Leather and a Priest
Blessed Staff fill holes created by enforcing ownership. Existing shops sell
these intermediate choices. All new male/female pairs have equal combat stats.
The complete catalog contains 543 items, 387 equipment definitions, 39 skills
and three companion NPC definitions.

## Progression and validation

The main equipment milestones remain levels 1, 8, 15, 25, 35 and 45. Original
levels, EXP and the cubic curve are preserved. Levels 30–50 should contain
reachable long-term rewards; items beyond Oron must improve a role rather than
merely cost more. Class balance is assessed with attack, durability, resource
use, range, area damage, healing and acquisition effort together.

The searchable [HTML guide](../outputs/balance-revamp/balance-guide.html)
contains every equipment and skill definition and deterministic milestone
comparisons. Summoner comparisons include an adjacent commanded pet while TP
is available; they do not claim measured sustained farming speed. Pathing,
upkeep, incoming damage, player movement and parties affect real results.

Native acceptance checks use disposable accounts in an isolated database.
They exercise class-switch equipment removal, raw-packet off-class spell
rejection, real summon damage, one-pet replacement, idle cutoff, mana exhaustion,
dismissal, class changes, travel, logout, healing, crafting and the real Godot
client. Installer and migration checks preserve unrelated records and total
ownership. A stopped-world private backup and verified migration precede live
rollout. Reports record actual outcomes; broad population balance still needs
play-session evidence after release.

Implementation: `server/patches/etheos-class-identity.patch` follows the existing
balance patch; `server/class_identity.py` owns equipment permissions and bounded
styles; `server/configure_balance.py` generates native content, configuration
and version-2 ownership migration. The original baseline directory retains its
`balance-v1-baseline` name so upgrades always rebuild from the same original
content and can detect unexpected operator edits.

## Release status

Profile 2 is live. The stopped-world migration returned seven incompatible worn
items to their owners' bags and verified unchanged total ownership, accounts,
progression, spells and unrelated character values. A private rollback backup
was retained. Public HTTPS/WSS verification created a fresh dev fixture and
confirmed real summoning, exact initial/upkeep TP, Priest-heal rejection and
native dismissal through the public game connection.

Validation passed 515 native acceptance checks across 36 builds, 21 Godot checks,
137 adapter regression tests, 10 content/migration tests and a separate native
expiry test. See [validation](class-identity-validation-report.json),
[native acceptance](class-identity-native-report.json),
[public connection](class-identity-public-report.json), and
[deployment](class-identity-deployment-report.json) for evidence.

The signed Android 0.42.0 update (code 74) contains the synchronized profile-2
catalog and client. No device was connected, so it has not been installed on a
phone. The APK is available in `builds/aster-vale-0.42.0-release.apk`.
