# Endless Online Android

A first playable foundation for an independent Endless Online–inspired Android game, using Godot 4.7.2, typed GDScript, and 2D isometric rendering. The current app's working title is **Aster Vale**. This is an independent project, not an official Endless Online release.

This public repository contains source code, content import tools, build scripts and server setup. **Original EO assets, reference downloads, APKs, signing keys and personal game saves are not included.** Supply content before running or exporting the client; see [local content setup](client/content/README.md).

## Play the Android build

After importing content and building, install `builds/aster-vale-debug.apk` on an Android device (Android 7 / API 24 or later). This development build includes ARM64 and x86_64. Open **Aster Vale**, then **Enter the vale**. The build is signed with a development key, not configured for Google Play release.

The current playable slice is **local/offline**. It includes the imported 87×87 Aeven map, animated character, collision and pathfinding, a floating circular touch joystick, a training slime, attacks, loot, a separate wooden bag and original EO equipment paperdoll, sound effects and saved local progress. Character appearances are composed from the original layers during import and selected when equipment changes. The blade changes attack damage; the starter outfit and boots provide appearance changes in this slice.

- Drag in the lower-left area to use the translucent circular joystick. Releasing it stops movement and clears queued movement. Tap clear ground elsewhere to walk to a destination.
- Move beside the training slime and press/hold the enlarged circular **weapon icon**. Attacks repeat every 0.9 seconds; the rim shows recovery without fading the weapon. Release, slide off, or open a screen to stop. With no weapon equipped, the icon shows a fist. The slime does not damage you in this first slice.
- The **bag icon** opens only the 24-slot wooden bag. Select a stored item and equip it.
- The **person icon** opens the original EO paperdoll bitmap and all 15 original equipment positions. Select worn equipment and use **Remove** to move it into the bag. The original **OK** button closes the paperdoll. Three equipment types currently work: armor, boots and weapon; the other slots remain empty until their items are implemented.
- Progress saves locally. The menu includes a confirmed reset.
- Desktop controls: WASD/arrows, hold the mouse on the weapon icon to repeat attacks, Space for one attack, I for bag, C for paperdoll, E to collect, Escape to close a screen or open the menu.

## Open and build

Import licensed/reference content using [the content setup instructions](client/content/README.md), then open `client/project.godot` with Godot 4.7.2. The local development workspace may already contain imported assets; a fresh public checkout does not.

Linux build prerequisites: Python 3.10+, Java 17, and an Android SDK for APK export. The scripts use the official pinned Godot release, verify published SHA-512 hashes, and keep tool configuration/debug signing material in the selected local cache. Initial engine/export-template download is approximately 1.3 GB. The SDK path defaults to `ANDROID_HOME`, otherwise `~/Android/Sdk`.

From this project directory:

```sh
python3 scripts/build.py android --bootstrap
python3 scripts/build.py web
python3 scripts/build.py linux
python3 scripts/build.py check
```

Use `--toolchain /path/to/cache` to reuse another cache and `--sdk /path/to/Android/Sdk` to select the SDK. `client/export_presets.cfg` is generated for the local toolchain. Nothing is uploaded or published by these commands.

To preview the browser export, serve `builds/web/` with a local HTTP server. The browser build is a convenience preview of the same client; the Android APK is the target deliverable. The Linux export is optional.

## Local real server

The separate `server/` scripts build and run the actual pinned etheos C++ server with SQLite and the maintainer's world data:

```sh
python3 server/setup.py
python3 server/smoke.py
python3 server/run.py
```

The server binds only `127.0.0.1:8078` and does not advertise itself publicly. The client is **not yet logged into this server**. The tested server fixture verifies the genuine EO Init challenge response, not accounts or synchronized gameplay. See [server/README.md](server/README.md) and [server/VALIDATION.md](server/VALIDATION.md).

Server validation loaded all 282 numbered maps and 490 items / 302 NPC types / 31 spells / 8 classes. Generated syntax repairs permit 35 of 36 supplied quests to load; quest 17 is disabled pending an explicit content decision. Nine maps retain 58 chest-placement warnings. These are recorded content issues, not silently suppressed compatibility claims.

## Content pipeline and tests

`tools/import_eo.py` reads the preserved source ZIPs, decodes maps and PE graphics resources, exports the selected map and images, composes classic character animation frames, repairs selected WAV containers and records provenance. See [tools/README.md](tools/README.md).

```sh
python3 tools/test_import_eo.py
python3 scripts/test_client.py --godot /path/to/Godot
```

Set `EO_DATA_DIR` for real-data importer tests if the source archives are elsewhere. The gameplay test exercises the actual scene through joystick press/drag/release, independent attack input, modal/focus cancellation, collision, combat, loot, equipment, save/load and reset. The wrapper uses temporary user data, so even a failing assertion cannot overwrite a real desktop save.

## Next milestone

Connect the Godot client to the real server: EO framing/encoding/sequencing, account and character flows, welcome/content negotiation, authoritative movement and visibility, then combat/inventory synchronization. Add reconnect/resume behavior and test two clients together before expanding the world. The current training combat and local persistence must be replaced by server-authoritative state for online play.

## Content rights

This is a private development prototype using reference content. Original EO maps, graphics, quests and audio have not been established as licensed for publication in a new game. Obtain permission or replace them before distributing publicly. New code uses MIT; upstream software retains its original licenses. See [THIRD_PARTY.md](THIRD_PARTY.md).
