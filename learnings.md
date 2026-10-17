# Endless Online Android: session handoff

This file is the starting point for the next session. Read current Git status,
recent commits and the relevant code before editing; runtime state can change
after this document was written. Keep this file current when behavior or
deployment changes materially.

## Goal and current product

The user is building their **own game and server**, inspired by classic Endless
Online, with original-style maps, movement, equipment, inventory, combat and
shops adapted for Android. This is not a client for somebody else's public EO
server. The project is called **Endless Online Android** on GitHub; the app's
current working title/package are **Aster Vale** / `io.astervale.prototype`.
Godot 4.7.2, typed GDScript and 2D isometric rendering are sufficient. A Unity/3D
rewrite and a larger server have not been needed for the measured regressions.

Baseline before this update: commit `8c9e541`, APK 0.10.0/code 10. The current
build is 0.22.0/code 24. See the final v0.21 section for current chat/presence and the v0.20 sections for equipment/HUD/Junk support. v0.12 added level/EXP, Nearby Send closure and
native consumables; v0.13 adds native skills and touch targeting. v0.11 added native bank/lockers, player inspection and
trading, local/global/private chat, a dynamic joystick, and the heart/TP HUD,
as well as placing NPC names near visible heads and fixing observer equipment/
attack animation updates. Check `git log` and the version in
`scripts/build.py` for the actual latest release. Earlier important commits are
`0bf3458` (original shops/loot/stats) and `bf18ba5` (combat/stats/respawn).

## Paths, repository and delivery

- Canonical checkout: `/home/kc/workspace/Endless online` — quote the space.
- Remote: `git@github.com:kcpdme/Endless-Online-Android.git`, branch `main`.
- Original task folder: `/home/kc/Documents/Codex/2026-10-16/cr`.
- Its `outputs/aster-vale` and `work` links lead into the canonical checkout.
- User download files go in `/home/kc/Documents/Codex/2026-10-16/cr/outputs`.
- Exported APK in the repo: `builds/aster-vale-debug.apk` (ignored).
- Download naming: `endless-online-android-vVERSION.apk`, matching source ZIP
  and SHA256SUMS text. Source ZIP uses `git archive` and excludes private assets.
- Use public commit email `239019296+kcpdme@users.noreply.github.com` when
  committing. Fetch/check divergence before pushing; do not force-push.

`reference/`, `work/`, generated `client/content/`, builds, databases, signing
keys, downloaded archives and private device/test files are ignored. Do not
stage them. Original EO content has unresolved redistribution rights; source
availability does not establish rights to publish the original artwork/maps.
The user already has the development resources locally.

## Resource and toolchain inventory

- `reference/gfx.zip` and `reference/trunk-305-EODelta.zip`, with provenance
  `.metadata.json` files; extracted supplied material is under `reference/extracted`.
- Original Windows client/reference archives and downloaded development sources
  are also retained in ignored `reference/` / `work/`; inspect rather than
  redownload them. Do not execute old supplied binaries.
- `work/EndlessClient`: Ethan Moffat's open-source reference client, pinned
  around `d4764cb8b1bad6501c33f38a596d80d3d79c47bb`.
- `work/server-build/source`: pinned etheos source
  `d6b6395d5ae28e1b20cd72f33fbf23ba921e7919`, with our maintained password patch.
- `work/server-build/{build,deps,runtime,python}`: native build, dependencies,
  local runtime/SQLite/private config, and pinned WebSocket Python dependencies.
- Godot executable:
  `work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64`.
- Android SDK: `/home/kc/Android/Sdk`; use its `platform-tools/adb`, not an older
  PATH adb which can restart the daemon and disconnect wireless devices.
- Build tools: `/home/kc/Android/Sdk/build-tools/36.0.0`.
- CMake available under `/home/kc/Android/Sdk/cmake/3.22.1/bin/cmake`.
- Toolchain/export templates/debug keystore are under `work/toolchain`.
  Keep the existing signing key so installing an update preserves app data.

## Architecture and authority

Android Godot client → trusted TLS WebSocket → Cloudflare/Caddy → Python
WebSocket bridge → independent Python EO session adapter → real C++ etheos
world → persistent SQLite. This is a genuine EO v28 integration, not a mocked
world. Each connected client owns its own encrypted native EO connection.

- `client/scripts/main.gd`: world, local character, controls, bag and common UI.
- `online_controller.gd`: login, native-backed state, prediction/reconciliation,
  peer rendering, interaction, equipment and inventory UI.
- `online_session.gd`: JSON TCP or WS/WSS transport; normal TLS verification.
- `server/eo_session.py`: native packet framing/codec, login/Welcome, inventory.
- `live_session.py`: asynchronous movement/attacks/collection and compact deltas.
- `eo_stats.py`: exact native stats/combat parsing; `economy.py`: native shops.
- `services.py`: original Bank, Locker, Paperdoll, Trade and Talk flows.
- `consumables.py`: native Item_Use and acknowledged quantities, healing, scroll
  warp completion, EXP rewards and curse removal.
- `services_window.gd`: storage/trade/inspection UI and separate read-only
  original paperdoll. `chat_window.gd`: channels, whispers and bounded log.
- `vitals_hud.gd`: five fractional HP hearts and five TP orbs.
- `gateway.py`: JSON operations, session lifetime and native event pumping.
- `auth_sessions.py`: in-memory, single-use previous-session proofs.
- `ws_gateway.py`: full-duplex WebSocket/TCP bridge, bounded buffers/clients.

The server owns movement acceptance, combat, HP, Gold, inventory, quantities,
equipment, drops and map transitions. Item catalogs describe requirements and
art; they do not grant ownership. Never invent successful pickups or equipment
changes before a native acknowledgement. Offline progress is a separate device
save and must never receive online state or credentials.

## Hosting and operational commands

Public endpoint: `wss://eo.kcpd.top/ws`; health: `https://eo.kcpd.top/healthz`.
The existing AWS host uses Caddy and proxied Cloudflare DNS; Caddy routes only
`/ws` and `/healthz` to the bridge. Do not expose native EO or JSON ports.

SSH alias: `AwsHosting`, user `admin`. The alias's old default key was missing;
the working local key is `/home/kc/workspace/VPSKeys/kcpdnew.pem`. Use:

```sh
ssh -o BatchMode=yes -o IdentitiesOnly=yes \
  -i /home/kc/workspace/VPSKeys/kcpdnew.pem AwsHosting
```

The dedicated service user/group is `astervale`.

- `/opt/aster-vale/runtime`: world binary, game data, `database.sdb`, and private
  `config.local.ini` / persistent PasswordSalt.
- `/opt/aster-vale/app/server`: adapter source.
- `/opt/aster-vale/python`: verified WebSocket dependency, currently 17.2.
- `/opt/aster-vale/backups`: private deployment/database backups.
- `aster-vale-world`: `127.0.0.1:8078`.
- `aster-vale-gateway`: `127.0.0.1:8079`.
- `aster-vale-websocket`: `127.0.0.1:8180`.

```sh
sudo systemctl is-active aster-vale-world aster-vale-gateway aster-vale-websocket
sudo journalctl -u aster-vale-world -n 40
curl -fsS http://127.0.0.1:8180/healthz
```

Back up reviewed adapter files before replacing them. Restart gateway and
WebSocket for adapter updates; this briefly disconnects players but preserves
their native progress. An adapter update does **not** need a world restart.
Back up SQLite with its backup API or stop the world before copying it. Never
replace the hosted database/config with a local test fixture or regenerate its
salt. A native binary change needs a controlled world stop/restart and private
backup. Preserve current ownership and systemd hardening. Host measurements
were lightly loaded; extra CPU/RAM would not fix serialized protocol waits.

Local tests typically use world 8078, gateway **8182**, WebSocket **8183**.
Check listeners/processes first and reuse suitable existing services; do not
assume old PID numbers still identify the same process. Example commands:

```sh
python3 server/run.py
python3 server/gateway.py --port 8182
python3 server/ws_gateway.py --port 8183 --tcp-port 8182 --deps-dir work/server-build/python
```

## Important regressions and their fixes

### Movement and attack cadence

The original-style protocol does **not** refresh the full world every step.
Old adapter/client versions waited for sleeps, Refresh and round trips before
animation. See `docs/MOVEMENT.md` for the original-code comparison and measured
before/after behavior. Reference EndlessClient is open source; do not describe
it as decompilation of the proprietary Windows executable.

Current movement starts locally, uses a 400 ms tile animation and roughly
420 ms input cadence, and allows four bounded predictions. Native Walk_Reply
confirms inputs; only acknowledged inputs are discarded. Replay the outstanding
directions when reconciling. NPCs/peers interpolate independently. There is no
periodic full-world Refresh timer. Real rejection/death/warp still corrects.

Releasing online movement clears future input and finishes the already-committed
tile; freezing halfway caused later snaps. Offline release still stops directly.
True correction/disconnect/death uses `_cancel_controls(true)`.

Original client NPC collision remains local. Native etheos player Walk checks
terrain and player occupancy. A second adapter NPC check used a newer moving-rat
position to reject a step already predicted by the client; it was removed.
Do not reintroduce this race. Static NPC tiles still block client movement.

An attack after the visual walk completes does not wait for an additional Walk
ACK. Reliable native action order preserves Walk→Attack. Attacks repeat around
520 ms, matching the native 500 ms cooldown, rather than the offline 900 ms rate.

Native Attack uses direction + timestamp. Differences below 48 ticks are refused;
differences at least 60 force the previous native facing. The adapter advances
50 ticks per streamed attack, 42 per walk. Start the session counter at **0**,
not the former arbitrary 1000: otherwise the very first attack after login can
face the wrong way. Native Timestamp begins unset. Do not add a Face wait to
every swing to mask this; it adds a native queue slot.

### Inventory, drops and shops

Gold item **1** always occupies the first bag slot, including amount zero.
Stored quantities appear in the top-right corner. Original Gold icon is GFX23:70;
original ground coin piles are 269/271/273/275/277 at amounts 0/2/100/10000/100000.
Do not replace these with a diamond glyph or fabricated currency artwork.

Rat Tail is item **249**. A named Pick up control works within native Manhattan
distance two. Walking onto a drop also collects. Pickup intent survives movement
and its ACK. `collect` returns immediately; native Item_Get updates inventory
and emits success. A failed protected/overweight pickup expires as a feedback
event instead of blocking the native packet pump. Native NPC drop protection is
30 seconds; player drops have a separate protection interval (five seconds in
the test runtime). Other players' reserved drops stay unavailable.

Packet layout pitfalls: Item_Add is item2/uid2/amount3/x1/y1; Walk_Reply ground
items are uid2/item2/x1/y1/amount3. Item_Get uses the native UID, not item ID.
Partial pickup subtracts only the acknowledged amount.

Original per-NPC economy was imported: 48 trade/craft records and 152 NPC drop
entries. Shop Bob Buy/Sell and Cyndi Craft pass native and scene tests. Prices,
ingredients and random drop chances remain original. Shop operations require
opening the nearby keeper and invalidate on movement/warp. Bank/locker,
inspection/trade and chat are implemented in v0.11. Guild/quest and other NPC
services remain unfinished; do not claim every NPC works.

### Equipment and multiplayer appearance

Original native Equip silently refuses an occupied slot. The client implements
a one-tap replacement as **Remove → native ACK → Add**. It checks level, class,
gender, attributes, cursed gear and obvious two-handed conflicts first. Old gear
returns to the bag, with exact native quantities. Do not send both packets before
Remove is acknowledged or invent an atomic inventory result. Error text now
explains native refusal instead of only saying acknowledgement timed out.

Snapshot appearance order is **B000A0HSW**: boots index0, armor4, hat6, shield7,
weapon8. Character-selection order is BAHSW. Avatar_Agree (family23/action5,
slot1) instead has **BAHWS**, five two-byte graphics after player2/slot1/sound1.
Decode into indices **0,4,6,8,7**. Ignoring this packet left observers displaying
the weapon a player wore when they entered view, rather than the current gear.

Peer attacks are family11/action8: player2/direction1. Forward the event, update
the peer's persistent facing, and start a 360 ms two-frame weapon animation.
Render from the attack's direction, not a stale walking direction. The current
client uses `peer_attacks` and the shared `entity_animation()` render path.
No full-world refresh is necessary for either equipment or attack animation.

Current composed player art covers male gender1/race0/hair1/color0, starter
armor/boots graphics 0/1 and these weapons: Dagger21 (doll4), Broadsword19 (14),
Ancient Sword22 (19), Battle Axe32 (18), Dragon Blade37 (3), Dark Katana38 (12),
Ultima Blade281 (33). Eight starter variants remain under `hero_variants`;
24 additional combinations are under `weapon_variants`, keyed `aA_bB_gGRAPHIC`.
Long weapons use 192×192 transparent canvases so their art is not clipped.
Unsupported appearances still show an explicit fallback; they need more layer
composition rather than substituting a random item sprite.

### NPC names, health and character stats

NPC export includes per-frame `visible_bounds`, computed from original opaque
pixels after mirroring. The client positions names over the visible standing
head using region dimensions and the original frame offset. It centers the text
by measured width; it does not add the old fixed `-32-name_label_offset` gap.
Idle labels sit five pixels above the art. While fighting, a five-pixel HP strip
fits between head and name. Standing geometry keeps labels stable during swings.

Battle strips use native remaining HP percentage, appear on engagement/damage,
expire after eight seconds without combat, and clear on death/map change.
Character HP/TP, damage flash, native retaliation/death and Aeven respawn work.
The original Stats panel is GFX2:34. INT/WIS field order differs between Welcome
and equipment packets; preserve their explicit decoder orders. Item details show
native bonuses, requirements, weight and quantity.

### Mobile controls and login

The translucent floating stick has radius110 and a 364×322 activation area.
Its pointer stays captured outside the circle, and another non-HUD touch cannot
accidentally pathfind the map. Attack, bag, person and nearby Pick up remain
usable with a second finger. Native touch ownership suppresses duplicate
emulated mouse actions. Android Back closes the top modal first.

Login code **5** is already logged in, often a dead Wi-Fi session while moving
to mobile data, not evidence of broken mobile TLS/firewalls. The gateway issues
a random in-memory, account-bound single-use reconnect proof; valid proof can
retire only that same prior session. New native login still verifies the password.
Tokens/passwords are not saved on the device. WS ping interval/timeout are 5/8
seconds, and code5 retries are bounded. Carrier networking still adds real latency;
do not claim controlled injected delay represents every mobile network.

## Password hashing recovery: do not regress

Earlier setup used a 64-character persistent PasswordSalt. Native version2
prepended salt + account name + password before bcrypt, which consumes only
72 input bytes. Some account names therefore caused the entire password to be
ignored. A negative login test reproduced this. It was **our setup interacting
with the legacy hash scheme**, not proof that mobile internet rejects passwords.

Maintained patch: `server/patches/etheos-password-v3.patch`. Setup applies it to
the pinned native source. Version3 hashes the full salted input to 64 printable
SHA-256 hex characters before bcrypt with random per-hash salt/work factor12.
Hosted/local secure config: `PasswordCurrentVersion = 3`,
`RejectLegacyBcrypt = yes`. Preserve the original private runtime salt.

Legacy vulnerable hashes require operator recovery (code7). Do **not** migrate
them based on a supposedly successful old login, enable legacy verification to
avoid a reset, or run an unpatched binary against a version3 database.
`server/reset_password.py` prompts privately or generates a mode-0600 file,
backs up SQLite and verifies character rows did not change. It uses the native
`runtime/native-auth` helper; `native-auth --self-test` checks truncation/rejection.
The operator helper requires 8–25 printable ASCII characters; native ordinary
registration has its separately configured password limits. Do not weaken the
hash scheme for an explicitly requested short test password.

Never put user passwords, reconnect tokens, DB hashes, salts, Cloudflare tokens
or SSH/signing key contents in this public file or repository. Private operator
profile notes live in ignored `work/session-handoff-private.json`. Previously
generated private login files are in the task outputs directory with mode0600.
Look up those files privately instead of printing them or resetting accounts
again. Manually funded real/test profiles must not be reused as integration
fixtures or overwritten by a local database.

## Bank, lockers, player interaction and chat (v0.11)

Use the original pinned reference, rather than inventing a parallel economy:
`EndlessClient/Dialogs/{BankAccountDialog,LockerDialog,TradeDialog}.cs`,
`EOLib/Domain/Interact/Bank/BankActions.cs`, `Domain/Map/LockerActions.cs`,
`Domain/Trade/TradeActions.cs`, `Domain/Chat/ChatActions.cs`, and matching native
`handlers/{Bank,Locker,Paperdoll,Trade,Talk,Global}.cpp`. UI is adapted for touch;
the original male paperdoll background/slot regions and item art are reused.

`services.py` initializes per-connection bank/locker/trade/request state. Its
snapshots and compact world deltas explicitly include these keys, including
`null` to close a window. All inventory changes follow native acknowledgements.
Bank/locker contexts clear on movement or warp. Storage, equipment, shops and
pickups are blocked during a trade, including the native Bank_Take path that
lacks its own trading guard. Moving/attacking during a trade is rejected until
Cancel, so walking cannot leave the adapter with a stale active trade.

- Bank NPC type9: Open36/13 NPC index2; response bankGold4/token3/upgrades1.
  Deposit36/7 and withdraw36/9 use amount4 plus token3. Reply36/3 carries exact
  bagGold4/bankGold4. Locker expansion37/11 returns bagGold4/upgrades1.
  Capacity/cost use read-only native config settings (25 base slots, +5 per
  upgrade, 1000 base Gold/+1000 step in the supplied runtime), not DB grants.
- Lockers are map tile spec16. Tap their actual tall object or their tile;
  approach within one Manhattan tile. Open37/13 x1/y1; full contents are
  item2/amount3 pairs. Deposit37/7 x1/y1/item2/amount3; reply37/3 includes exact
  remaining bag amount4 and native weight/maxweight. Withdraw37/9 x1/y1/item2
  takes the whole stack (limited by CanHoldItem), acknowledged37/27 amount3.
  Gold is banked through the NPC rather than stored as a locker item.
- Inspect another visible player via Paperdoll30/1 PID2. Reply30/3 has six
  break strings, PID2/class1/gender1/unknown1 and 15 equipped itemIDs2.
  Parse into a separate inspection record. Never call the self-only paperdoll
  parser or overwrite your own equipment when inspecting another player.
- Trade32/1 sends byte0 + PID2; incoming includes raw trailing requester name.
  Accept32/2 byte1 + requesterPID2. Open32/13 starts both dialogs. Add32/7
  item2/amount4; remove32/4 item2. Offer updates32/3 or32/17 contain ownerPID2,
  item2/amount4 pairs and byte255 delimiters for both players. Any offer change
  resets both approvals. Agree32/5 uses one byte. Own status is32/16; peer
  status32/5 contains the receiver's PID in this pinned server, so treat it as
  peer agreement instead of attributing it by the misleading ID.
- Only completion32/10 transfers local inventory quantities; decode by group
  PID, not group order. Weights use native read-only EIF definitions, as the
  reference client does. Cancel32/14 and peer disconnect close the trade without
  transferring items. Tests verify completion and persistence after reconnect.
  Native requires both players to offer something before the second approval
  completes. This adapter limits each offer to five distinct item types because
  the pinned world's Trade_Remove wrongly refuses removal above five; quantities
  remain stackable. Lore items are refused. No Python database trading exists.
- Native Talk18 sends Nearby action21, Global15, Whisper20 (recipient break
  string followed by message). Incoming Nearby8 has PID2 + raw message; Global15
  and Whisper20 have two break strings. Server23 is raw text, Reply3 is a missing
  recipient, Spec16 means muted. Sender echo is local, matching EndlessClient;
  it is not proof of delivery when native mute/jail rules drop a message.
  Log is bounded to150 messages in RAM, cleared on character entry, never saved
  with credentials or an offline profile. Native protocol text is Latin-1;
  unsupported Unicode gets a clear error. Input is 1–128 printable characters,
  rate limited to one message per0.7 seconds. Nearby messages also show a short
  speech bubble; new incoming messages mark the opaque chat icon with a dot.

Client dialogs use actual native state. The bank is a compact wooden card;
locker and trade screens show bag items and stored/offered quantities; inspecting
shows the original paperdoll and item bonuses without modifying your gear.
A tap on another player's rendered body requests inspection once your current
step is confirmed. Trade and Whisper actions are on that player's dialog.

The gameplay HUD hides the title, player/location coordinates, map name, nearby
player/NPC counts and Gold. Gold remains visible as item1 in the bag and in bank,
shop, trade and Stats dialogs. `CharacterStats.vitals` is a custom Control with
five fractional red hearts and five blue TP orbs; HP/TP numeric totals are in
Stats. An idle joystick is invisible. Touch down anywhere in the larger lower
left activation area centers it exactly at the thumb, and long drags slide the
base while retaining pointer ownership. Release clears input and hides the
stick; online movement still finishes its committed tile (never stop a rendered
sprite between native tiles). Multi-touch attack and modal/focus cancellation
remain covered by gameplay tests.

Test details and pitfalls:
- `server/test_services.py`: fresh two-client WS→EO native bank/upgrade/locker,
  inspect, all three chat channels, trade reset/complete/cancel and relog.
  Passed locally and through public WSS on the deployed adapter.
- `server/test_services_ui.py`: actual Godot scene and two real native sessions;
  taps the bank/locker/player, exercises dialogs, checks exact inventory, local
  speech bubbles and whispers. `--screenshots work/v11-screens` uses desktop
  rendering for visual QA; private screenshots include only dev fixtures.
- Moving banker NPCs can wander away from their initial map spawn. Integration
  fixtures must approach the banker's live coordinates rather than assuming
  the NPC remains beside a fixture staged at2,2. Do not restart production or
  alter NPC data to make a test pass. Local world restarts for isolated QA reset
  local NPC positions without deleting the DB; they do not affect production.
- Locker targeting once reused NPC index0 and replaced its selected coordinates.
  A locker interaction must skip NPC lookup and retain its own x/y.
- Center-anchored dialogs must change `offset_top/bottom`, not set `position`
  to a negative half-size after anchoring: that moves them off screen. UI tests
  and screenshot inspection cover bank/trade bounds.

## Content status and known gaps

There are 282 imported server maps, 3,945 original warp records, 490 items,
302 NPC definitions and 158 world NPC graphic sets. Valid map changes follow
the native warp handshake before swapping rendered geometry. Eight malformed
map47 destinations are guarded. Map relog coordinates are not guaranteed safe
spawn locations. Source graphic171 has blank standing art; do not silently
replace its species with invented artwork.

The sample quest archive contains 36 numeric sources; 35 parse after conservative
logged `.eqf` conversion. Quest17 is isolated because of a missing target state;
native output 35/56 includes permitted numeric ID gaps. Original text bytes and
conversion provenance are preserved. Some chest/map data remain inconsistent.
Quest gameplay, guild/party controls, spells, self-service recovery, more appearance
combinations, abuse monitoring and real capacity testing are future work.

## Build, verify and install

```sh
python3 scripts/build.py android --toolchain work/toolchain
/home/kc/Android/Sdk/build-tools/36.0.0/apksigner verify builds/aster-vale-debug.apk
/home/kc/Android/Sdk/build-tools/36.0.0/zipalign -c -P 16 4 builds/aster-vale-debug.apk
```

The build imports resources, checks Godot script errors (Godot can exit0 despite
script errors), then exports/signs with the existing key. API24+, ARM64/x86_64,
immersive full-screen; wide screens show extra world instead of letterboxing.
`export/android/shutdown_adb_on_exit = false` avoids killing wireless ADB.

Physical device is Galaxy S23 Ultra/SM_S918B, Android16. Wireless port changes:

```sh
/home/kc/Android/Sdk/platform-tools/adb mdns services
/home/kc/Android/Sdk/platform-tools/adb connect IP:PORT
```

Before `adb install --no-incremental -r`, force-stop and privately read the
existing `files/aster_vale_save.json` through `adb exec-out run-as
io.astervale.prototype`. Compare the raw bytes after installing. **Never
uninstall to fix an install error**; that would delete the offline save. Do not
print the save. Ignored `work/install_v10.py` demonstrates the successful check;
adapt version/device port rather than assuming it is current. Launch component:
`io.astervale.prototype/com.godot.game.GodotAppLauncher`.

Tests use temporary XDG data/config roots and fresh `dev...` accounts. Native
character selection IDs are session-specific: **after relogin find the character
by name in that login's returned list**. Reusing a fixture's previous ID causes
a silent Welcome refusal/acknowledgement timeout. Never stage a human character
for a test. Keep fixture JSON mode0600 and outside committed source.

```sh
python3 -m unittest discover -s tools -v
python3 -m unittest discover -s server -p test_live_state.py -v
python3 scripts/test_client.py --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64
python3 scripts/test_client.py --world --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client --script res://tests/movement.gd
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client --script res://tests/network_regressions.gd
python3 server/test_reconnect.py --deps-dir work/server-build/python
python3 server/test_weapons.py --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64
python3 server/test_peer_visuals.py --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --report work/peer-visuals.json
```

Peer visual integration uses two independent real native sessions, changes
weapons after the observer has already entered, checks native equip/removal
updates and both rendered attack frames in four directions without observer
Refresh. `--fixture-file` and `--url` allow the same test through public WSS,
using freshly provisioned dev fixtures on the hosted world.

Other meaningful integrations: `test_streaming.py` (ACK/peer pushes/warps/jitter),
`test_combat.py` (real outgoing/incoming damage, stats and native respawn),
`test_economy.py` (Bob/Cyndi, quantities, protection/persistence),
`test_kill_loot.py` (actual random Rat Tail drop), and `test_mobile_flow.py`
(real scene native touch/pickup/bag under injected delay). Run appropriate tests
for the change; do not repeatedly rerun unrelated lengthy suites after passing.

`latency_proxy.py` is loopback-only and pipelines delay rather than serially
sleeping each RPC. Controlled tests at 120±80 ms per direction completed eight
touch steps/pickup with no correction/Refresh; 300±150 ms tests chased/killed a
real Rat while attacking before Walk ACK. Do not run movement fixtures on the
same coordinates simultaneously: genuine player collision can fail an otherwise
valid isolated test. Stop temporary proxies/emulators after finishing; keep the
hosted world running.

Sanitized results are in `docs/*report.json` and `docs/TESTING.md`. Raw logs,
credentials, phone screenshots and save hashes remain private/ignored. Add
meaningful regressions for protocol bugs instead of tests which merely restate
implementation. Verify an observer's actual render state, not only an attacker
RPC saying it was sent.

## Reference explanations

- `docs/MOVEMENT.md` and `server/ONLINE.md`: original-source and packet details.
- [Client prediction and reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html).
- [Entity interpolation](https://www.gabrielgambetta.com/entity-interpolation.html).
- [Snapshot interpolation](https://gafferongames.com/post/snapshot_interpolation/).
- [Password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
- `tools/README.md`, `docs/REFERENCE_IMPORT.md`, `THIRD_PARTY.md`: content
  provenance, import commands and license boundaries.

The user prefers autonomous implementation, testing and installation, with
concise progress updates and concrete results. Existing authorization covers
these requested fixes, deploying them and reinstalling the update. Ask only
for genuinely missing information; do not repeatedly reconfirm reversible work.


## v0.11 final delivery notes

The native adapter changes are deployed to the existing AWS/Cloudflare/Caddy
endpoint. All three hosted services remain active. Deployment backs up adapter
source and restarts only gateway/WebSocket services; the production native world,
existing account database and password salt are preserved. Fresh dev fixtures
are the only test DB staging. Public WSS tests pass bank/locker/inspection/trade,
all three chat channels and persistence; the actual Godot observer sees eight
weapon swings across two weapons/four directions. Sixteen Python state tests,
24 content tests and the Godot gameplay/movement/network regressions pass.
Actual Godot service dialogs and rendered screenshots were also checked.

Install using the existing signing key and `adb install --no-incremental -r`.
The Galaxy S23 Ultra wireless link was paired and installation succeeded with
identical save bytes. A stalled first transfer (~0.5 Mbps) recovered after
restarting the SDK adb daemon; the same APK then transferred at roughly90 Mbps.
Use the discovered mDNS serial rather than accumulating duplicate manual IP
transports. Current identity is `adb-RZCW40X8YZZ-lFn1cg._adb-tls-connect._tcp`;
its IP/port can change. Never uninstall to solve a transfer issue. Private
install logs/save backup/hash evidence are under ignored `work/v11-phone-*`.
The final APK must match the SHA256 in the final install report, not a prior
intermediate v0.11 export. Source ZIP is made from the final committed HEAD.


## v0.12: level/EXP HUD, Nearby Send and consumables

Current version is 0.12.0/code12. The vitals HUD now has a five-pixel gold EXP bar
below HP/TP, with the native level and an integer progress percentage underneath.
EXP is cumulative: level n starts at round(n^3*133.1), so progress is
(exp - current threshold)/(next threshold - current threshold), clamped0..1.
Level0 starts at0; the currently configured native level cap250 shows MAX.
Operator-granted levels with EXP below their threshold show0%, never a negative
bar. `CharacterStats.refresh` supplies server level/EXP to `VitalsHUD` on every
accepted player update, including kills and EXP items.

Nearby chat closes and releases keyboard focus as soon as a Send request is
queued successfully. Global/private chat remain open. The normal native sender
echo still adds the message to the log and creates the nearby speech bubble.

Inventory action now says Use for native consumable item types and Equip for
gear. Use requests `item_use` with an owned itemID. Native `Item_Use` is14/10,
itemID2. `Item_Reply`14/3 begins type1/itemID2/remaining4/weight1/maxweight1,
followed by type-specific data. Only that acknowledgement changes quantities.
Supported native types are Heal3, Teleport4, EXPReward6, Beer22, EffectPotion23,
HairDye24 and CureCurse25. Spell/stat/skill item types have no Item_Use case in
this pinned world and do not get a false Use action. No DB grants or client-only
healing are involved.

- Heal reply adds hpGain4/hp2/tp2; update actual HP/TP, bag quantity, weight,
  vitals and feedback. A pure health/mana potion at its relevant full stat is
  refused before sending or consuming anything. The Use button re-enables after
  a refusal. Drinking keeps the bag open.
- Scrolls follow the native Warp handshake through map download/accept and final
  Warp_Agree before returning a usable snapshot. The client closes the bag for
  a scroll and loads the rendered map only from confirmed native transition.
  Native EMF offset0x2a is the scroll-permission flag; reject forbidden maps.
  A direct destination already occupied by the character is refused without
  consuming the scroll. Recall uses the server's home/spawn rules, not hardcoded
  coordinates. Original source: native handlers/Item.cpp and reference
  EOLib/Domain/Item/ItemActions.cs, PacketHandlers/Items/ItemReplyHandler.cs.
- EXP rewards update native totals, optional new level, points and maxima;
  levelUp0 means retain the existing level, not reset to0.
- Cure follows native STR/INT/WIS order, removes only cursed equipment, updates
  maxima/derived stats and obtains the original paperdoll afterwards. Cursed
  gear is destroyed by the pinned native handler; it does not return to the bag.
- Hair/effect/beer acknowledgements are decoded. The full original cosmetic
  animation/drunk behavior and additional hair artwork remain future renderer
  work; avoid claiming complete visual parity for every cosmetic item.

`services.item_definitions` now also reads the native EIF type, HP/TP and the
union at offsets32..36 (scroll map/x/y, effect or hair color). Keep native
metadata lookup separate from item ownership and never trust a client catalog
as authority for granting consumables. Storage/trade guards also cover use.

Validation:21 server state regressions pass (including exact potion reply,
full-stat refusal, native EXP levelUp0, trade lock and cure/stat ordering).
Godot gameplay and network regressions pass. `test_consumables.py` runs the
actual Godot scene and bag buttons with a fresh dev fixture, both locally and
through public WSS: HP/mana quantities and vitals, full-health refusal, Beach
scroll to map13 at12,19, same-destination refusal, Recall home, Nearby dialog
closure/speech bubble, and correct level2/EXP progress all pass. Rendered HUD,
bag Use button and Beach destination screenshots were reviewed. Reports are
`docs/consumables-v12-{local,public}-report.json`; private fixtures stay ignored.
Deployment adds `consumables.py` and updates services/live_session/gateway, with
adapter backups and gateway/WebSocket restarts only. The native world, existing
players and password salt are preserved.

The v0.12 APK was installed and launched on Galaxy S23 Ultra, with identical
offline save bytes, verified version12/0.12.0, valid signature/16KB alignment
and no startup script/crash errors. Private evidence is in work/v12-phone-*.


## v0.13: native skills, shortcuts and original effects

Current version is 0.13.0/code13. `server/skills.py` adds original ESF parsing,
nonblocking chant/release scheduling, skill-master dialogs, learn/forget and
skill-point training. `client/scripts/skills_controller.gd` owns three circular
shortcuts, an opaque book button, a wooden skill list/master screen, TP costs,
target selection, a chant bar and original effects. The native server owns
learned skills, TP, HP, damage, EXP, loot and learning costs. No client grant or
fake hit is used. Tap an attack shortcut then a living NPC; Heal Self casts
immediately. Normal friendly healing supports selecting another player or self.
Movement cancels an unreleased cast. Weapon attacks clear selection. Skills
cannot be cast during trade, death, warps or outstanding movement.

Original protocol: Spell12/1 prepares spellID2 + timestamp3; chant lasts
cast_time*0.48seconds. Native callback is0.47*cast_time plus remaining native
cooldown. Self release12/30 is targetType1/spellID2/timestamp3. Other release
12/31 is targetType1/unknown1/unknown2/spellID2/victimID2/timestamp3. TargetType2
means NPC,1 means player. Timestamp advances48*cast_time ticks; native accepted
window is (cast_time-1)*47+35 through max(cast_time,1)*50. `poll_spells` releases
without sleeping or requesting Refresh; entity movement/damage keeps streaming.
Recovery is600ms. Invalid targetType0 invokes native CancelSpell safely.

NPC Cast44/3 prefixes normal damage with spellID2 and appends casterTP2. Spell
kills44/16 and levelups44/2 also have prefix2/TP2, before recipient EXP4 and
optional level/points/maxima11. Kill playerID identifies the loot winner, not
necessarily the caster; do not blindly apply that TP to an observer. Matching
own released casts identify own kill TP; another player killing the same NPC
during our still-unreleased chant must not replace our TP. Self heal12/30 has caster2/spell2/
displayHP4/percent1 plus ownHP2/TP2/unknown2; targeted heal12/31 starts victim2/
caster2/direction1/spell2/displayHP4/percent1, optional victimHP2. Native Recover
42/8 supplies caster HP/TP. Spells are serialized `id,level;` in the DB and
exposed in player.spells; only native ACKs mutate the learned list.

Skill master NPC type is14, not7 (Inn). Open16/13 sends NPCindex2 and returns
NPC definitionID2/name break and28byte offers. Stat order in offers is STR/WIS/
INT/AGI/CON/CHA, despite config comments listing INT/WIS. Learn16/9 uses session4/
spellID2 and replies spellID2/Gold4; Forget16/4 uses the same request shape and
replies spellID2. Training16/7 uses TRAIN_SKILL2 aschar1/spellID2;16/2 returns
remaining points2/spell2/newlevel2. Native maximum skill level is100 in the
current configuration. These levels retain the pinned world's behavior; do
not invent extra spell scaling. The native server does not enforce client SP;
this update uses native TP and casting/recovery rules, not a new SP system.

The supplied `reference/extracted/trunk-305-EODelta/trunk 305 EODelta/data/skills.ini`
is populated Version1 data: NPC116 Aeven,124 Anundo,144 Padu,162 Bard. The old
runtime sample skills.ini was empty. `server/import_skills.py` installs the
original bytes as data/aster-vale-skills.ini and points SkillsFile there. Setup
with --economy-data also imports skills.ini when supplied. Original prices,
class/attribute/prerequisite requirements are retained. Masters are indoors on
maps156,162,220,216, respectively, reached by normal linked maps. NPC spawn
locations may differ from the EMF center after native spawn placement; approach
the live NPC coordinates, not the static center.

`tools/export_catalog.py` now exports all31 ESF definitions, GFX025 icons and
GFX024 effect layers. GFX025 has two horizontal halves (normal/hover); the
client uses AtlasTexture regions. `tools/spell_metadata.py` derives34 default
frame/layer/offset/loop records from pinned MIT EndlessClient
Rendering/Metadata/EffectMetadataProvider.cs. Effects animate at120ms/frame,
with behind/transparent/front layers, sliding/flicker/position modes. Killed
NPC effects retain their last coordinates. Player composition now includes
skin GFX008 resource4 and armor/weapon logical11/12 for casting in all four
directions. Original assets remain ignored and out of the public repository.

Scope limits: no party management/group casting, bard implementation or PvP
attack targeting in this update; these show a clear unavailable message. The
native pinned world itself has no Bard SpellAct effect. Full cosmetic/player
appearance coverage remains as documented previously. Spell sounds beyond the
existing game audio are not added yet.

Production was backed up before a brief world/adapter restart to install native
skill-master config and grant the requested Skylar changes. Skylar now has
level120, EXP at least229996800, baseAGI90, baseCON30 and test skills Heal Self1,
Small Fire4, Small Thunder5 (existing learned skills/levels preserved). Added
level points follow the native3 stat/skill points per gained level. All Gold,
items, equipment, other attributes, other characters and password salt were
preserved. Public WSS native Welcome verified level120 and displayedAGI90/CON30.
Private operator details/evidence remain in ignored work/session-handoff-private.json
and work/v13-skylar-verified-private.json; never publish login data.

Validation:31 server state regressions and13 original catalog/graphics checks
pass; gameplay smoke passes. `server/test_skills.py` tests native learning/
training/forgetting, self-heal HP/TP, another client receiving chant/effects,
spell cancellation without TP spending and fire kills/EXP without Refresh.
`server/test_skills_ui.py` drives real Godot touch shortcuts, target selection,
original effects, skill book sizing and master learning/forgetting. Both pass
locally and through public WSS; sanitized reports are docs/skills-v13-*-report.json.
Rendered screenshots were reviewed under work/v13-skills*-screenshots. Tests
use fresh dev accounts only; operator accounts are never integration fixtures.


The v0.13 APK was installed and launched on Galaxy S23 Ultra over wireless ADB,
verified package13/0.13.0, byte-identical offline save, valid signature and16KB
alignment, no startup script/crash errors and healthy hosted services. Report:
`docs/skills-v13-phone-report.json`; raw phone logs/save hashes stay ignored under work/.
The public Godot test additionally verifies another player's original casting
pose and heal effect. Download artifacts are the v0.13.0 APK, source ZIP and
SHA256SUMS under the task outputs directory. Original assets are in the APK
for the user's local testing, not in the source ZIP or public Git repository.


## v0.14: counter NPC services and left-side skill targeting

Skylar's saved production position was map125/tile6,4 (Marble Shop) when the
user reported being unable to tap Marble's head. Read-only SQL confirmed this;
no operator-character login, relocation, stat changes or grants were performed.
Map125 has an impassable counter at x5 separating the customer from Marble
(NPC87, graphic53). Marble can wander on her side. The previous client AND
Python gateway imposed a two-tile service range and tried to path to that
range, which can be entirely unreachable. Original EndlessClient
Rendering/Map/ClickDispatcher.HandleNPCClick directly calls ShowNPCDialog for
visible NPCs; native handlers/Shop.cpp Shop_Open does not require adjacency or
pathfinding. It is therefore wrong to remove counter collision or move Marble.

Visible service NPCs (shop6, bank9, skillmaster14) now open directly without
pathfinding. The adapter bounds these services to the current same-map visible
NPC within Manhattan11 (the world's SeeDistance), rechecks live NPC presence and
range for transactions, and keeps movement/death/warp/trade/casting guards.
`services.NPC_SERVICE_DISTANCE` is shared by economy and NPC service checks;
`_near_service` validates current NPC index/location instead of stale coordinates.
Locker adjacency1, ground pickup distance2, NPC collision and combat approach
rules remain intact. This fix also covers bankers and teachers behind counters.

The joystick regression was input dispatch order: _input captured the entire
large lower-left zone before a touch could reach skill target handling in
_unhandled_input. Previous skill tests called map_click directly, so they missed
this actual Android input path. Main now converts the native screen touch using
get_global_transform_with_canvas().affine_inverse() and dispatches armed skill
or visible entity taps before starting the floating stick. The full world is
available for a selected spell's target; left-side enemies no longer become
joystick presses. Empty ground still starts the floating joystick, dragging
retains pointer ownership, and release clears input. An existing joystick
finger still suppresses unrelated map touches unless a skill is armed.

`online.map_entity_target` returns an explicit kind/tile, and `map_press` uses
that identity so a head tap doesn't become a loot/locker action on the same
tile. `map_target` remains a compatibility tile wrapper. Ground loot/lockers
are excluded from spell hit testing. Native touch ownership and emulated-mouse
suppression prevent a single tap from issuing a second cast/open request.
Physical desktop mouse clicks use the same priority and target resolution.

`server/test_npc_services_state.py` adds regressions for Marble four tiles away,
open without movement, transaction range/presence and live service contexts.
35 server state checks and gameplay smoke pass. `server/test_touch_interactions.py`
creates separate dev shop/combat fixtures; Godot feeds Input.parse_input_event
through the actual scene, including mouse emulation. At map125/tile6,4 it taps
Marble's visible head, opens Marble Shop without moving/path/correction, buys
War Axe360 for2000 and sells it for200. It then frames a real native rat inside
the lower-left joystick zone, selects Small Fire, injects a real touch, verifies
exactly one native cast/TP decrement with no movement, and checks empty-ground
joystick drag/release. Local and public WSS reports are docs/touch-v14-*-report.json.
Screenshots under work/v14-touch*-screenshots were reviewed. Existing bank,
locker, inspection, trading/chat and native skill UI regressions are also run
for the changed service flow; reports are docs/services-v14-local-report.json
and docs/skills-v14-local-report.json.

Production deployment updates economy.py/services.py/skills.py with source
backups and restarts only gateway/WebSocket services. Native world, Caddy,
Cloudflare, database and operator account data are not modified. The APK is
version0.14.0/code14, with the existing package/signing key. Use the current
mDNS ADB serial to install with -r and preserve the offline save byte-for-byte.


The v0.14 APK is installed and running on Galaxy S23 Ultra. Confirmed package
code14/version0.14.0, valid APK signature and16KB alignment, byte-identical
pre/post-install offline save, healthy public endpoint and no startup script/
crash errors. Sanitized evidence is docs/touch-v14-phone-report.json. Original
bank/locker/inspection/trade/chat UI and original skills/observer pose regressions
also passed. Deliverables use outputs/endless-online-android-v0.14.0.{apk,...}.
Raw device logs, saves and fixture credentials stay private/ignored under work/.


## v0.15: readable buy/sell/craft shop details

`client/scripts/shop_window.gd` now uses a1120x660 wooden modal with independent
left catalog and right selected-item panes. The old90px bottom description
could clip four original recipe materials and equipment details. All four
native material rows now fit within the right viewport at1280x720; additional
item stats/requirements scroll independently below. Each material has its
original item icon/name and colored Have / Need quantities. Gold is a normal
native ingredient row with original artwork. Missing materials disable the
Craft action and are called out in the footer. Repeated ingredient IDs are
aggregated to match the gateway's Counter guard (e.g. native Pilotte313 needs
11 Ant Legs322, from two recipe entries10+1). No crafting/price/gameplay data
is invented or changed.

Original reference: pinned EndlessClient Dialogs/ShopDialog.cs shows item
name and a short price subtitle for buy/sell, ingredient count in craft list,
and a separate full ingredient list in CraftItem/BuildMessage. This mobile
adaptation keeps the catalog and requirements visible together instead of
squeezing the full recipe into one bottom label. Buy/sell rows now read e.g.
War Axe ·2000 without "gold each". Quantity and total stay in the footer; the
selected pane shows full item name/icon, bag quantity, damage/armor/bonuses,
weight and level/class/attribute requirements. Native armor type12 gender is
shown as(M)/(F), distinguishing Lotus Armor311/312 and other same-name armor.

A second browsing bug was fixed: online snapshots call shop.refresh for every
world update. Rebuilding the entire list and calling _selected(reset=true)
used to reset quantity/selection/scroll while NPCs moved. Catalog rendering is
now keyed by mode/offer data, details by mode/item/ownership/offer data, and
routine refresh uses _selected(false). World/native snapshots preserve selected
item, requested quantity, and independent scroll offsets. Actual user selection
or tab changes may reset quantity. Ownership ACKs refresh rows/readiness while
preserving scroll. Empty buy/sell/craft sections clear stale details explicitly.

Modal curtains now use z_index10 in main._modal, so the later-created chat/HUD
buttons cannot draw over or intercept the wider shop header. Native gameplay
input still respects _modal_open. Existing HUD behavior outside modals remains
as before. No new graphics import, server deployment, restart or account grant
is needed for this client-only update.

`server/test_shop_ui.py` / `client/tests/shop_details_live.gd` run the actual
Godot scene with a fresh dev fixture in Marble's shop (map125/tile6,4). The
native fixture owns the real ingredients; tests buy two War Axes360 for4000,
sell them for400, show all four Lotus Armor311 materials at1280x720, verify
Pilotte's repeated/missing ingredients, preserve both panes' scroll and buy
quantity across explicit native snapshots, and craft311 using318x8/320x8/
322x10/Gold250. The native ACK must update the result and consumed bag stacks.
Also checked at1544x720. `shop_touch_input.gd` explicitly arbitrates native
screen touches in both panes: a12px drag scrolls with pointer capture and does
not select a row; release without a drag selects once. Emulated mouse events
are suppressed within the panes so a swipe cannot change the selected item.
Physical mouse/wheel/keyboard handling remains native. The first actual
finger-swipe regression exposed that ItemList was not scrolling from the
injected native gesture; the explicit handler fixes it, and real touch swipes
in both columns now pass. Touch capture clears when the modal hides or loses
focus. Local and public WSS tests pass; sanitized reports:
docs/shop-v15-{local,public}-report.json. Screenshots were reviewed under
work/v15-shop*-screenshots. Operator accounts are never used as fixtures.
Gameplay smoke passes after the common modal draw-order change.

Build version is0.15.0/code15. Package/signing key remain unchanged. Release
APKs/source/checksums follow the existing outputs naming convention. Keep
fixture credentials, device logs/saves and original assets private/ignored.


Final v0.15 APK installed and launched on Galaxy S23 Ultra with the existing
signing key. Confirmed version15/0.15.0, installed base.apk SHA256 identical to
the final touch-scroll build, byte-identical offline save across reinstall,
valid signature/16KB alignment and no startup script/crash errors. Report:
docs/shop-v15-phone-report.json. Raw logs and save backups stay ignored under
work/. Download files use outputs/endless-online-android-v0.15.0.*. No server
restart or operator account modification was performed for this UI release.


## v0.16 — purchase feedback, classic movable bag and Plaot Robes

Skylar's read-only live character inspection found Plaot Robes (item 407,
armor doll graphic 40), Blue Boots (80/graphic 1) and Ultima Blade (281/graphic 33).
The old `character_graphic` rejected every armor and boot outside graphics 0/1,
which caused the explicit two-circle placeholder. No operator character was
changed to fix this; the missing renderer was the cause.

`tools/export_player_layers.py` exports 252 independent male equipment layers
from the private original graphics archive: skin, hair, all male armor graphics,
boots and weapon front/back layers. Armor resource stride 50 and boots stride 40
match the pinned original CharacterSpriteCalculator. Each layer is a compact
32-pose atlas covering idle, walk, attack and cast in four directions. The world
renderer assembles these in original order; original split weapon attack sprites
remain in front/behind correctly. `tools/export_catalog.py` invokes the exporter
for future full content rebuilds. To regenerate just these layers:

```
python3 tools/export_player_layers.py --graphics-zip reference/gfx.zip
```

`tools/test_catalog.py` now checks all 32 starter frames against the previous
precomposition, pixel for pixel. All 252 layer exports succeeded with no missing
source art. Body support is still male/race 0/hair 1/color 0. Hats/offhands,
alternate bodies/hair and exact ranged-weapon animation offsets remain further
renderer work; do not describe this as complete support for every EO appearance.
The existing starter/precomposed assets remain as fallback/offline content.

`client/scripts/bag_grid.gd` restores the original 14×4 inventory with the eight
EIF ItemSize footprints (1×1 through1×4, then2×1 through2×4). Plaot Robes use 2×3;
Ultima Blade uses 1×4. Images fill their footprints and actual stack quantities
appear in the upper-right corner. Native finger dragging and desktop mouse
dragging snap to cells and reject occupied/out-of-bounds drops. Android's
emulated mouse press can arrive BEFORE the finger press; ignore it in the bag's
GUI handler so it cannot steal ownership of a drag. Cancel drags on hide/focus
loss or authoritative inventory membership/quantity changes.

Arrangements live separately in `user://bag_layouts.json`, keyed by server and
character name. JSON cell coordinates are normalized back to ints on load.
Never treat layout changes as item ownership changes or send them to the server.
Gold remains present at zero. Additional 14×4 bag pages keep all stacks reachable,
including dev inventories larger than the classic grid. Arrows browse pages;
Move to next bag moves the selected item to a free footprint on a later page.
The offline demo keeps its previous 24-slot presentation and unchanged save data.

Purchase/craft/sale messages use actual native `shop_transaction` events after
acknowledgement. The toast explicitly identifies the item/amount and says it is
in the bag, draws above the shop modal, and never claims success on submission.
Craft Have/Need has a 30px right margin inside the detail scroller. Shop View
opens the large original artwork and full stats; closing returns to the shop.
The inventory also has a large selected-item preview and scrollable attributes.
The larger item detail window keeps the image beside a scrollable stats panel.

Validation: 35 server state regressions, 14 original catalog/graphics checks,
gameplay/world/network regression scenes, the existing full native Marble
buy/sell/craft/touch-scroll suite, and the new `server/test_inventory_ui.py` passed.
The new isolated dev fixture tests real purchase feedback, craft padding,
six-cell finger dragging, collision rejection, layout reload, overflow pages,
exact inventory quantities, large previews, native robe/boots/weapon equip and
an independent native observer seeing armor graphic 40. No Skylar/ravigameboy
account login or mutation was used. Reports: `docs/inventory-v16-live-report.json`
and `docs/shop-v16-live-report.json`. Private screenshots are under
`work/v16-inventory-shots` and `work/v16-shop-shots`.

Build: 0.16.0/code 16, normal signed debug APK, arm64/x86_64, 16KiB alignment.
This is a client-only change; production services and native world need no
upgrade/restart. Existing production health endpoint returned `ok`.

Final v0.16 APK installed and launched on Galaxy S23 Ultra. Confirmed
version 16/0.16.0, valid signature/16KiB alignment, installed base.apk SHA256
identical to the final exported/download APK, byte-identical offline save across
reinstall and zero startup script/crash errors. Report:
`docs/shop-inventory-v16-phone-report.json`. Private logs/save backups remain
under ignored `work/`. Download files use
`outputs/endless-online-android-v0.16.0.{apk,-source.zip,-SHA256SUMS.txt}`.


## v0.17 — one large bag, no separate inventory preview or pages

User explicitly rejected the v0.16 inventory side preview/details and multiple
bag pages. The inventory now uses a single full-width 22-column grid with eight
visible rows (48px cells) in the same wooden modal. Extra rows, if needed, extend
the same scrollable bag rather than creating another bag. Removed the preview,
attribute/details panel, page arrows and Move to next bag action. A small selected
item name and Use/Equip action remain below the grid; original footprints,
quantity badges and rearranging remain unchanged. Shop View and paperdoll/stats
windows keep their existing separate behavior.

`bag_grid.gd` now saves positions as [x,y]. It migrates v0.16 [page,x,y] layouts:
first-page positions stay where valid, and items from all other former pages
repack into free cells of the same bag. Server quantities/equipment are not
changed by migration. Native touch drag, overlap rejection, reload persistence,
legacy page migration, original transaction feedback and robe rendering passed
with isolated dev accounts. Report: `docs/inventory-v17-live-report.json`.
Screenshot: ignored `work/v17-inventory-shots/v17-classic-movable-bag.png`.
Gameplay/world smoke checks passed; no native server changes are required.
Build version is 0.17.0/code 17. Deliver/install with the same signing key and
preserve the phone save, as in prior versions.

Final v0.17 installed and launched on Galaxy S23 Ultra. The installed base.apk
matches the final download APK by SHA256; version 17/0.17.0, signing/16KiB
alignment, byte-identical offline save preservation and startup logs verified.
Phone report: `docs/shop-inventory-v17-phone-report.json`. No operator character
or production service was changed.


## v0.18 — fixed 12×4 bag and native Drop

User clarified that the existing wooden window should have exactly 12 columns
and four rows, with enlarged individual cells. Grid is now fixed at 1056×384
inside the same 1120×640 modal: cells are 88×96. No added rows or bag pages.
Original EIF footprints still apply (robe2×3, long weapon1×4). Layouts save in
`user://bag_layouts_12x4.json`; first placement sorts larger items first to avoid
fragmentation. Original ownership/quantities never change due to layout. If an
old oversized test inventory cannot fit, its unplaced items remain reachable
through a conditional Items needing space selector in the footer, allowing
Equip/Use/Drop to make room without extra bag pages or losing server items.
Skylar's current owned stacks fit within the requested grid.

Action text is simply Equip or Use. Added Drop alongside it. The original
InventoryController.DoItemDrop uses an amount dialog for stacked items; the
new drop_window.gd provides that quantity choice and sends Item_Drop only after
tapping Drop. Gold can be dropped by quantity; Lore items cannot. Cancel/Back
sends nothing, duplicate submissions are blocked, and network closure hides the
dialog. Only native acknowledgement updates bag and ground items/weight; the
native world enforces map, quantity and drop restrictions. No world refresh is
needed for the new drop operation.

Server: EconomyMixin.drop_item, gateway item_drop dispatch and LiveSession's
native Item_Drop acknowledgement handling. Deployed only economy.py,
gateway.py and live_session.py to production after confirming the previous
remote hashes matched Git HEAD. Source backups and restart script are in ignored
work/hosting/upgrade_v18.py and /opt/aster-vale/backups. Only gateway/websocket
adapters restart; native world and operator character data remain unchanged.
The local gateway process was also restarted (see its current listener PID).

Validation: 37 server state tests, gameplay/world smoke, real native stack
partial-drop/ground/pickup roundtrip, exact four-row layout, compact action
labels, native touch rearranging, persistence and original robe appearance.
Report: docs/inventory-v18-live-report.json. Screenshots: work/v18-inventory-shots.
Build is 0.18.0/code18; use the existing signing key and preserve phone saves.

The new Drop/confirmation buttons were exercised with injected native finger
press/release, not only emitted button signals. Bag drag input must yield while
the quantity dialog is visible, otherwise it intercepts taps meant for the dialog.
Drop/pickup also passed end to end through public `wss://eo.kcpd.top/ws` using a
fresh isolated dev fixture. Report: `docs/inventory-v18-public-report.json`.

Final v0.18 installed and launched on Galaxy S23 Ultra; installed base.apk SHA256
matches the download build, version18/0.18.0 verified, valid signature/16KiB
alignment, byte-identical offline save, and no startup script/crash errors.
Report: `docs/shop-inventory-v18-phone-report.json`. Release files use
`outputs/endless-online-android-v0.18.0*`. Operator accounts remain unchanged.


## v0.19 — 15×5 bag, unobtrusive notices, facing, damage and held stats

User requests supersede earlier bag dimensions: current grid is exactly 15
columns and five rows in the same 1056×384 area (70.4×76.8 logical-pixel cells).
Positions save in `user://bag_layouts_15x5.json`, reading the character's v0.18
12×4 layout as a fallback so existing valid arrangements carry forward. Drop,
quantity selection and the compact Equip/Use labels remain available.

Toasts are now plain text with an empty StyleBox, two-second duration and a
brief final fade. Their timer runs BEFORE the `not started` return, fixing
Game server disconnected messages that previously stayed forever. Removed
NPC-kill/drop announcement toasts and the offline slime-kill toast; native drop
ownership tracking and level-up messages remain. Pickup/purchase/drop notices
still confirm acknowledged actions, with no large ribbon.

Original ArrowKeyController.FaceOrAttemptWalk calls Face before validating a
walk. The Android client returned when the tile was blocked without changing
facing, and request_attack redirected to an arbitrary adjacent NPC when none
was ahead. Blocked joystick directions now turn in place, using the original
Face_Player packet (7,8). Facing updates locally immediately; repeated rapid
turns coalesce to the latest direction at a 125ms send interval. Attack uses the
chosen direction and does not silently aim at another adjacent NPC. Move and
attack packets clear an obsolete queued facing. Face is nonblocking, keeps
attack timestamps unchanged, can follow a committed walk, and never requires a
world Refresh. Existing movement/attack cadence stays at 400/520ms. Deployed
only gateway.py/live_session.py; native world and operator characters unchanged.
Upgrade/backups: ignored work/hosting/upgrade_v19.py and native backup directory.
Local gateway listener PID changed; inspect ss rather than reusing an old PID.

Damage issue confirmed in actual GL rendering: old draw_string alignment width
18 clipped `12345` to about 5px of visible text; unrestricted drawing showed 48px.
Private probe: work/font_width_probe.gd and work/font-width-probe.png. Floats now
measure/center and draw the complete native value with an outline, render zero
as Miss like the original HealthBarRenderer, and distinguish incoming damage
with a different color. NPCs briefly flash on confirmed positive damage. The
old code also searched only the post-update NPC list, losing the killing blow
after NPC removal. Cache previous NPC tiles for the event, preserving the last
hit number. Do not inflate damage: native NPC::Damage limits to remaining HP
when LimitDamage=yes. Skylar was read only (class0/STR39, existing Ultima Blade);
no account, equipment, formula or combat balance changes were made.

Stats + now spend once on press, repeat after 350ms and every 160ms while held,
and stop on release, pointer exit, panel hide, focus loss, exhausted points or
server rejection. At most one acknowledged stat request is in flight; only
native totals change displayed attributes/remaining points. Buttons remain
held through their own in-flight stat request rather than disabling/resetting
the gesture every time. All six attributes use the same flow.

Validation: 38 server state tests, gameplay/world smoke, expanded network
regressions for blocked facing/explicit attack direction/Miss/last-hit value,
real native Rat chase with zero corrections and zero full Refresh during chase,
native peer observation of turning in place, and actual finger holding INT+
with confirmed points conservation and no allocations after release. Local and
public WSS integration also verify the 15×5 bag, native Drop/pickup, old layout
handling and notice expiry while gameplay is stopped. Reports:
`docs/gameplay-v19-{live,public}-report.json` and
`docs/combat-chase-v19-report.json`. Private screenshots:
`work/v19-gameplay-shots` and `work/v19-public-gameplay-shots`.
Build version: 0.19.0/code 19, same Android signing key and package.


Final APK0.19.0/code19 installed and launched on Galaxy S23 Ultra. Installed
base.apk matches the download APK by SHA256; signature/16KiB alignment,
byte-identical offline save and zero startup script/crash errors verified.
Phone report: `docs/gameplay-v19-phone-report.json`. Release files use
`outputs/endless-online-android-v0.19.0*`.


## v0.20 — complete catalog equipment layers, combat shortcuts and native Junk

Helmet of Darkness (item426, doll graphic44) was worn correctly in native state,
but the Android compositor exported/rendered no head or offhand layers. This
was a client asset/composition gap, not a server equip failure. New
`tools/export_player_layers.py` manifest version2 exports 1,055 layers, with no
missing resources: both genders, all seven native skins, 20 hairstyles × ten
colors, every catalog armor for its correct gender, all boots/weapons, headgear
and offhands. Original CharacterSpriteCalculator/renderer/metadata rules are
used for directional resource IDs, offsets, hat hair masking/hiding, face masks
and shield/wings depth. Armor/boot/skin offsets now respect gender. Bald uses
no hair while retaining the original hair-based hat anchor. This supersedes the
older male-only/no-hats/offhands limitations above. Exact ranged attack offsets
and sitting poses remain future work; rings/belts/etc have no world sprite in
the original and continue to affect stats/paperdoll only.

`online_controller.character_graphic` binds B000A0HSW head6/offhand7, builds
independent body/gear layers and a head/hair composition. `main._frame` masks
black hat pixels after compositing and caches the resulting head texture;
`head_images` caches source readbacks. Map changes clear both image/texture
caches. The existing paperdoll live preview uses the same generated frames.
A shader or trimmed atlases could further reduce large-population memory/
first-appearance composition work if future profiling warrants it. Do not
regress starter pixels: the 32-pose reference composition test still passes.

The attack circle moved up 64 logical pixels. Two configurable skill shortcuts
sit on its upper arc; two consumable shortcuts sit to its left. The Skills book
still opens the full learned list/master offers, with Set slot1/2. Bag remains
bottom-right. `quick_items.gd` provides tap-to-use and 500ms hold-to-assign, native
quantity badges, zero-stock indication, and per-endpoint/character persistent
assignments in `user://quick_items.json`. Defaults select owned HP/TP potions
only if no saved assignment exists; clearing both slots must remain cleared.
Assignment supports the same native consumables as bag Use, including scrolls.
No inventory is decremented optimistically; blocking/pending requests guard
repeated use. Native touches are owned and emulated mouse suppressed, holds
cancel on focus loss/other modals/disconnect; mouse presses also precede spell
world targeting. The pickup control is now a circular hand icon with an optional
item tooltip and no changing item-name text ribbon.

Bag footer adds Junk beside Drop and Equip/Use. `drop_window.gd` shares the
quantity chooser but labels Junk as permanent destruction and requires its
explicit button confirmation; Cancel has no effect on inventory. Original
Item_Junk is family14/action25 (NOT26): request id2+amount4; reply id2+amount3+
remaining4+weight1+maxweight1. Gateway validates positive, owned quantities up to
the three-byte reply limit, sends native Junk, waits for and applies the ack,
then returns state. Original Junk permits Lore items (unlike Drop), so the UI
and adapter preserve that distinction. Base event `item_junk` updates remaining
inventory/weight, and LiveSession marks dirty without a ground drop or Refresh.
Gold continues to show its coin even at zero. Public services deployment changed
only gateway.py/economy.py/eo_session.py/live_session.py, with source backups in
`/opt/aster-vale/backups` and ignored work/hosting/upgrade_v20.py. The native world
was not restarted. All operator accounts, including Skylar, remained unchanged.

Validation: 40 server state tests, 16 catalog checks including every visible
item/body choice and original hat colorkeys, gameplay/world smoke, network
regressions, native skill/master UI, and Rat chase with zero corrections and
zero full Refresh during chase. Native touch integration locally and over
public WSS tests both potion shortcuts/counts, hold assignment without use,
persistence, hand-only pickup, partial Junk/Cancel/no ground drop, and native
helmet426+shield56+robe407 equip with an independent observer. Original existing
bag/shop/drop/held-stat flows also pass. Reports:
`docs/gameplay-v20-{live,public}-report.json`, `docs/skills-v20-live-report.json`,
`docs/combat-chase-v20-report.json`. Private screenshots in
`work/v20-gameplay-shots` and `work/v20-public-gameplay-shots`.
Version0.20.0/code20 uses the existing Android package and signing key.

Final v0.20 APK installed and launched on Galaxy S23 Ultra; installed base.apk
SHA256 matches the download build, code20/name0.20.0 verified, signature and
16KiB alignment valid, offline save byte-identical, zero startup script/crash
errors. Report: `docs/gameplay-v20-phone-report.json`. Release files use
`outputs/endless-online-android-v0.20.0*`. Wireless ADB was reconnected using its
mDNS endpoint after Godot export restarted the daemon; use the current SDK adb.


## v0.20.1 / code21 — compact vitals and HUD placement

Small client-only layout update: the bag is centered on the former Skills book
location at bottom-right offset(-262,-100), size76. The Skills book (index2 in
skills_controller.buttons; two spell shortcuts remain index0/1) is anchored
TOP_RIGHT at(-356,24), directly left of Chat at(-266,24). Retain the conditional
top anchor when changing shortcut layout; applying the bottom anchor moves it
off-screen. Hearts and TP orbs, including their spacing/highlights, are drawn at
75% of the previous size. EXP width is174 and text stays at original font sizes,
with progress/text moved up to suit the shorter vitals. No native server update
or operator data mutation is needed. Visual QA: ignored work/v21-hud-preview.png
at1544×720. Gameplay/world smoke and signed Android build validate the update.
APK version0.20.1/code21 uses the same package and signing key.

Installed and launched v0.20.1 on Galaxy S23 Ultra; final base.apk SHA256,
version21/0.20.1, signature/16KiB alignment, byte-identical offline save and no
startup script/crash errors verified. Report: docs/gameplay-v21-phone-report.json.
Downloads use outputs/endless-online-android-v0.20.1*.


## v0.21 / code22 — native world-wide Online list and modern game chat

The original client uses OnlinePlayerActions.RequestOnlinePlayers(fullList)
and the Init PlayersList handler; OnlineListPanel's name action prepares a
whisper. ChatActions keeps separate Local/Global/PM histories and an outgoing
local echo because native broadcasts exclude the sender. The native server's
Global_Open/Close handlers are no-ops; global messages already broadcast across
maps. The previous Android UI only showed them inside a modal, making them
appear absent during play.

New server `online_players` operation uses native Players_Request(22,1), with
no database reads or Refresh. Native Init(255,255), reply code8, contains count2,
FF, then name-break/title-break/unknown1/icon1/class1/guild3-break per player.
ServicesMixin.parse_online_players preserves public title/class/guild/icon,
sorts names, and emits an `online_players` event. The server applies original
hide-online/admin rules, verified using a real isolated hidden character.
Requests are asynchronous, limited/cached to five seconds, and deferred during
committed movement/warp to avoid confusing an Init map-download response with
the roster. The full chat Online tab refreshes only while visible, every ten
seconds, supports search and one-touch whisper selection. Nearby players are
not used as a substitute for the world roster.

`chat_window.gd` now has Nearby/Global/Whispers/Online tabs; private conversations
filter by recipient, with a recent contacts list, timestamps, unread badges and
clickable names. A bottom-center 504×52 translucent quick composer selects
Nearby/Global and opens private chat; a bounded four-message feed immediately
shows native local/global/private/system events without opening the modal.
Global entries stay until displaced by newer messages. Full session history is
bounded to250 entries and is cleared on character entry; no private chat is
written to disk. RichTextLabel uses add_text and push_meta, never parses chat as
BBCode. Native Latin1/128-character/rate-limit/not-found/mute rules stay in force.
Sending through the native server keeps its normal sender echo; it does not
claim a recipient delivery receipt. Rejected requests restore an empty draft.
One chat send may be in flight; new text typed while pending is preserved.

Quick shortcuts: /g or /global, /s or /nearby, /w name message, /r reply, and
original !name message. Enter focuses quick chat on desktop. Quick Send dismisses
the keyboard; Nearby Send in the full window still closes it, preserving the
user's earlier preference. Chat sends and roster requests do not trigger a native world Refresh.

The HUD's normal GUI input must precede world targeting/floating joystick;
owned movement/attack releases must STILL reach cleanup, including when the
finger ends over chat or a channel popup. Quick focus cancels controls and
suppresses WASD/world actions. Empty feed backgrounds are hidden. Controls use
anchors plus offsets: assigning Control.position.y after centering can move the
HUD off-screen; quick_root.offset_top/bottom adjust keyboard lift correctly.
Keyboard height lifts the quick HUD; `_layout` compacts the full chat above the
keyboard, keeping its input and Send visible. Store last_keyboard_lift so a new
message cannot reset the layout for one frame. `blur_quick` hides the virtual
keyboard ONLY if quick_entry had focus; calling hide every inactive frame would
break the login keyboard. Android Back/focus loss handle chat/controls cleanup.

Deployment changed only server/gateway.py and server/services.py; originals
matched Git HEAD first and were backed up under /opt/aster-vale/backups. Scripts:
ignored work/hosting/{deploy,upgrade,provision}_v22.py. Only gateway/WebSocket
adapters restarted, not the native world. No operator characters changed.
Skylar's separately requested Scav Bow/Fire Arrows/Lens grant is recorded in the
ignored private operator handoff and its native backup, not in this UI update.

Validation: 42 server state regressions, gameplay/world smoke, existing network
regressions and the native services UI (bank/locker/inspection/trade/local chat/
whisper). New actual Godot finger presses through Input.parse_input_event verify
the Online tab, a real cross-map whisper and reply, native hidden-player filtering,
global feed visibility without a modal, literal markup, quick composer input and
keyboard release, /r, rejection draft restoration, 1280/1544 layouts and compact
keyboard layout. Reports docs/chat-v22-{live,public}-report.json and
docs/services-v22-live-report.json. Private visual QA in work/v22-chat-shots and
work/v22-public-chat-shots. Build0.21.0/code22 retains the package/signing key.

Final v0.21.0/code22 installed and launched on Galaxy S23 Ultra. Installed
base.apk SHA256 matches final APK, code/name verified, signature/16KiB alignment
valid, offline save byte-identical and no startup script/crash errors. Report:
`docs/gameplay-v22-phone-report.json`. Download files use
`outputs/endless-online-android-v0.21.0*`. Source/graphics state and live Python
adapter hashes match the tested build/deployment; native world was not restarted.


## v0.21.1 / code23 — center other players' names on their heads

Peer names previously began at the fixed offset(-28,-66), so a short name such
as skylar visibly sat left of the character's center. Original CharacterRenderer
uses HorizontalCenter - ActualWidth/2. New online_controller.player_name_offset
measures the actual name with the same Godot font/size11 used to draw it, and
subtracts half its width from the shared body/head anchor. Existing label height
and interpolation remain unchanged. Weapon/shield/wings/animation bounds never
move the label. This fixes every observing client's peer labels for short and
long names; it does not require a native server change. Observers on an older
APK still need to update to see centered names.

Expanded existing network regressions cover skylar, a single letter, and a
16-character name, alongside the previous peer swing/direction checks. Gameplay
smoke and signed Android build pass. Private original-art visual probe:
work/v23_names_preview.gd / work/v23-peer-name-centering.png. APK0.21.1/code23
retains the existing package/signing key. No operator-character mutation.

Installed and launched v0.21.1/code23 on Galaxy S23 Ultra; final installed APK
SHA256 matches the build, signature/16KiB alignment valid, offline save unchanged
byte-for-byte and no startup script/crash errors. Report:
docs/gameplay-v23-phone-report.json. Download files use
outputs/endless-online-android-v0.21.1*. No server restart or account change.


## v0.22.0 / code 24 — native coupons, character grants and Shop Bob close

- Hamburger menu now has **Redeem Code**, implemented in `redeem_window.gd`.
  `KCPD108` gives 1,000 Big Health Potions (375), 50,000 Gold (1), and one Lens
  of Truth (421). It is once **per account**, including other characters on the
  same account. Operator grants do not consume the coupon.
- `server/rewards.py` normalizes/validates codes, waits for the native reply and
  applies acknowledged item totals. Native extension family/action **230/1 →
  230/3** is implemented by `patches/etheos-redeem.patch` in Item.cpp and the
  packet enum. Account comes from authenticated `Player::username`; reward
  definitions never come from clients. A primary key `(account,code)` in
  `aster_coupon_redemptions` prevents repeat rewards. Character Save and ledger
  INSERT commit together. Failure restores live inventory and rolls back DB.
  Preserve this table with account/world backups.
- `setup.py` now applies **three** independent pinned-source patches and records
  every hash: password v3, redeem, and `etheos-character-hp.patch`.
- Character HP patch supports operator config `CharacterHPFloors = name:1000,...`.
  It applies a minimum max HP after the original formula/equipment math and
  before current HP clamps. Ordinary characters retain original rules. Hosted
  config lists only Skylar and Ravigameboy. Both were filled to 1,000 HP. This
  survives equip/recalculation/reconnect without changing CON or other stats.
- Hosted world binary was compiled on Debian (local binary is not portable to
  its GLIBC). Ignored host build: `/home/admin/eo-v24-native/{source,build}`.
  Runtime `/opt/aster-vale/runtime/etheos`, adapter modules in app/server.
- Authorized offline clone/grants completed with graceful three-service stop,
  full SQLite/source/binary/config backups, and all other row fields and account
  records checked. Operation marker **v24-rewards-loadout-20261017-v1** is in
  native table `aster_operator_operations`; matching private backup directory
  under `/opt/aster-vale/backups/`. Never rerun a non-idempotent grant.
- Ravigameboy copied Skylar's fresh level 120, EXP, six base attributes, class,
  points, karma, learned skills/TP, bag, paperdoll, locker and bank Gold. Existing
  target excess belongings were retained in the bag/locker. Each then received
  **10,000 Big Health Potions + one Lens of Truth + one Oron (460)**. Identities,
  appearance, position, quests, passwords and account rows were preserved.
  Read current live/DB state before future grants; the user actively plays.
- Shop Bob close bug reproduced at 1544×720: close X overlaps the Chat HUD.
  Godot Control GUI hit testing follows scene-tree order, not drawn `z_index`.
  Chat HUD was built later than the shop and intercepted taps. `_modal` marks
  curtains; `_build_ui` now moves every modal root after all HUD nodes so its
  visible input priority matches its rendering. Shop close also clears queued
  interaction and blocks leftover touch/mouse events for 180ms. Owned releases
  still clean up before this guard. Do not put a global delay on every modal
  hide: programmatic modal changes should not block unrelated controls.
- Tests: 47 server state cases; actual native invalid/success/repeat/reconnect/
  second-character coupon checks, immediate persistence, forced SQL failure
  rollback and capacity failure; Godot real GUI touch menu/claim/duplicate/back;
  same UI against public WSS; HP floor test across equip/reconnect; gameplay,
  map/world and network regressions; reproduced Shop Bob synthetic/native input
  regression and fresh deliberate Chat tap. Sanitized evidence is in
  `docs/rewards-v24-*.json` and `docs/vitals-v24-native-report.json`.
- Test details: EO character IDs are session-generated. On every fresh login,
  select fixtures by character **name**, then use that login's ID. A saved
  previous session ID can silently fail Welcome. SQLite has no busy timeout:
  let dev fixture sessions finish logging out before external test DB writes,
  especially DROP TRIGGER; otherwise a concurrent native logout Save can fail.
  Local test WS URL must end in `/ws`, e.g. `ws://127.0.0.1:8183/ws`.
- APK 0.22.0/code 24 uses the existing package/signing key; installation keeps
  existing phone save data. Delivery, hash, device proof and final commit are
  recorded in the release outputs/private handoff and `git log`.

- Follow-up in the same v24 release: Nearby speech was already broadcast natively
  with Talk_Player (18/8), but bubbles were painted inside each character's
  depth-sorted draw. Walls, roofs, later sprites and overlay2 could paint over
  them. Both self and peer speech now draw together at the end of the world draw,
  after scenery and combat numbers, using current interpolated character positions.
  Expired bubbles are pruned after the existing 5.5 seconds. Global/whisper text
  stays in its channel and does not replace Nearby speech. Actual two-Godot-client
  native sends/replies and expiry are covered in `nearby_bubbles_live.gd` and
  `docs/chat-bubbles-v24-live-report.json`; an observer screenshot was inspected. The same two-client speech/reply/expiry
  test also passed through public WSS (`docs/chat-bubbles-v24-public-report.json`).
