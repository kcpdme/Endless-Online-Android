# Validation scope

v0.26.1 checks original480ms Self Heal chant and local480ms cast-pose recovery,
with no added acknowledgement-time lock. State tests total54; combat_mobile
covers late ACK/rejection and ongoing walking. Native timing comparison is in
`heal-v29-timing-report.json`. Native600ms spell cooldown remains unchanged.


v0.26 adds moving potion/skill, boss-child despawn, attack-timing and chat-scroll
regressions. Run `python3 -m unittest discover -s server -p "test_*state.py" -v`
(53 cases), then Godot `res://tests/combat_mobile.gd`, `movement_timing.gd`,
`network_regressions.gd`, `movement_controls.gd`, `short_movement.gd` and
`gameplay_smoke.gd`. Native isolated-server evidence is in
`combat-v28-native-report.json`; the phone/build report is
`gameplay-v28-phone-report.json`. The native test creates its own disposable DB
and map fixture; it never stages a human player or alters live-world NPCs.


Version 0.10 adds native streaming/pickup regressions, delayed real-scene touch
and Rat-chase tests, secure session handoff, native wrong-password rejection,
legacy hash recovery, larger joystick capture and six original weapon
appearances. A live Godot test equips all six weapons with five automatic
Remove-ACK-then-Add swaps, checking exact bag conservation, native receipts and
original appearance bindings. Battle health strips use native HP percentages and
clear on death, timeout and map changes. The original Gold icon replaces the HUD
glyph. Parser/catalog tests now total 23.

Reproduce additional checks against local services:

```sh
python3 -m unittest discover -s server -p test_live_state.py -v
/path/to/Godot --headless --path client --script res://tests/network_regressions.gd
python3 server/test_reconnect.py --deps-dir work/server-build/python
python3 server/test_weapons.py --godot /path/to/Godot
```

`latency_proxy.py` binds loopback only and pipelines packets without logging
credentials. Run it against port 8183 with `--port 8194 --delay-ms 120 --jitter-ms 80`
before `test_mobile_flow.py --godot /path/to/Godot`. A second proxy on 8195 with
300/150 ms delay/jitter supports `test_mobile_flow.py --chase --url
ws://127.0.0.1:8195/ws --godot /path/to/Godot`. These stage only new dev accounts.
The known Rat Tail is a controlled player drop; the independent native kill-loot
test covers actual random NPC drops and ownership.

APK 0.10.0 was signed, checked for 16-KiB ZIP alignment and installed on the
Galaxy S23 Ultra; offline save bytes matched before and after the update.

`gameplay-v10-report.json` contains sanitized measured results. Private accounts,
recovery passwords, device saves and fixture credentials are excluded.

Version 0.9 restores the supplied original Version-1 per-NPC shop catalogue
(48 trade/craft records) and 152 NPC drop-table entries. The public runtime was
backed up before the change; existing accounts, inventory and PasswordSalt were
preserved. Actual hosted native tests passed Shop Bob grocery Buy/Sell, Cyndi
Craft, quantities, insufficient/oversized transaction guards, protected pickup,
observer add/remove packets and persistence after relogin. A hosted kill test
collected one actual Rat Tail (item 249) after 17 native kills using unchanged
random drop rates; only the fresh dev fixture's attributes were staged.

The actual Godot scene passed the same shop flow over public WSS, including
sprite targeting, approach to the keeper, Buy/Sell/Craft acknowledgements,
Android Back, Gold corner badges, original stats-panel values and Dagger EIF
bonuses/stack quantity. Local source checks passed 22 parser/catalog tests,
world/quantity/layout and gameplay smoke checks, movement/collision/combat/stats
regressions and native economy/kill-loot integration. Public WSS login, movement,
equipment and offline-save isolation also passed. APK version 0.9.0 is signed,
16-KiB ZIP-aligned and installed on the Galaxy S23 Ultra with its offline save
preserved byte for byte. Generated assets, downloaded archives, private test
credentials and runtime databases remain ignored by Git.

Reproduce native economy tests against an already-running local runtime with:

```sh
python3 server/test_economy.py --state-dir work/server-build
python3 server/test_kill_loot.py --state-dir work/server-build
```

`client/tests/economy_live.gd` additionally requires a fresh isolated dev fixture
in map 193 with `1,1000;258,4;` in inventory and the three
`ASTER_VALE_TEST_HOST`, `ASTER_VALE_TEST_USERNAME`, `ASTER_VALE_TEST_PASSWORD`
environment variables. Use temporary XDG user-data/config directories. Never
stage or reuse a human player's character for these tests.

Version 0.8 adds real NPC collision, nonblocking 520 ms attacks, health/TP bars,
hit/death feedback, valid Aeven respawn, character attributes/stat allocation,
and original item bonuses/requirements. `server/test_combat.py` verifies real
outgoing damage, NPC retaliation, point persistence, equipment-derived stats,
zero HP on death and 50% native HP recovery after the queued respawn. It creates
and stages only a fresh dev fixture. The Godot movement regression also covers
NPC blocking, attack recovery before movement, death input suppression,
distinct INT/WIS display and Android Back. A real 60-FPS Godot held-attack probe
recorded five swings at 522–543 ms intervals, with no idle refresh during the
held attack; an outstanding strike receipt did not block another strike.

```sh
python3 server/test_combat.py --state-dir /path/to/server-state
```


Version 0.7 is signed, verified for 16-KiB ZIP alignment and installed on the
physical Galaxy S23 Ultra. Its existing offline save is byte-for-byte identical
before and after updating. The same APK passes hosted WSS login/world entry on
an Android 15 emulator; held touch-joystick movement from (40,40) to (44,40)
is confirmed again through a native server reconnect. Offline save bytes remain
unchanged during hosted play.

Version 0.7 movement changes pass real local and public WSS scene tests,
including immediate prediction, native confirmation, equipment and offline-save
isolation. `streaming-v07-test.json` records live peer/NPC pushes, corrections,
bounded network-jitter bursts and map negotiation using fresh dev accounts.
`MOVEMENT.md` explains the original-code comparison and measured regression.

```sh
/path/to/Godot --headless --path client --script res://tests/movement.gd
python3 server/test_streaming.py --state-dir /path/to/server-state --deps-dir /path/to/websocket-deps
ASTER_VALE_TEST_HOST=wss://eo.kcpd.top/ws python3 scripts/test_online.py --godot /path/to/Godot
```

The prediction regression simulates outstanding inputs and verifies that matching
ACKs and metadata updates preserve animation, rejected steps reconcile, and
nearby movement interpolates independently of the local character. The live
streaming test stages only newly-created dev characters in its local database;
never point its database setup at unrelated characters. Legacy nonstreaming
WebSocket map-travel tests also pass against the updated adapter.

Version 0.6 uses Godot 4.7.2. The Android APK was signed, checked for
16-KiB ZIP alignment, installed on an Android 15 emulator and updated on a
physical Galaxy S23 Ultra running Android 16. The physical device's existing
offline save was compared byte for byte immediately before and after updating.
The physical phone also passed normal-TLS public WSS login and world entry,
rendered the neighboring map, and displayed the zero-value Gold bag slot.
Screenshots confirmed world rendering reaches both screen edges. Offline
progress remained unchanged during hosted play.

## Client checks

```sh
python3 scripts/test_client.py --godot /path/to/Godot
python3 scripts/test_client.py --world --godot /path/to/Godot
python3 scripts/test_online.py --godot /path/to/Godot
```

Both wrappers isolate user data in a temporary directory. The offline smoke
covers collision/pathfinding, joystick release and multitouch, held attack
recovery, modal/focus cancellation, Android Back behavior, combat/loot,
separate bag/paperdoll, equipment, saves, migration and reset.

The online test requires the real running gateway and etheos. It creates a
throwaway account/character, then checks actual login, Welcome, NPC snapshots,
server-confirmed movement and weapon equip/unequip. It writes an offline fixture
through the actual scene, checks byte-for-byte preservation during online play,
checks restoration after returning offline, and checks fresh authentication
when returning online. Connection text is hidden over modal panels. Tests use
real replies, not a simulated network service. Optional environment variables
`ASTER_VALE_TEST_USERNAME` and `ASTER_VALE_TEST_PASSWORD` reuse a fixture account.

The emulator UI was also used to create an account and character, enter Aeven,
open the wooden bag, equip all three starter items and inspect the original
paperdoll. A second independent EO session observed joystick movement from
40,40 to 41,39 and unchanged coordinates two seconds after release.

## Content and native server checks

```sh
python3 -m pip install -r requirements-tools.txt
EO_RUNTIME=/path/to/staged/runtime python3 -m unittest discover -s tools -v
python3 server/test_online.py --report /path/to/work/online-report.json
```

All 22 importer/catalog tests passed against the reference content. Real-data
checks skip when input archives/runtime data are unavailable. These cover map
and PUB parsing, real source hashes, eight hero equipment variants, all item
icons, 158 world NPC graphic sets/offsets and five original money piles.

Native and JSON-gateway two-session tests both confirmed authoritative movement.
Real Rat damage/death, owned-item drop/pickup, equip/unequip and SQLite position/
equipment persistence passed. See `server/online-validation-report.json` and
`server/ONLINE.md` for the exact scope. Native tests create dev-prefixed accounts;
they preserve the database and salt.

All 282 maps are imported and loaded on confirmed server transitions. The live
Godot scene passed a public WSS Aeven/map4 round trip with rendered geometry and
server coordinates agreeing. Native Aeven Store door entry/return also passed.
The inventory/world smoke verifies zero-value Gold, three stacked Daggers,
wearing/removing one, quantity persistence and wide-screen HUD anchors. Eight
malformed legacy map47 destinations are guarded. Native shops and hosted WSS are implemented in the later milestones above. Quests, guild/party controls, spells and additional appearance combinations remain unfinished. Bank/lockers, player inspection/trade and chat are covered by the v0.11 tests below. Nearby entities use streamed positions with interpolation and movement animation. Server quest/chest content gaps remain recorded
in `server/VALIDATION.md`. Private credentials, device saves, generated assets,
compiled APKs and screenshots are excluded from the public source repository.


## v0.11: native services, chat, mobile HUD and peer animation

The pinned original Bank/Locker/Paperdoll/Trade/Talk handlers and corresponding
EndlessClient actions/dialogs were checked before implementing the protocol.
`server/services.py` changes Gold/items only from native replies. Trade offer
changes reset both approvals, completion applies both native inventory deltas,
and cancellation never transfers items. Native storage is guarded while trading.

Validation uses newly provisioned dev accounts; no operator characters, database
resets, password salts or production world restarts are used:

- 16 server state regressions cover movement/collection, observer equipment,
  first-attack facing, storage restrictions, exact locker quantity replies,
  trade resets/completion/cancel, inspection isolation and original chat formats.
- 24 real-content importer/catalog tests pass, including opaque NPC frame bounds.
- Godot gameplay, movement and network regressions pass. Dynamic joystick tests
  check exact touch origin, sliding base, retained pointer, release and multitouch.
- Two native clients through local WS and public WSS pass bank deposit/withdraw,
  locker expansion, item deposit/whole-stack withdrawal, 15-slot inspection,
  nearby/global/private chat, trade completion/cancellation and persistence.
- Actual Godot dialogs pass bank/locker/player tap, deposit/withdraw, native trade
  offer/accept and exact bag deltas, chat log/bubble/whisper, original inspection
  without overwriting self equipment, hidden old HUD and visible heart/TP vitals.
  Rendered screenshots were reviewed for dialog bounds and layout.
- A separate real Godot observer verifies equipment changes and both weapon
  swing frames for Dagger/Ultima in all four directions, without observer Refresh.
  Both local and deployed public WSS tests pass.

Sanitized evidence: `docs/services-v11-local-report.json`,
`docs/services-v11-public-report.json`, `docs/services-v11-ui-report.json`,
`docs/peer-visuals-v11-public-report.json`. Runtime fixtures and raw screenshots
remain ignored. `learnings.md` records native packet layouts, codec restrictions,
trade limits, fixture pitfalls, deployment and device handoff details.


## v0.12: EXP, Nearby Send and inventory item use

21 server state regressions and the Godot gameplay/network checks pass. The
actual Godot bag Use button was exercised against local native EO and the public
WSS endpoint with a fresh dev character. Tests verify health/mana restoration,
exact remaining quantities and vitals, full-HP refusal without consumption,
Beach scroll warp plus rendered destination, same-destination refusal, Recall
home, Nearby Send closing the modal while retaining the speech bubble, and
correct level/EXP progress. Original Item.cpp and EndlessClient item handlers
were used for packet layouts. No existing player data is staged or reset.
See `consumables-v12-local-report.json` and `consumables-v12-public-report.json`.


## Native skills (v0.13)

Run packet regressions with `python3 -m unittest discover -s server -p '*_state.py'`
and content checks with `python3 tools/test_catalog.py`. With the real local
world/gateway/WebSocket bridge running and original skill-master data installed:

```sh
python3 server/test_skills.py --fixtures-out work/skills-fixtures-private.json --report docs/skills-local-report.json
python3 server/test_skills_ui.py --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --report docs/skills-ui-local-report.json --screenshots work/skills-screenshots
```

The first creates three disconnected dev fixtures, stages only their stats and
spells, then checks native timed casts and master transactions with two observing
sessions. The second uses the actual game scene, native touch dispatch, skill
book and master UI. Pass --url and --fixture-file for prepared isolated fixtures
on a hosted server; keep that file ignored/private. Never use operator accounts.
Sanitized v0.13 local/public and UI reports are in this directory. Original
art/icons and actual effect frames were visually reviewed with the GL renderer.


## Counter shops and joystick target arbitration (v0.14)

```sh
python3 server/test_touch_interactions.py --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --report docs/touch-v14-local-report.json --screenshots work/v14-touch-screenshots
```

This uses fresh dev fixtures only, matching the customer's map125/tile6,4.
It injects real native touches through `Input.parse_input_event`, including the
engine's emulated mouse. It verifies Marble's shop opens without movement,
actual native buy/sell across the counter, a spell target inside the joystick
activation zone with exactly one cast, and normal empty-ground drag/release.
Do not replace this with direct `map_click` calls: those bypass the regression.
`--url` and `--fixture-file` support privately prepared hosted dev fixtures.
NPCs wander, so use live sprite positions, not their static EMF spawn centers.


## Shop details and crafting readability (v0.15)

```sh
python3 server/test_shop_ui.py --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --report docs/shop-v15-local-report.json --screenshots work/v15-shop-screenshots
```

Uses a fresh dev character with native Marble ingredients. It exercises actual
buy/sell/craft acknowledgements, all four material-row bounds at1280x720,
independent native finger swipes (with tap-versus-drag selection), compact prices and preservation of selection/quantity/
scroll through native snapshots. It also checks duplicated material totals,
missing/readiness state and1544x720 layout. Use --url and --fixture-file for
prepared hosted dev fixtures; never use operator accounts or publish that file.
