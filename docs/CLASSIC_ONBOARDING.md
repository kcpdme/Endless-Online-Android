# Classic Tutorial Island start

New characters start at level 0 in the original Tutorial Island house, map 192,
at 7,6. Their inventory, equipment and learned spells are empty: no free Gold,
Dagger, Oak Shield, clothes or Heal Self. Both genders and all four supported
skin choices use the same original birth location.

The original house chest still supplies Peasant Suit / Peasant Clothes, as in
classic EO. Goats on the island retain their original outfit, Goat Horn and Gold
drops. Cyndi, in the original shop (map 193), retains the original recipe:
**Dagger = 2 Goat Horns**, with no Gold requirement. Her original purchase options
and the other island quests and NPCs are preserved.

The original dock crossing on map 195, tile 21,6, requires **level 4**. It lands
on mainland map 1 at 7,21. Walk north through the sheep fields on map 2; the
Aeven entrance requires **level 5**. Neither crossing, its door, destination,
level requirement nor any map artwork has been modified.

Original content references: [classic starting house and chest](https://apollo-games.com/eoclassic/map.php?map=192),
[classic mainland/Aeven gate](https://apollo-games.com/eoclassic/map.php?map=2),
and the supplied native EMF/shop/drop files. The pinned server's original SQL
schema independently specifies the same birth map and coordinates.

`configure_starters.py` clears all native item/spell overrides and both paperdolls,
and sets the original spawn. `configure_onboarding.py` validates the birth tile,
Cyndi recipe and both original level gates before applying configuration. It adds
two homes and a small **reward-free Aster Vale routing quest** in the previously
unused default quest slot 0; this glue is authored here, not recovered classic
quest content. It never grants items, Gold or EXP or changes a class or level.

For a new player, the routing quest keeps death respawns on Tutorial Island until
the boat reaches mainland map 1. It then uses the boat's mainland arrival until
the player enters Aeven, when the home becomes Aeven. Progress persists across
logout. This prevents an island death from skipping the intended boat journey.
Existing mainland characters end the routing check without changing their homes,
possessions or learned spells. Existing innkeepers and citizenship questions
remain intact.

Apply with the native world stopped and a consistent private runtime/database
backup:

```sh
python3 server/configure_onboarding.py --runtime /path/to/runtime --world-stopped
```

Then restart the native world and adapters. `setup.py` applies the same policy
after staging original maps, shops and balance data. The tool refuses an occupied
quest 0, a changed boat/gate/recipe or a conflicting reserved home before writing.
No account database is opened. This is a server configuration/content update;
Android 0.50.0 already supports these original maps, chests, crafting and quests.

Verification reports are `classic-onboarding-native-report.json`,
`classic-onboarding-deployment-report.json`, `classic-onboarding-public-report.json`
and `classic-onboarding-client-report.json`. The separate natural-farming report
records 19 unmodified goat kills to earn two horns, followed by native crafting
and the original outfit chest. The remaining lifecycle/gate fixture seeds two
horns after verifying bare birth so it can repeat those checks independently
of random loot timing. Gameplay checks use disposable or
fresh regular test characters; existing real player characters are not used.
