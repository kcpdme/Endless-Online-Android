# Server baseline validation — 16 October 2026

The real upstream etheos 0.7.1 C++ server was built from pinned source on Linux with GCC 15.2.0, Android SDK CMake 3.22.1, and locally compiled SQLite 3.46.1. No administrator installs were required. Build state and downloaded content live outside the deliverable at `work/server-build` in the implementation workspace.

`setup.py` completed twice, including an incremental repeat, retaining the generated password salt and existing SQLite state. Upstream source files were not patched. The source's JSON dependency was supplied at the same version as its installer, and its umbrella standard header was force-included because disabling precompiled headers exposes missing upstream individual includes with this compiler.

`smoke.py` booted the executable, exercised a real TCP exchange, inspected the database and listening socket, then terminated the server cleanly with exit code 0. The machine-readable evidence is `validation-report.json`.

Verified:

- 282 of 282 numbered world maps loaded.
- 490 item definitions, 302 NPC types, 31 spells and 8 classes loaded.
- SQLite automatically installed the upstream schema. Tables: accounts, bans, characters, command_audit, guilds and reports. `PRAGMA integrity_check` returned `ok`.
- `/proc/net/tcp` showed the only listener for port 8078 on `127.0.0.1`.
- EO version-28 Init request was accepted. Challenge 12345 produced the expected response 266403. This was checked against the real server, not a mocked reply.
- Public listing is disabled, environment configuration overrides are stripped by the local launcher, and automatic promotion of the first created character to administrator is disabled.
- Server shutdown was clean. Python source files compile without syntax errors.

Quest conversion and parser results:

- The raw sample archive supplied 36 numeric `.txt` quest files. Initially only 25 parsed; 11 failed on legacy syntax or validation.
- `prepare_quests.py` preserves original `.txt` bytes and records every generated-copy change in `content-manifest.json` / runtime `content-report.json`.
- Existing `Reset`, `End` and `ShowHint` functions now receive the required `action` prefix where it was missing. `rule RemoveItem` and `rule Reset` are corrected to `action` because these implemented functions occur only in the server action table. Three unterminated UI strings receive their missing closing quotes. Hyphenated internal state identifiers are consistently renamed in declarations and matching goto references.
- **35 of 36 supplied quests now parse and validate successfully.** Final startup emits no quest parser errors. The server prints `35/56 quests loaded` because it scans through highest ID 56 and the source pack contains intentional gaps.
- Quest 17 references state `Reset` from `EndWithoutReset`, but only `GoReset` exists. It remains disabled in `data/quests_disabled/00017.eqf` pending review of its intended daily quest behavior. Its original `.txt` is preserved. No redirect was guessed.
- All 36 preserved original quest files were compared byte-for-byte against the pinned archive. Regenerating every quest reproduced identical generated hashes.

Remaining content gaps:

- The map loader reports 58 chest spawn warnings on maps 10, 21, 68, 70, 158, 199, 222, 233 and 234. These spawn records point to tiles that this server identifies as non-chests. Terrain and chest gameplay need map-level review before editing their meaning.
- One quest is deliberately disabled as described above; the nonnumeric haunted-house draft also stays inactive.

Therefore `content_validation_passed` remains explicitly `false`; the smoke result is `server_smoke_passed_with_content_gaps`. A passing smoke process establishes the local server foundation, active quest parsing, and handshake only. Parsing does not establish that a quest's rewards, NPC interactions or progression are correct in play.

No character/account gameplay, encrypted session, authoritative movement/combat, load test, or phone-to-server connection has been validated. The Android/Godot client is still an offline exploration prototype. The next network milestone should implement a maintained EO transport adapter and a complete two-client login/movement/combat round trip. Quest syntax repair and chest placement validation are separate content tasks before those systems enter a playable online alpha.
