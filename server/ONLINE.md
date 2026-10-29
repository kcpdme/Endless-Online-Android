# Real EO online development slice

The Android/Godot client can use `gateway.py`, a Python standard-library JSON-lines adapter to the **real pinned etheos C++ server**. Each gateway connection owns its own native EO v28 TCP session. Account password hashing, character creation, positions, collision, NPCs, combat, inventory and persistence remain on etheos. The adapter translates packet formats and returns actual server snapshots; it does not simulate a world.

## Start

Run etheos using `python3 server/run.py`, then in a second terminal:

```sh
python3 server/gateway.py --host 127.0.0.1 --port 8079 --eo-host 127.0.0.1 --eo-port 8078
```

Both bindings are enforced as loopback. The root development launcher can start the services and configure Android USB forwarding. For a manually attached development device:

```sh
adb reverse tcp:8079 tcp:8079
```

The Android client then connects to `127.0.0.1:8079`. This adapter is a local development transport, with unencrypted JSON credentials restricted to this local connection. A public Android service needs TLS, authentication/abuse controls and a separate deployment design before internet access is enabled.

The local server starts new characters at level 0 in the original Tutorial Island house (map 192, 7,6), with no inventory, equipment, Gold or spells. Take the first outfit from the existing house chest and craft a Dagger at Cyndi’s using two Goat Horns. The original boat crossing requires level 4; it lands on mainland map 1, and entering Aeven through map 2 requires level 5. `configure_onboarding.py` applies this policy to a stopped, backed-up runtime and adds reward-free native journey/home tracking. Existing characters receive no item changes or relocation. The unchanged `etheos-starter-kit.patch` supports empty gender overrides with an empty fallback. Loopback reconnect delay remains disabled and up to 12 connections per IP are allowed. See [classic onboarding](../docs/CLASSIC_ONBOARDING.md).

## JSON-lines protocol

Profile 14 restores the classic Peasant foundation: a bare newborn has 10 HP,
10 TP, damage 0–1 and zero combat attributes, accuracy, evade and armour.
Peasant outgoing/incoming hit and damage calculations use the original formulas;
professional classes and pets retain the revamped formulas. The entry catalog
includes actual progression NPC stats, so existing Android clients receive the
updated encounter values on reconnect. See [profile 14](../docs/PEASANT_V14.md).

Send a flat JSON object followed by a newline. Every reply preserves its `id` and `op` and has either `ok: true, data: ...` or `ok: false, error: ...`. No request body, password, or raw authentication packet is logged. Each connection allows at most 16 requests per second, 16 scalar fields per request, 256 characters per string field, and a 64 KiB input buffer. The gateway caps simultaneous connections at 12.

Supported operations:

- `connect`: initialize and confirm a genuine EO v28 session. This does not log a player in.
- `register`: `username`, `password`. Create a real server account.
- `login`: `username`, `password`. Return `characters`, each with `id`, `name`, `level` and appearance fields.
- `create_character`: `name`; optional `gender` (1 male, 0 female), `hairstyle` (default 1), `haircolor` and `race` (default 0).
- `enter`: `character_id` from the **current login response**. Complete both Welcome stages and return a snapshot.
- `refresh`: request and return a fresh server snapshot.
- `stream`: enable unsolicited `event: "world"` updates after entering. Replies include `movement_seconds: 0.42`.
- `move`: `direction`, monotonically increasing `input_seq`, current `map_id`, predicted destination `x`, `y`, and optional `open_door`. Returns only a transport receipt; native Walk_Reply establishes acceptance and Refresh corrects rejected/mismatched steps. Up to four inputs may be outstanding. Native etheos enforces its 400 ms movement queue; the adapter does not sleep or refresh per step.
- `walk` (legacy v0.6 compatibility): `direction` (0 = y+1, 1 = x-1, 2 = y-1, 3 = x+1). Return a fresh server snapshot after the request. The adapter spaces requests by at least 0.43 seconds; etheos applies its own movement rules. Returned coordinates can differ from the requested destination when the server rejects a move.
- `strike`: `direction`. Nonblocking native attack for v0.8, without a Face/Refresh round trip; the client uses a 520 ms cadence and native etheos applies its 500 ms action queue.
- `spend_stat`: `stat_id` 1=STR, 2=INT, 3=WIS, 4=AGI, 5=CON, 6=CHA. Requires an available point; returns only native-confirmed totals.
- `attack` (legacy): optional `direction` using the same convention. Face and attack through real EO packets, respecting 0.9-second adapter recovery, then return server state and any confirmed damage/death events.
- `pickup`: `uid` of an actual visible ground item. Wait for the real Item_Get acknowledgement.
- `equip` / `unequip`: `item_id`; optional `subloc` (default 0 for paired slots). Wait for the real Paperdoll acknowledgement and request equipped item IDs again.
- `disconnect`: close the native session, allowing etheos to save progress.

EO character IDs are session-generated identifiers, not stable database primary keys. After reconnecting, obtain the character ID from the new login response. Account credentials and character name persist.

Snapshots contain `online`, `map_id`, `player`, `players`, `npcs`, `items`, and `events`. The `player` includes connection `id`, current `character_id`, name, map coordinates, facing, HP/TP, `max_hp`/`max_tp`, actual `inventory` entries `{id, amount}` and `equipment` mapping slot names to server item IDs. `players` includes the local player; filter by `player.id` when drawing peers. NPCs contain server `index`, catalog `id`, coordinates and direction. Items contain server `uid`, item `id`, coordinates and amount.

Events use a `kind` discriminator. `npc_damage` contains `player_id`, `npc_index`, `damage`, and `hp_percent`; `npc_killed` contains the NPC index, damage and an optional nonzero `drop` record. `pickup`, `equip`, and `unequip` are generated only from their corresponding server acknowledgements. Other packets are recorded only as family/action/length metadata. Native world packets establish entity presence and positions; full snapshots initialize or recover state.

The gateway drains unsolicited packets and answers sequence-update pings while idle. Version 0.7 opts into streaming. World messages contain `position_update`, `position_seq`, `correction`, `events`, optional updated `player`, and changed entities in `players_upsert`/`players_remove`, `npcs_upsert`/`npcs_remove`, `items_upsert`/`items_remove`. Collection keys are `player_id`, `index`, and `uid`, respectively. Unchanged entities are omitted. Entry, map travel and explicit RPC snapshots contain full collections. The WebSocket bridge forwards backend events independently of client requests.

The client immediately animates a predicted tile, discards only inputs confirmed by `position_seq`, and replays remaining directions on the authoritative coordinate. Metadata-only pushes cannot rewind it. A successful ACK matching the predicted tile leaves the animation untouched. Corrections clear queued pathfinding; map transitions snap to the confirmed destination. A ten-second refresh is allowed only while idle with no pending movement or held joystick; it never gates normal steps. The prediction window is four inputs, and movement confirmation times out after 15 seconds.

 The adapter implements Warp Request/Take/Accept/Agree, verifies downloaded EMF size and RID, and returns server-confirmed map transitions. The client loads matching imported geometry on demand. Walk accepts optional `open_door: true`; this sends a native Door_Open request for the adjacent destination before walking. Locked doors still require the real key. See `warp-validation-report.json` and `door-validation-report.json`.

## Integration evidence

`online-validation-report.json` records the real integration run without credentials:

- Account registration, bcrypt-backed login, character creation and full Welcome entry succeeded.
- Two native EO sessions independently observed movement from 40,40 to 41,40, with server Refresh replies establishing the mover's position.
- Two sessions through the actual JSON gateway independently observed another accepted move from 41,40 to 42,40.
- The server supplied starting inventory and acknowledged equip, unequip and re-equip operations.
- A real server Rat was pursued, damaged and killed. Its random drop was empty; NPC loot was not invented.
- A separate owned-item round trip exercised real Item_Drop, Item_Get and re-equipping with starter boots.
- After disconnection, a read-only SQLite query confirmed persisted position and equipped weapon.
- Malformed nonobject JSON and oversized string fields returned errors without killing the gateway.

Run the native integration harness against an already running server:

```sh
python3 server/test_online.py --state-dir /path/to/server-state --report /path/to/work/online-report.json
```

It creates only `dev`-prefixed accounts and characters and never resets the database. Optional `EO_TEST_USERNAME` and `EO_TEST_PASSWORD` reuse a supplied dev fixture. `--credentials-out /path/to/work/private-fixture.json` saves a generated fixture with owner-only permissions for device tests; keep that file outside deliverables and version control. Integration accounts and their progression remain in the local database. The harness's combat pursuit can vary with real NPC movement and drops.

## Reference archive assessment

The user-supplied `trunk 305 EODelta` archive is a historical EOSERV-derived server fork whose changelog identifies version 5.5. Its software license is zlib-style and credits the EOSERV team. It adds pets, rebirth, event/config systems, overlays/underlays, arena and PK features, and spike behavior. It contains only three map files (IDs 0–2), four PUB files and two quest files; it is not a complete replacement for the current 282-map foundation. Its preserved executables, private database/configuration and logs are not included in source deliverables or used as executable dependencies. Software permission does not establish publication rights for original game artwork or game data.

The modern pinned etheos remains the runtime. Legacy feature ideas can be evaluated later through small explicit ports with source attribution and current security review.

## Secure WebSocket transport

`bootstrap_ws.py` verifies the pinned websockets 17.2 pure-Python wheel before installing into isolated local state. Python 3.11+ is required.

```sh
python3 server/bootstrap_ws.py --target /path/to/server-state/python
python3 server/ws_gateway.py --deps-dir /path/to/server-state/python --port 8081
```

This bridges WebSocket text messages on `/ws` to the existing TCP gateway. `/healthz` checks gateway reachability. Bindings stay loopback; Caddy terminates trusted public TLS. The hosted endpoint is `wss://eo.kcpd.top/ws`; its bridge uses private port8180 because8081 already belongs to another application. See `deploy/README.md`. No TLS verification bypass is used.

Public WSS was tested with the actual Godot scene: login, character entry, rendered Aeven/map4 round trip, inventory/equipment and offline-save isolation.

## Gameplay configuration in v0.8

`configure_gameplay.py --runtime /path/to/runtime` sets a real default home at
Aeven (5,40,40), using its own `data/aster-vale-home.ini`, and sets bare
`DeathRecover = 50`. The pinned Character::DeathRespawn divides this setting by
100; the bundled `50%` converts to 0.5 and otherwise restores zero HP for a
low-level character. An unconfigured home otherwise falls back to map1 (0,0).
The corrected configuration is also generated by setup.py. Reload the world
service to apply it, preserving its database and PasswordSalt. The v0.8 hosted
upgrade made a private database/config backup before restarting.

Stats are decoded from Welcome, Paperdoll, StatSkill, Recover and NPC packets.
Welcome's STR/WIS/INT order differs from equipment's STR/INT/WIS order. Death
sets displayed HP to zero and suppresses input until the genuine warp completes;
`map_transition.reason: death_respawn` distinguishes this from walking through an
exit. NPC attack events show damage, misses and attacks; natural HP/TP recovery
is streamed too. Native view distance 11 is used to discard departed entities.
The client and adapter both block NPC occupancy. Rejected predicted steps halt
input until outstanding confirmations settle instead of extending an invalid
path. Item descriptions come from original EIF bonuses and requirements; the
server supplies equipped totals, current attributes and available points.

Held strikes are independent of earlier strike receipts, bounded by the same
four-request window. Idle recovery refreshes are suppressed while attacking.
Walking waits for attack recovery; held attack yields to joystick movement,
avoiding a native action backlog when switching between walking and combat.


### Bounded spike damage (v0.25)

The fourth native patch, `etheos-spikes.patch`, limits each timed/walked spike
hit to at most50HP and5% of maximum HP (minimum1HP for small characters).
SpikeDamage=0 still disables spikes; low remaining HP can still be lethal.
Self Effect_Spec31/16 subtype2 supplies real damage/currentHP/maxHP; the adapter
updates authoritative stats and streams the hit immediately. Effect_Admin31/17
supplies peer damage. The Android HUD and damage numbers consume these native
values; they do not locally subtract estimated health.


### Mobile combat and boss cleanup (v0.26)

`potion_use {item_id}` sends the original native Item_Use for health/mana
potions and immediately returns a transport receipt. It is nonblocking alongside
walks and spell chants. Native Item_Reply updates exact inventory and HP/TP;
`item_use_failed` releases the shortcut after rejection/timeout. Up to four potions may await acknowledgement, bounded by ownership and useful
projected gains; authoritative HP/counts remain unchanged until native replies. Other consumables retain `item_use` and standing
checks. Trade, death and map-transition guards remain in force.

The fifth native patch, `etheos-mobile-spells.patch`, adds AllowMovingSpells.
Our setup enables it; the patch defaults to false for upstream compatibility.
It preserves chants while walking and separates spell timing from the advancing
movement timestamp. Cast duration, native range/TP/target validation and attack/
warp cancellation remain authoritative. Rebuild the native server and restart
with AllowMovingSpells=yes when deploying the new moving-cast client behavior.

NPC_Junk26/25 removes all NPCs of its ENF type ID. This matches original boss
child cleanup: killing Apozen Overlord removes its Taraduda children. Streamed
removals clear sprites and collision; Range_Reply restores actual respawns.

Attack remains at the native500ms plus20ms dispatch cycle. The client now
renders the original480ms swing timeline and carries frame overshoot between
held attacks. Movement remains420ms and does not wait for previous strike RPC
receipts. Chat history and compact feed support finger dragging and preserve the
reader's scroll position while incoming messages arrive.


### Self Heal timing (v0.26.1)

Original Heal Self uses ESF cast_time1:480ms chant. The client now recovers
input after the original480ms local cast pose, measured from chant release.
A native confirmation clears the pending cast without adding a new600ms lock.
The adapter does not impose a second preparation cooldown. Native
SpellCastCooldown=600ms and SpellCooldownTime remain unchanged and enforce
about1.07seconds between repeated heal effects. Isolated first-heal timing was
about507ms including dispatch; public network delay is additional. HP/TP are
updated only from native replies. See docs/heal-v29-timing-report.json.


### Mobile potion priority and combat receipts (v0.27)

The sixth native patch, `etheos-mobile-feedback.patch`, adds MobileFastPotions
(defaultfalse; our setup/live configyes). Healing Item_Use can execute on the
world thread during a walk/attack wait without resetting that action's deadline.
Other item types stay in the normal queue. Native use still checks ownership,
trade and healing and returns actual HP/TP/counts. Zero-gain races now receive a
standard unchanged-count Item_Reply. The gateway pipelines at mostfour useful,
owned potions; a blocking item_use waits for their acknowledgements.

NPC::Damage always includes the caster in its result broadcast, even when a
moving caster left visibility during the chant. This prevents valid Small Thunder
hits from leaving TP/casting pending. Native skill timing/cooldown is unchanged.
Dead/departed targets cancel promptly, and actual effect events clear local
casting even if no separate casting:null delta was sent. Full-health Self Heal
is rejected without TP use; no large cast bar is shown.

Kill packets with private EXP appendages generate exp_gain from the authoritative
new total minus the previous total. Both melee and spell kills support it;
observers without that suffix do not gain EXP. Boss damage and rounded native HP
percentages are drawn above the visible head and above other scenery.

## Fairy Soda and Ice Blast area extension (v0.32)

Small/Big Fairysoda (210/211, native Beer22) consume one bottle through native
Item_Use/Reply. Only a confirmed quantity decrement starts the drunk timer.
Duration is the original `(100 + potency*10)/8` seconds:25s /137.5s. The adapter
sends native Emote9/Report21 value11 immediately and every4–6s, decodes peer
Emote9/Player8 and forwards it. The original drunk chat slurring, vowel-star and
`*hic*` rules apply to outgoing chat; command text and whisper targets are kept
intact. Text remains bounded to128 Latin-1 bytes. The temporary effect ends on
expiry or session disconnect; it does not heal HP/TP or alter character saves.

Both original Ice Blast definitions14/21 accept `spell_cast` with
`target_kind="area"`, no opponent ID. Preparation and the original480ms chant
remain native Spell12/Request1 and release12/TargetSelf30. The patched native
Character::SpellAct routes these damage spells into Map::SpellAreaAttack.
It chooses at most5 closest live combat NPCs in the centered5×5 square
(abs(dx)<=2 and abs(dy)<=2), ordered by squared distance then NPC index. Players
and noncombat service NPCs are excluded. Targets are chosen at release, so the
area follows the caster's current native tile. Damage, hit chance, training,
EXP, loot and quest kills still use normal native NPC::Damage/Map::SpellAttack.
TP is deducted once, including an empty cast. No PUB damage or TP costs change.

Native extension family231/action3 confirms casterPID2/spellID2/x1/y1/TP2/hits1
(9bytes). It broadcasts area visuals and ends empty casts. Only the caster
adopts its TP. Original family44 per-target damage/death packets remain intact.
The client shows the5×5 frost pulse and original hit effects on each target.

### Character shortcut preferences (v0.35.2)

`enter` includes `shortcuts` with saved `items` and `skills` arrays (two IDs per
group). An absent group has never been saved; `[0, 0]` is an explicitly empty
group. `shortcuts_set` takes `kind`, `first`, `second` and returns the acknowledged
`kind` and `slots`. Account and character scope come from native authentication
and entry. No client-supplied identity is used. Saves persist in the dedicated
`ASTER_VALE_SHORTCUT_DB` SQLite file, separate from native character data.
See [shortcut migration, validation and deployment](../docs/SHORTCUTS.md).

### Native party, group spells and Bard (v0.36.0)

`party_invite` / `party_join` take a nearby `player_id`; `party_accept` /
`party_decline` respond to the current native invitation. `party_leave`,
`party_kick` (`player_id`) and `party_refresh` use native membership permissions.
Snapshots/deltas expose `party`, `party_invitation`, `party_notice`; membership
changes only on native packets. `chat_send` accepts `channel="party"` for native
party chat. `spell_cast` supports `target_kind="group"` for learned group heals
and the normal `target_kind="player"` for friendly heals, including your own
player ID. `bard_note` takes a note integer 0–35 and requires learned Bard plus
an equipped native instrument. See [behavior and validation](../docs/PARTY_HEAL_BARD.md).
