# Permanent pet collection and original EXP

Android 0.50.0 (code 92), balance profile 12.

## Pet lifecycle

- Hatching an unhatched Egg consumes one and permanently learns that species.
  A matching **Hatched Egg** appears as a weightless, bound Lore keepsake.
- A Summoner can collect all 16 species. Duplicate species stay unhatched;
  spare unhatched Eggs can be sold to the Eggkeeper for 40% of their price.
- The top paw icon opens the collection. Choose a collected species and bind it;
  the bottom paw summons or dismisses the bound pet.
- Dismissal, TP exhaustion and death start **one shared five-minute recovery**.
  No species can be summoned or rebound during it. Expiry allows choosing another
  collected pet or recalling the previous one. Reconnecting cannot reset it.
- Ordinary, PK and arena deaths preserve pet ownership and Hatched Eggs.
  Pets still cannot fight in PK areas or arenas; the existing Summoner PK spell
  allowance remains in effect. Arena elimination starts recovery for the loser.
- Changing maps or logging out removes the active pet entity without starting
  recovery. A running timer continues across travel and reconnects.
- Native spell ownership is authoritative. Selling, trading, dropping, junking,
  chest-sharing or forgetting a Hatched Egg/pet is refused. Learned ownership
  permits selection even if the physical keepsake is in the bank.
- Egg rolls remain restricted to Summoners who win the source monster's loot.
  Another Summoner cannot collect their egg after ordinary drop protection ends.

Tier prices, drop odds, owner damage multipliers and upkeep remain unchanged:

| Tier | Level | Price | Drop chance | Owner attack | TP / 2 sec |
|---|---:|---:|---:|---:|---:|
| Normal | 5 | 100 | 5% | ×0.45 | 2 |
| Rare | 10 | 6,000 | 2% | ×0.70 | 5 |
| Epic | 20 | 20,000 | 1% | ×1.00 | 7 |
| Legend | 30 | 60,000 | 0.5% | ×1.20 | 9 |
| Mythic | 40 | 100,000 | 0.1% | ×1.50 | 12 |

The five smooth vector egg designs now have separate unhatched and cracked,
spirit-lit Hatched Egg variants. Pet previews use existing creature sprites.

## Migration and persistence

`server/pet_collection.py` migrates transactionally and once per database. It
preserves every existing learned pet, creates missing keepsakes, refunds previous
pet training levels to skill points, and leaves other skills and existing bag,
bank, equipment, account, level, EXP and admin values intact. A full bag defers a
keepsake instead of overflowing or removing ownership; later binding materializes
it when space is available. Bank copies are recognized without duplication.

`aster_pet_state` stores the selected spell and absolute recovery deadline. The
native server validates all summon/bind paths, including raw original-client
packets. The adapter only reads server state and publishes countdown snapshots.
The native changes are an additive pinned patch in
`server/patches/etheos-pet-collection.patch`, applied by `server/setup.py`.

The rollout stops services, backs up runtime/adapter data, validates hashes,
checks account/item/spell conservation, applies the profile and migration, restores
runtime ownership, and starts services. Failure restores the complete backup.
Previously destroyed mortal bonds cannot be reconstructed without historical
ownership evidence; existing learned bonds are preserved.

## Emotes

A tap opens five translucent choices. Tapping a choice sends its native emote;
tapping outside closes and consumes the tap; inactivity closes it in three
seconds. Hold-and-drag and numpad shortcuts still work. The original enhanced
four-frame animation and 240 ms frame timing remain intact.

Chair and floor emotes now follow the same gender/facing-specific head offsets
as the original hair sprites: chair 9–12 world pixels, floor 18–23 pixels lower.
The offset applies to the local character, nearby players and drink/music emotes.
Standing placement stays unchanged.

## EXP

`ExpRate = 100%` restores ×1 kill EXP. The profile also restores all 305 original
NPC EXP values byte-for-byte from its saved original ENF baseline; combat HP,
armor and class balance are retained. Pet entities grant no extra EXP.

Native quest `GiveEXP` already adds its literal argument without `ExpRate`.
Quest files and their written rewards are preserved. Existing player EXP and
levels are not reset or reduced. `server/configure_rates.py` also defaults to ×1
so rerunning the rate tool cannot reintroduce ×5.

## Verification

See `pet-collection-v12-native-report.json`, `pet-collection-v12-client-report.json`,
`pet-collection-v12-deployment-report.json`, `pet-collection-v12-public-report.json`
and `pet-collection-v12-release-report.json` for measured release results.

Tests run in a disposable native world and database, including all 16 hatch/call
paths, prices/buyback, owner-scaled damage, upkeep, multiple collected species,
shared cooldown bypass attempts, death/reconnect/TP exhaustion, raw item guards,
original kill/quest EXP, and the Godot UI. Synthetic rendered fixtures cover the
collection at phone sizes and standing/chair/floor emote placement. Real player
characters are not used for gameplay QA.
