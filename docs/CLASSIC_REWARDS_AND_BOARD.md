# Classic rewards, centred speech and town-board tabs

Android **0.50.1** (code 93), balance profile **13**.

## Original reward audit

The native drop configuration matches **262 original entries across 159 combat
NPC tables**, including quantities, chances and explicit empty tables. All **305
original NPC EXP fields** match the saved original ENF baseline. The native rates
are `ExpRate = 100%`, `DropRate = 100%`, `GoldDropRate = 100%`, with classic
weighted selection mode 3. Original quest reward amounts remain unmultiplied.

For Goat (#7), the classic values are:

- Goat Horn ×1: **10%**, so two horns require **20 kills on average**.
- Peasant Suit ×1: 5%; Peasant Clothes ×1: 5%.
- Gold ×1–5: 10%; monster reward: **8 EXP** at ×1.

The observed two horns after 19 kills were normal random variation. This was a
fresh Peasant using bare fists, with the original goat spawns/drop settings.
It then crafted a Dagger from those two earned horns without paying Gold.

Sources: the [official EO drop-rate record](https://eoserv.net/forum/topic/23270),
the pinned classic database snapshot in `server/content/classic-economy.json`,
and the original supplied ENF data. The stored classic snapshot includes source
URLs and hashes; it is the existing reviewed project reference, not modern EO+
loot/progression data.

### Summoner egg correction

Previously, a successful egg roll occupied the normal drop slot. Thus a Summoner
with a 5% Normal egg roll had a 9.5% effective Goat Horn chance, although ordinary
Peasants still had the original 10%. Profile 13 fixes this interaction.

Eggs are now **independent bonus loot**, preserving the complete classic item/Gold
roll. A kill can produce its ordinary drop and a bound egg together. The ordinary
reward stays in the original NPC-death packet; the extra egg uses native Item_Add.
The same Summoner/source/winner ownership checks and advertised tier chances
apply. Other players cannot take the egg after normal protection expires.

`etheos-classic-bonus-eggs.patch` is additive to the pinned native patch stack.
`BonusSpiritEggDrops` defaults off for older configurations; profile 13 enables
it and requires a compatible binary. Existing item/spell/class/pet combat values,
all maps, original quest files and player data remain unchanged by this patch.

Run the read-only audit with:

```sh
python3 server/audit_classic_rewards.py --runtime /path/to/runtime
```

It compares every original table/EXP definition, checks all three global rates
and flags egg replacement behavior. It never opens the account database.

## Overhead chat

Overhead speech labels and their drunk haze use centred horizontal alignment.
Short text, explicit line breaks and automatically wrapped lines are all centred
inside the existing bubble. Its measured height, padding, camera tracking and
screen-edge positioning remain intact.

## Town board

The town board opens on **Read**, with subjects and authors, native post ages,
selection, double-tap reading, and a Back to posts action. **Post** opens the
subject/message composer. Switching tabs preserves the draft. Publication clears
it and returns to Read only after native acceptance; rejection keeps the form.
The Publish button remains visible in a fixed footer, including on small phones.

The subject accepts up to 64 characters and the message up to 256, matching the
existing gateway limits. Empty/oversized messages are refused. Native board
posting limits remain in place. Administrative removal is visible only for admins
and is still validated by the server. No test message was published to the live
board: publication/read checks used a disposable native world.

## Verification

- `classic-rewards-audit-report.json`: complete classic table/EXP comparison.
- `classic-rewards-native-report.json`: pet tiers, cooldowns, owner binding, death,
  original kill/quest EXP, and guaranteed classic Gold plus a simultaneous egg.
- `classic-town-board-client-report.json`: real regular-player native posting and
  reading, Read default, preserved drafts, centred wrapped speech, keyboard and
  two phone layouts.
- `classic-rewards-deployment-report.json`: backed-up rollout and live audit;
  account database bytes, maps, PUB stats, quests, possessions and pets preserved.
- `classic-rewards-public-report.json`: public TLS login/shop/hatch/bind/recovery.
- `classic-rewards-release-report.json`: build, signing and installation status.

The matching classic Tutorial Island journey is described in
[Classic onboarding](CLASSIC_ONBOARDING.md).
