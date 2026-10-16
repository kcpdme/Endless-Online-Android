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

The local server configuration starts new characters on Aeven, map 5, at 40,40, with actual item IDs 21 (Dagger), 80 (Blue Boots) and 143 (Soldier Plate) in their inventory. They start unequipped; the server validates equipping. The plate is a male item; the first slice's character art uses a male character. Existing characters receive no inventory grant. Loopback reconnect delay is disabled and up to 12 connections per IP are allowed because all adapter sessions share one loopback address.

## JSON-lines protocol

Send a flat JSON object followed by a newline. Every reply preserves its `id` and `op` and has either `ok: true, data: ...` or `ok: false, error: ...`. No request body, password, or raw authentication packet is logged. Each connection allows at most 16 requests per second, 16 scalar fields per request, 256 characters per string field, and a 64 KiB input buffer. The gateway caps simultaneous connections at 12.

Supported operations:

- `connect`: initialize and confirm a genuine EO v28 session. This does not log a player in.
- `register`: `username`, `password`. Create a real server account.
- `login`: `username`, `password`. Return `characters`, each with `id`, `name`, `level` and appearance fields.
- `create_character`: `name`; optional `gender` (1 male, 0 female), `hairstyle` (default 1), `haircolor` and `race` (default 0).
- `enter`: `character_id` from the **current login response**. Complete both Welcome stages and return a snapshot.
- `refresh`: request and return a fresh server snapshot.
- `walk`: `direction` (0 = y+1, 1 = x-1, 2 = y-1, 3 = x+1). Return a fresh server snapshot after the request. The adapter spaces requests by at least 0.43 seconds; etheos applies its own movement rules. Returned coordinates can differ from the requested destination when the server rejects a move.
- `attack`: optional `direction` using the same convention. Face and attack through real EO packets, respecting 0.9-second adapter recovery, then return server state and any confirmed damage/death events.
- `pickup`: `uid` of an actual visible ground item. Wait for the real Item_Get acknowledgement.
- `equip` / `unequip`: `item_id`; optional `subloc` (default 0 for paired slots). Wait for the real Paperdoll acknowledgement and request equipped item IDs again.
- `disconnect`: close the native session, allowing etheos to save progress.

EO character IDs are session-generated identifiers, not stable database primary keys. After reconnecting, obtain the character ID from the new login response. Account credentials and character name persist.

Snapshots contain `online`, `map_id`, `player`, `players`, `npcs`, `items`, and `events`. The `player` includes connection `id`, current `character_id`, name, map coordinates, facing, HP/TP, `max_hp`/`max_tp`, actual `inventory` entries `{id, amount}` and `equipment` mapping slot names to server item IDs. `players` includes the local player; filter by `player.id` when drawing peers. NPCs contain server `index`, catalog `id`, coordinates and direction. Items contain server `uid`, item `id`, coordinates and amount.

Events use a `kind` discriminator. `npc_damage` contains `player_id`, `npc_index`, `damage`, and `hp_percent`; `npc_killed` contains the NPC index, damage and an optional nonzero `drop` record. `pickup`, `equip`, and `unequip` are generated only from their corresponding server acknowledgements. Other packets are recorded only as family/action/length metadata. Server refresh snapshots remain the authority for entity presence and positions.

The gateway drains unsolicited packets and answers sequence-update pings while idle. Active clients should request refresh periodically (the Godot slice polls around every 0.6 seconds). Map transitions/content downloading are not implemented; the current Godot slice blocks Aeven warp tiles and closes if an unexpected map arrives.

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
