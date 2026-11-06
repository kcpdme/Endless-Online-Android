# Dragon Warrior recipes and full Archer shot damage

The subsequent [Android 0.58.4 update](SIDE_NPC_V584.md) adds a separate 20%
bonus to Archer basic bow hits against adjacent NPCs. Farther shots retain the
full normal impact described here; cadence and Dragon recipes are unchanged.

This server content update works with Android 0.58.3. Reopen Dragon Warrior's
shop and choose **Craft** after reconnecting.

## Classic behavior and the new recipes

The pinned [Apollo EO Classic shop 40](https://apollo-games.com/eoclassic/shop.php?shop=40)
record names NPC 253 **Dragon Warrior**. Its only trade is buying a player's
Dragon Claw for 250 Gold; there are no items for purchase or classic recipes.
The client lists only owned items in Sell, so all three tabs previously appeared
empty when the player carried no Dragon Claws. The deployed data matched that
reference. Apollo is a classic reference server/database, rather than the current
private original server's source.

Two requested custom recipes now provide an alternate path to the existing
Dragon armor. Each costs **10 Dragon Claws, 10 Dragon Wings and 200 Gold**:

- Draco, item 458, male armor.
- Dracota, item 459, female armor.

Both retain their current dropped-item stats, Warrior ownership and level-35
requirement. Adding an alternate recipe does not apply the usual crafted-only
stat bonus. The classic claw buyback remains 250 Gold. No direct equipment sales
or new item IDs are introduced. The migration updates only the shop, public
acquisition metadata and installed-content manifest; fresh setup creates the
same recipes.

## Dragon drops

The [classic Dragon record, NPC 225](https://apollo-games.com/eoclassic/npc.php?npc=225)
and the actual deployed table agree:

| Item | Chance per kill |
| --- | ---: |
| Saw Sword | 1% |
| Draco | 1% |
| Dracota | 1% |
| Scav Bow | 0.05% |
| Dragon Wing | 10% |
| Dragon Claw | 10% |
| 100–500 Gold | 40% |

Native DropRate and GoldDropRate are both 100%, with DropRateMode 3. The ordinary
table totals 63.05%, so none of these probabilities is compressed by the gold
cap. The bound dragon egg has its own Summoner-only bonus roll. Rare equipment
was already configured and selectable: no drop-rate increase or drop-table edit
is needed. Rolls remain independent between kills, rather than guaranteeing an
item after 100 kills.

## Archer damage correction

Restoring the classic attack cadence left the old fast-bow damage tradeoffs in
place: Reinforced Hunting Bow/Longbow dealt 95% basic damage, Crossbow 85%, and
Scav Bow/Dawn Longbow 70%, despite no longer firing faster. Every bow now has
**100% shot impact** while retaining the native 600 ms minimum and 620 ms client
timing. Bow ranges, arrow bonuses, equipment stats and skill costs are unchanged.

The existing milestone threshold is unchanged: every class must exceed 60% of
the strongest sustained damage at levels 25, 35 and 45, and 55% at level 15.
At levels 35 and 45 the Archer model improves from 75.92/94.05 to 104.61/128.12
sustained DPS, approximately 69% of the best class, and passes. These are matched
60-second model estimates, rather than promised farming rates.

The separate full-equipment audit now uses the same 600 ms attack constant as
the native server and milestone model; it previously still assumed 500 ms and
read obsolete fast/close-range metadata. Its close-range estimate is the same
as the ordinary basic attack. Generated guide text also reflects full impact
and the fixed cadence.

## Summoner attack stat

Summoner attack comes from equipment plus `0.25 × CHA + 0.10 × INT + 2`, with
native integer rounding. Four additional CHA therefore generally add one point
to each end of the attack range; ten INT generally add one. CHA also contributes
to accuracy and maximum TP. CON contributes HP and defense. Active pets roll
the owner's equipped attack range and apply their tier's power multiplier,
then target armor and hit chance. The fallback additive pet formula is disabled
by the deployed OwnerScaledPets setting.

## Verification

- Fifteen balance tests pass, including the previously failing Archer threshold
  and unchanged male/female Dragon armor stats. Thresholds were not lowered.
- Four Dragon unit checks pass, including migration idempotency, preservation of
  unrelated offers/content/ownership, classic facts, and the compiled native loot
  selector over 200,000 evenly spaced rolls. The latter gives exactly 2,000 rolls
  each to Saw Sword, Draco and Dracota, verifying their 1% intervals without a
  flaky random-farming assertion.
- Real native Dragon Warrior transactions pass in an isolated world: hot rehash,
  classic claw buyback, both recipes, exact ingredient consumption, rejection with
  missing materials and persisted crafted items. The same check passes against
  a private copy of the deployed runtime.
- Twenty-four native attack scenarios pass, checking every class, all seven bows,
  near/far targets, forged rapid packets and progression-disabled behavior. Every
  successful Archer hit against an unarmored noncritical fixture falls in its
  full equipped damage range. The same suite is run against a private copy of
  the deployed runtime before applying the update.
- Two cadence migration tests, four class-audit tests and 21 adapter-state tests
  pass. Native binary, NPC/map files, equipment PUB definitions and drop tables
  are preserved by deployment. No player database migration is required.

Local test logs and deployment receipts are under `work/dragon-warrior-v583/`.

Deployment saved the previous files under
`/opt/aster-vale/backups/dragon-warrior-archer-20261105T193536Z`. Native hot rehash
kept world PID 539188 running; the two connection services restarted to load the
new Python/public metadata. All 300 checked map/PUB/drop files and the native
binary stayed identical. Private configuration retained its owner and permissions,
and all unrelated settings, including EXP/drop rates, were preserved. A public
WSS registration, login, character entry, new recipe/source metadata, full bow
impact metadata, basic strike and disconnect check passed. Native shop transaction
checks also passed again against a copy of the final deployed runtime.
