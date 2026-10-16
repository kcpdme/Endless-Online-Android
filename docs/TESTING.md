# Validation scope

The version 0.4 client has been exported with Godot 4.7.2 and installed on an
Android 15 emulator and a physical Galaxy S23 Ultra running Android 16.

The gameplay smoke exercises real scene code for collision/pathfinding,
eight-direction joystick input, native touch plus generated mouse ordering,
simultaneous movement and attack, 0.9-second held attack repetition, release and
modal/focus cancellation, combat, loot, separate bag/paperdoll equipment flow,
the original paperdoll OK button, local save/load, and old-save migration.

Run it after importing content:

```sh
python3 scripts/test_client.py --godot /path/to/Godot
```

The wrapper uses temporary user data. Parser tests can run without reference
archives; real-data checks skip when those archives are absent:

```sh
python3 -m pip install -r requirements-tools.txt
EO_DATA_DIR=/path/to/reference-archives python3 tools/test_import_eo.py
```

All 12 importer tests passed locally against the reference data, including all
289 reference map files and eight distinct equipment appearances. Android APK
signature verification and 16-KiB zip alignment checks passed.

Private phone saves, screenshots, compiled APKs and session reports are not
published in this repository. Multiplayer is not yet implemented in the client;
see `server/VALIDATION.md` for the separate server startup/handshake scope.
