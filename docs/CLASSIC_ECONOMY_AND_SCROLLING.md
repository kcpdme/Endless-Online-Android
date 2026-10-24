# Classic economy and touch scrolling — v0.40.1

The production world now uses **100% monster drops**, replacing the previous
200% multiplier and EODelta item tables. EXP remains **1000% (10×)**.
Existing accounts, inventory, maps and character stats are preserved.

## Source and restoration

`server/content/classic-economy.json` pins the public
[Apollo EO Classic database](https://apollo-games.com/eoclassic/) captured on
2026-10-24, with a URL and SHA-256 for every source page. It contains all
159 combat NPC tables (262 drop rows; 47 explicitly empty tables), 50 Gold
pile records, and all 42 shops (382 buy/sell rows and 38 recipes).
Gold records from the item page were cross-checked against every NPC page.
Probabilities use the database's displayed effective chances, including its
classic proportional caps and published decimal precision.

`tools/import_classic_economy.py` reproduces the reviewed capture from public
pages. The capture is a development step; the running game never fetches prices
or drop data from an external site. Example:

```sh
python3 tools/import_classic_economy.py --cache work/classic-economy-sources \
  --npc-catalog client/content/catalog.json --out work/classic-economy-review.json
```

`server/configure_classic_economy.py` applies the pinned snapshot only as part
of a stopped-world operation. It checks coverage against the current ENF,
restores all monster tables, and preserves non-economy configuration. Setup
runs it after the supplied EODelta import and feature content, preventing
future setup from restoring inflated prices or drops. The separate rate
configuration also defaults to DropRate 100%.

The native `etheos-classic-gold.patch` gives Gold its own 100% rate. Weighted
mode 3 still drops at most one item/pile per kill. Its default negative
GoldDropRate retains the previous server behavior for deployments that have
not enabled the classic override. The current world uses DropRate 100% and
GoldDropRate 100% together.

Classic Baru Flock ID 491 is remapped to 492 because 491 is already the custom
admin blade. The admin weapon remains intact and is excluded from monster
loot. Baru/Baruta recipes require an Oron/Orona and 40 Flocks, with no added
Gold charge. Examples of restored prices: Aeven Mana Potion buy 120 / sell 10;
desert Small Health Potion buy 120 / sell 10.

## Inn and bank audit

The inn already used the classic formula and keeps it:
**missing HP + missing TP**, in Gold. The client now explains that formula
beside the quote. For maximum HP 1000 / TP 442, full HP with empty TP costs
442 Gold; both empty cost 1442 Gold. Full HP and TP needs no paid rest.

A disposable native world reproduced the live character's attributes and
outfit, then applied deficits only to its private copy. The native quote,
payment and full recovery matched exactly. The live character was never
changed by the probe. One recorded case was HP 500/1000 and TP 0/417, costing
917 Gold; native maxima depend on the equipped items.

Gold deposits and withdrawals have no fee. The first locker upgrade costs
1000 Gold, then 2000, increasing by 1000 for each upgrade. Other native fees
are explicitly restored: haircut 200 × level, marriage 500, divorce 10000,
guild creation 50000, recruitment 1000 and jukebox 25.

## Mobile scrolling

The shared `client/scripts/mobile_scroll.gd` handles modal ScrollContainers,
ItemLists and RichTextLabels, including ongoing quests. Scrollbars have
36-logical-pixel touch targets, a visible Gold thumb and a minimum thumb size.
Drag the content directly to scroll, including over quest text and buttons.
A nine-pixel threshold distinguishes taps from swipes, and dragging stays
captured outside the list until release. A swipe never becomes a button tap.
Text editors retain native focus and keyboard handling. The compact HUD chat
retains its existing gesture control.

## Verification and delivery

- 4 classic economy tests: full source coverage, preservation/idempotency,
  repeated native patch setup, and deterministic compiled native Gold/item
  selection and probability caps.
- 2 native rate tests and the feature-content preservation test passed.
- 135 existing server state checks passed.
- 92 private native checks passed: all 42 shops and recipes, actual purchase
  and sale, inn quote/payment/recovery, bank fees and locker upgrades.
- 13 touch gesture checks passed, including quest-card scrolling, swipes over
  buttons, exactly-once taps, canceled touches and skill-list scrolling.
- Native/Godot feature integration passed 33 checks. Quest journal, guild,
  shop-close, movement, character flow, social and music/quest regressions passed.
- Android release 0.40.1, code 67, passed signing/alignment checks and was
  installed as an update on the connected phone. Installed APK bytes matched,
  the original installation identity was preserved, and launch had no script
  or fatal errors. Gesture behavior was verified by injected touch tests;
  the user was actively playing, so their character was not used for a manual
  on-device swipe test.

APK SHA-256: `17eaacbc3435350532a130ef4a047733dc70964f4a1baa737ae252f45276e6fd`.
The final server-only drop normalization requires no further APK update.

Sanitized validation records accompany this document. Deployment used a
consistent stopped-world backup and verified the installer's account database
bytes were unchanged. Restoring the paired runtime/source snapshot returns the
previous economy; do not replace a live account database with an old snapshot
after players have resumed playing.
