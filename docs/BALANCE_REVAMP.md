# Class and equipment revamp for levels 1–50

Profile 7 sets pet hatch/summon levels to 5 / 10 / 20 / 30 / 40 and retains
the requested sixteen pet appearances across five equal-within-tier combat budgets
and the Aeven Eggkeeper. See [Summoner pet tiers](SUMMONER_PET_TIERS.md) for
current acquisition, balance and lifecycle rules.

Profile 4 replaces permanent summon unlocks with bound eggs and death-limited
pet bonds. See [Mortal spirit eggs](MORTAL_SPIRIT_EGGS.md) for that release.

Profile 3 extends this release with class signatures, permanent egg unlocks and
complete gear coverage. See [Class signatures and eggs](CLASS_SIGNATURES_AND_EGGS.md).


Profile 2 supersedes the class permissions and shared-heal rules of the first
release. See [Class identity and summons](CLASS_IDENTITY_AND_SUMMONS.md) for the
implemented rules, real pets, recipes and safe class changes.

The main journey is levels 1–50. Levels 30–50 contain worthwhile bosses, class
equipment and long-term crafting goals. Levels beyond 50 remain possible, with
the existing cubic experience curve; no existing level or experience is removed.
The current 5× monster EXP rate stays in place for this first pass. Power and
acquisition are calibrated around the 1–50 journey, rather than level 250 items.

## Class roles

- **Warrior:** STR damage, highest HP and armour. Reliable solo melee and the
  safest front line. Whirlwind provides a limited area attack.
- **Rogue:** AGI-led damage, accuracy and evasion, with some STR value. Precision
  weapons and Twin Strike reward an offensive build without Warrior durability.
- **Archer:** AGI-led ranged damage and Aimed Shot. Bows and arrows contribute to
  its damage budget. Range is a survival advantage, not a reason for weak damage.
- **Magician:** INT-led attacks and stronger spell scaling. Fire, thunder and
  bounded area attacks give burst and group clearing at a real TP cost.
- **Priest / High Priest:** WIS-led damage, strong healing and high TP. Holy Light
  provides a solo attack; group healing is useful without allowing unlimited
  healing from every class. High Priest retains its existing class identity and
  shares Priest equipment and skill access.
- **Summoner:** CHA/INT spirit caster with Spirit Bolt, Spirit Lance and one
  real native spirit companion. Active combat commands the pet; it cannot farm
  unattended. CHA becomes a useful combat investment for this class.
- **Peasant:** viable starter attacks and common potions while choosing a profession.

The Wise Man class menu explains the builds and includes Summoner. Class
selection is free. Skill masters offer a free rebuild: attributes and trained
skill levels are refunded, while learned spells, items, level and EXP are kept.
Changing class does not permit using another class's restricted abilities or
receiving bonuses from incompatible equipment.

## Attribute and combat rules

Enable class formulas and give each class its own physical/spirit damage,
accuracy, evade, armour, HP and TP formula. Spell attacks use class-scaled attack
power plus base spell power and a bounded training bonus. Healing scales with the
appropriate caster attributes. Healing spells are exclusive to Priest / High Priest; other classes use potions.

Use a smooth armour reduction and a bounded hit chance, so small armour upgrades
remain meaningful. Apply the same rules to PvE and PK; keep PK's damage modifier.
Area attacks have a small radius, a target cap and one TP charge per cast.
Friendly group healing reaches only nearby party members. Server-side class and
level checks apply even to a previously learned spell or a forged client request.

Skill training caps at 10 meaningful ranks. Existing ranks above the cap do not
increase damage beyond 10; the free rebuild returns their invested points.
Admin Heal and the operator blade remain administrator tools.

## Equipment journey

Combat milestones are **1, 8, 15, 25, 35 and 45**. Every class has affordable
starter equipment, regional upgrades, specialist gear and a reachable level-45
weapon and body outfit. Male/female equivalents receive equal combat stats.

Existing graphics, names, item IDs, ingredient identities and player ownership
are retained. Ordinary plates receive a defence/HP progression. Light clothes
offer AGI, accuracy and evade. Robes offer INT/WIS/TP. Spirit equipment offers CHA.
Cosmetic colour variants and costumes remain equivalent appearance choices and
are labelled accordingly; expensive combat crafting must provide combat value.

Oron/Orona becomes a level-25 precision milestone. Draco and rare Hero Plate
become later defensive choices. Baru/Baruta becomes a level-45 all-round upgrade
that preserves and improves Oron's strengths. Its recipe uses Oron/Orona and
six daily Flocks, rather than forty. Baru is the flexible all-round choice; rare
class outfits provide stronger primary attributes, with extra tank defence for
Warrior and evasion for Rogue/Archer. New class-specific level-45 recipes consume
earlier equipment and existing boss materials, keeping those rewards useful.

Hats, boots, shields, gloves, jewellery and accessories get modest supporting
budgets. Their combined bonuses must not overwhelm the weapon/body progression.
Ranged arrows and caster staves are included in the class power budget.

## Spells, healing and consumables

Provide learnable abilities throughout levels 1–45 at accessible native skill
masters. Early class attacks do not require irrelevant STR on a caster. Later
abilities have level and class gates and Gold prices appropriate to
their stage. Repurpose unfinished spell entries with truthful names and effects,
instead of advertising shields or summons that the server does not implement.

Heal Self is Priest-only, like the other healing spells. Priest heals scale
with WIS; Magician and Summoner have their own offensive abilities. Powerful attacks require
TP and bounded training. Rebalance the old 1–300 Ice Blast and 1,000-HP Heaven
outliers. Keep actual chant time, cost and effect descriptions synchronized in
the client.

Scale small, medium and big HP/TP potions to the new health and mana pools. Keep
their native inventory transactions and cooldowns. Future coupon redemptions
provide a useful starter bundle, not a near-endgame weapon and 1,000 potions.
Existing redeemed items and redemption records are preserved; Lens of Truth
becomes an appropriately gated midgame item.

## Content and reward difficulty

Retain original map topology, service NPC protection, quests, drops and boss
identities. Tune a defined set of progression monsters and bosses for the new
power bands: ordinary targets should support short solo fights, while level
30–50 bosses reward several players or a strong specialist build. Evaluate
both damage output and damage taken; equal paper DPS alone is not class balance.
Do not infer guaranteed farming times from rare-drop percentages.

## Delivery and existing characters

Implement the native behaviour behind a versioned configuration switch, with a
repeatable installer and a generated before/after manifest. Reject unexpected
item identities. Install into an isolated runtime first. New setup runs apply
the same versioned profile after the original content installers.

For rollout, stop the world, take a consistent private database/config/content/
binary backup, then install the tested binary, content and gateway together.
Move newly ineligible equipped items into their owner's bag transactionally,
without changing total ownership. Keep account authentication, level, EXP,
quests, guilds, money and learned-spell ownership. The free rebuild is voluntary.
Record the migration so retrying does not duplicate items or points.

Synchronize the Android catalog and descriptions, build a signed update, and
install it when the device is available. Publish this ordinary Markdown plan
and a normal HTML report so viewing does not depend on a canvas renderer.

## Acceptance checks

1. Installer is repeatable and preserves graphics, map routes, protected NPCs,
   operator equipment, player ownership and unrelated configuration.
2. At levels 1, 8, 15, 25, 35 and 45, each class has equippable, obtainable
   gear and a viable attack. Class/level restrictions are enforced natively.
3. Compare representative builds and enemies for raw attack, actual hit damage,
   survivability, resource cost and area output. Priest solo damage can be lower
   in exchange for healing, but cannot be ineffective.
4. Real native sessions verify class selection, stat rebuilding, skill learning,
   damage, self/other/group healing, one-charge area attacks and refusal paths.
5. The real client verifies updated equipment requirements, class guidance,
   spells, costs and targeting. Existing movement, admin, inventory and account
   flows continue to work.
6. Rollout health, binary/content hashes and the database migration's preservation
   checks must pass before claiming the new balance is live.

## Implemented releases

Version 0.41.0 introduced profile 1. Version 0.42.0 contains profile 2:
543 item definitions, 387 equipment definitions, 39 skills and three native
companion definitions. The updated rules and recipes are in
[Class identity and summons](CLASS_IDENTITY_AND_SUMMONS.md).

The searchable [balance-guide.html](../outputs/balance-revamp/balance-guide.html)
contains all equipment and skill values, acquisition flags, class access and
modelled milestones. `tools/export_balance.py` regenerates it and synchronizes
the Android catalog while preserving existing artwork.

Reproduce isolated acceptance with:

```sh
python3 -m unittest discover -s server -p test_balance.py
python3 server/test_balance_live.py --runtime /path/to/balanced/runtime \
  --godot /path/to/godot
```

Native behaviour is saved in `server/patches/etheos-balance-v1.patch` and
`server/patches/etheos-class-identity.patch`. Equipment migration requires a
stopped world and a consistent private backup. Versioned validation reports
record completed test, deployment and Android outcomes.
