# Validation scope

Version 0.5 uses Godot 4.7.2. The Android APK was signed, checked for
16-KiB ZIP alignment, installed on an Android 15 emulator and updated on a
physical Galaxy S23 Ultra running Android 16. The physical device's existing
offline save was compared byte for byte immediately before and after updating.
The user resumed offline play. A real EO handshake also passed through the
physical phone's ADB reverse connection; full phone account entry was left to
the user while they were playing.

## Client checks

```sh
python3 scripts/test_client.py --godot /path/to/Godot
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

All 19 importer/catalog tests passed against the reference content. Real-data
checks skip when input archives/runtime data are unavailable. These cover map
and PUB parsing, real source hashes, eight hero equipment variants, all item
icons, eleven NPC graphic sets/offsets and five original money piles.

Native and JSON-gateway two-session tests both confirmed authoritative movement.
Real Rat damage/death, owned-item drop/pickup, equip/unequip and SQLite position/
equipment persistence passed. See `server/online-validation-report.json` and
`server/ONLINE.md` for the exact scope. Native tests create dev-prefixed accounts;
they preserve the database and salt.

Only Aeven/map 5 is rendered by the client. Other exits are blocked. NPC shops,
quests, chat, trading, spells, additional appearance combinations and production
hosting remain outside this milestone. Nearby entity frames currently use idle
sprites between polled positions. Server quest/chest content gaps remain recorded
in `server/VALIDATION.md`. Private credentials, device saves, generated assets,
compiled APKs and screenshots are excluded from the public source repository.
