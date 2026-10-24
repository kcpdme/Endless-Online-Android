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

The build disables upstream precompiled headers and force-includes the upstream `src/stdafx.h` umbrella header instead. This retains required standard-library includes with the current compiler. Setup applies the checked-in password, account coupon, optional character HP floor, bounded spike damage, mobile spell, and mobile potion/combat feedback patches to the pinned source. Patch hashes are recorded in the generated content report.

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
Gold banking, item lockers, equipment inspection, trading, chat and skills now have separate native flows. Guild NPC opening, founding/support invitations, recruiter applications/acceptance, deposits, ranks, descriptions, leave/disband and guild chat use native Guild/Talk packets. Membership and Gold change only after native acknowledgement; silent leave/disband actions are verified through a self-paperdoll ordering barrier. Party controls remain future work.

## Password hash upgrade and recovery

Earlier setup generated a 64-character private `PasswordSalt`. Upstream version 2
prepended that salt and the account name to the password before bcrypt. Bcrypt
reads at most 72 input bytes: a sufficiently long account name could remove the
entire password from verification. A verified regression reproduced wrong-password
acceptance on isolated dev accounts. Do not automatically migrate these hashes
after an apparent successful login: that cannot prove the full old password.

Version 3 computes the 64-character SHA-256 hex encoding of the full existing
salt/name/password input, then bcrypt at work factor 12 with its own random salt.
The per-runtime secret and database are preserved. Setup explicitly selects
`PasswordCurrentVersion = 3` and `RejectLegacyBcrypt = yes`. Hosted deployment
does the same. Vulnerable version-2 accounts receive recovery code 7 until an
operator resets their password; their characters, equipment and inventory remain.
The upstream-compatible patch default allows legacy verification, so upgrading an
existing runtime must explicitly set the two secure config values above.

Stop the native world and make a private backup before recovery. Run locally as
the operator with runtime access:

```sh
python3 server/reset_password.py --runtime /absolute/path/to/runtime --username ACCOUNT
```

The tool prompts privately, creates an additional SQLite backup, uses the native
`runtime/native-auth` helper, and changes only that account’s password/version.
It verifies that all character rows are identical. `--generate-file /private/new-file`
instead generates a password into a new mode-0600 file; no password belongs in argv,
logs or source control. Rebuild both the world and helper through `setup.py` before
use. Old unpatched world binaries cannot read version-3 accounts.

`native-auth --self-test` reproduces the legacy truncation and verifies correct,
incorrect and suffix-changed passwords under version 3. `test_reconnect.py` also
verifies wrong-password rejection over real native login and WebSocket handoff.


## Original skills and masters

The client exposes learned native ESF spells through three touch shortcuts and
a skill book. Casts prepare and release original Spell packets at the original
chant cadence without blocking the gateway pump or refreshing the map. Native
replies update TP/HP, NPC damage, kill drops and EXP, and observers receive the
original chant, casting pose and effects. Target validation is server-side.

The supplied original `skills.ini` contains skill-master prices and requirements;
the upstream sample file contains no offers. Install the supplied file with:

```sh
python3 server/import_skills.py --runtime work/server-build/runtime --source /path/to/original/data/skills.ini
```

Restart the native world after changing its SkillsFile configuration. Setup
also imports it when present in --economy-data. The original Version1 offers
are preserved. Open, learn, forget and skill-point training use native16-family
requests/acknowledgements; the adapter never grants skills. Group/party casts,
bard effects and player-targeted offensive spells are not exposed yet.
See `docs/TESTING.md` for local/public native and Godot UI regressions.

## Account rewards and test-character HP

The hamburger menu's **Redeem Code** window calls `redeem_code`. The Python
adapter forwards the code to native `Redeem_Request` (family 230, action 1);
clients cannot choose accounts, rewards, quantities or character names.
`KCPD108` grants item 375 ×1,000 (Big Health Potion), item 1 ×50,000 (Gold), and
item 421 ×1 (Lens of Truth), once per account across all its characters.

The native server saves the character and inserts the account/code pair into
`aster_coupon_redemptions` in one database transaction before acknowledging.
Inventory limits or database errors leave both inventory and redemption status
unchanged. A lost acknowledgement is recovered by reconnecting; retrying cannot
grant twice. The ledger is created on first valid redemption and belongs in all
world database backups. Item weight remains the original native rule; operator
and coupon grants can exceed carrying weight, which affects later pickups.

For explicitly designated test characters only, `config.local.ini` may contain
`CharacterHPFloors = characterone:1000,charactertwo:1000`. The server preserves
original attribute/equipment calculations and applies the minimum maximum HP
before clamping current HP. Set current `characters.hp` during an offline grant
when full health is also required. Unlisted characters retain original rules.
Never edit a live character row: stop the world gracefully first and back up its
database. The hosted Skylar/Ravigameboy grant is recorded separately, with a
transactional operation marker so retries cannot add another 10,000 potions.

Verification with the actual native server:

```sh
python3 -m unittest discover -s server -p '*_state.py'
python3 server/test_rewards.py --report /tmp/rewards-report.json
```

`--fault-tests` adds dev-only SQLite failure/capacity fixtures to a local test
world. It must not be used during normal player sessions. GUI coverage is in
`client/tests/rewards_live.gd` and `client/tests/shop_close_regression.gd`.


### Native starter inventory and operator spells (v0.31)

New characters receive 1,000 Gold, matching Peasant Suit/Peasant Clothes,
Dagger, Oak Shield and learned Heal Self. The native character-creation patch
uses `StartItemsMale` / `StartItemsFemale`, with `StartItems` as fallback, and
`StartSpells`. `setup.py` configures this for fresh runtimes. For an existing
runtime, stop the world and take a consistent private database/config/binary
backup, install the patched native binary, then run
`python3 server/configure_starters.py --runtime /path/to/runtime` and restart.
Existing characters are unaffected by the starter policy.

`grant_spells.py` is an operator-only additive grant utility. With the native
world stopped and backed up, pass `--database`, `--esf`, `--characters` and
`--world-stopped`. It reads IDs from the actual native ESF, preserves existing
trained levels, appends missing skills at level zero, and updates only the
requested characters' spells field in one transaction. Re-running adds nothing.
The public gateway has no grant operation. Party and bard casting remain
unimplemented, even when those spells appear in the learned list.

### Operator admin blade

`admin_weapon.py` is a stopped-world operator utility for Skylar's dedicated
1,000–1,000 damage weapon (item 491). It preserves all original item definitions,
requires an administrator target, and grants one Lore item through a retry-safe
ledger. Back up SQLite/PUB/config before use. It is not a public gateway action.
See [admin weapon operation and validation](../docs/ADMIN_WEAPON.md).

### Connection recovery heartbeat (v0.39.3)

Deploy the updated `gateway.py` before installing the recovery client. The
lightweight `ping` operation confirms an existing native session without a
world Refresh or credential response. Restart gateway/WebSocket services; no
native restart or database migration is required. See
[recovery behavior and native outage tests](../docs/CONNECTION_RECOVERY.md).
