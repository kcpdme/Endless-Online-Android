# Aster Vale local server foundation

This builds the real C++ `etheos` server and stages the maintainer's sample world for local development. The project now also includes a real EO session adapter and local JSON gateway for the Android/Godot online slice. See [ONLINE.md](ONLINE.md) for commands, protocol and actual integration evidence. Offline exploration remains available separately.

## Build and run

Requirements: Linux, Python 3, git, a C/C++ compiler, ar/make, CMake 3.x, version 3.13 or newer (tested with 3.22.1; upstream dependency compatibility with CMake 4 is not validated), and internet access for pinned sources. SQLite is built locally from its verified amalgamation; no administrator install or Docker is required. If CMake is not on PATH, `setup.py` also discovers the Android SDK CMake installation under `~/Android/Sdk/cmake`, or accepts `--cmake /absolute/path/to/cmake`.

From the project root:

```sh
python3 server/setup.py
python3 server/smoke.py
python3 server/run.py
```

Setup defaults to `server/.local/`, which is excluded from version control. To keep build products elsewhere:

```sh
python3 server/setup.py --state-dir /absolute/path/to/work/server-build --sample-zip /absolute/path/to/sample-data.zip
```

Subsequent commands read the ignored `.state-path` pointer. `--sample-zip` is optional; the downloaded or supplied archive must match the pinned SHA256. `--jobs 2` limits build concurrency. Stop the foreground server with Ctrl+C. A running server must be stopped before running `smoke.py`.

The generated config binds **127.0.0.1:8078**, explicitly disables public server listing, uses SQLite `runtime/database.sdb`, and generates a random persistent password salt with owner-only file permissions. `run.py` removes inherited `ETHEOS_*` overrides so the local configuration cannot silently be replaced by shell environment values. Automatic first-character administrator promotion is disabled. No accounts or credentials are seeded. Do not delete the generated salt if retaining the database.

## Content and provenance

- Server: https://github.com/ethanmoffat/etheos at `d6b6395d5ae28e1b20cd72f33fbf23ba921e7919`, zlib license.
- bcrypt: https://github.com/trusch/libbcrypt at `d6523c370de6e724ce4ec703e2449b5b028ea3b1`; pinned dependency. Upstream MIT license applies.
- GoogleTest: https://github.com/google/googletest at `b514bdc898e2951020cbdca1304b75f5950d1f59` (v1.15.2). Required by upstream CMake configuration; server setup builds only the `etheos` target. Upstream BSD license applies.
- nlohmann/json 3.9.1: https://raw.githubusercontent.com/nlohmann/json/v3.9.1/single_include/nlohmann/json.hpp, SHA256 `7804b38146921d03374549c9e2a5e3acda097814c43caf2b96a0278e58df26e0`. Upstream MIT license applies. Matches the upstream dependency installer.
- SQLite 3.46.1: https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip, SHA256 `77823cb110929c2bcb0f5d48e4833b5c59a8a6e40cdea3936b99e199dbbe5784`. Public domain.
- Authoritative world maps/PUB/config content: https://etheosstorage.blob.core.windows.net/data/sample-data.zip, SHA256 `fad601ce11a4ed8d991b80b1cf31fcba237d01c566b4dc40cabb86b28861cc4e`.

The build disables upstream precompiled headers and force-includes the upstream `src/stdafx.h` umbrella header instead. This retains required standard-library includes with the current compiler; upstream source files are not patched.

Reference content is downloaded into local ignored state. The existence of a download does not establish publication rights for the original game content. The optional economy import below stages the supplied original shops and drops separately, with explicit config overrides. The separately recovered quest archive is not used by this baseline.

The sample pack contains plain EOPlus quest source under numeric `.txt` filenames. Setup preserves those original files and generates `.eqf` copies with conservative syntax repairs: explicit action keywords for implemented action functions, three missing closing quotes, and consistent renaming of internal state identifiers containing hyphens. Every change and source/generated hash is logged in `content-report.json`. Of 36 source quests, 35 now pass the real parser. Quest 17 remains isolated in `data/quests_disabled/` because it references a missing state; its intended redirect needs gameplay review. The nonnumeric haunted-house draft stays inactive. Missing numeric IDs are permitted gaps; the server prints 35/56 because it scans through highest ID 56.

`content-report.json` in the state directory records the source pins, hashes, map counts, and every converted quest's hashes and repair log. `smoke.log` and `smoke-report.json` record the real server parser and database results. The checked-in `VALIDATION.md` and `validation-report.json` record this implementation session's evidence. The smoke command returns success for a working server/handshake even if content gaps remain; consult `content_validation_passed` and the parser warnings.

## Network boundary

`handshake.py` sends a genuine EO version-28 Init packet to the server and verifies its mathematical challenge response. It can also test an already running local server:

```sh
python3 server/handshake.py
```

`handshake.py` remains a minimal initialization fixture. Full account/login/character/Welcome flows, server snapshots, movement, real NPC combat, item pickup and equipment operations are implemented separately in `eo_session.py` and exposed by `gateway.py`. See [ONLINE.md](ONLINE.md) for the current supported boundary. Loopback access from Android uses an explicit USB `adb reverse` during development.

## Persistence

The real upstream SQLite schema is installed by the server on first boot. The initial smoke test checks database tables and integrity. The later real-session integration also verifies account/character creation, equipment changes, NPC combat and persisted position/equipment after disconnect. Recovery from interrupted transactions and production backups remain untested. Database backups and production hosting require a separate deployment design.

## Original shops and NPC drops

After staging the supplied EODelta archive locally, stop the native world, make a
private SQLite/config backup and run this once against that runtime:

```sh
python3 server/import_economy.py --runtime work/server-build/runtime --source-data "reference/extracted/trunk-305-EODelta/trunk 305 EODelta/data"
```

Restart the world and adapter afterwards. Initial `setup.py` also accepts
`--economy-data /path/to/original/data`. The import preserves the original
Version-1 NPC IDs, prices, recipes and drop chances in separate
`data/aster-vale-shops.ini` / `data/aster-vale-drops.ini` files and changes only
ShopsFile / DropsFile overrides. It never changes account data or PasswordSalt.
Original content stays local and ignored by Git.

`economy.py` implements Shop_Open (13/13), Buy (13/11), Sell (13/12), Create
(13/6) and Item_Get (14/27) using pinned etheos builders/handlers. Transactions
require an opened nearby shop and apply inventory changes only from native
acknowledgements. Moving or warping invalidates the adapter shop session. The
native Item_Add payload is item2/uid2/amount3/x1/y1; Walk_Reply's ground-item
layout is separately uid2/item2/x1/y1/amount3. Partial pickup subtracts only the
acknowledged amount. Pickup and transactions do not request a full world refresh.
Bank, guild, quest and other NPC dialogs remain separate future work.
