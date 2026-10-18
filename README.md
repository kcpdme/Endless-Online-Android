# Endless Online Android

A first playable foundation for an independent Endless Online–inspired Android game, using Godot 4.7.2, typed GDScript, and 2D isometric rendering. The current app's working title is **Aster Vale**. This is an independent project, not an official Endless Online release.

This public repository contains source code, content import tools, build scripts and server setup. **Original EO assets, reference downloads, APKs, signing keys and personal game saves are not included.** Supply content before running or exporting the client; see [local content setup](client/content/README.md).

## Play the Android build

After importing content and building, install `builds/aster-vale-debug.apk` on an Android device (Android 7 / API 24 or later). This development build includes ARM64 and x86_64. Open **Aster Vale**, choose **Play online** to join the persistent shared world, or **Explore offline** for local practice. The build is signed with a development key, not configured for Google Play release.

The offline exploration mode remains available alongside hosted online play. It includes the imported 87×87 Aeven map, animated character, collision and pathfinding, a floating circular touch joystick, a training slime, attacks, loot, a separate wooden bag and original EO equipment paperdoll, sound effects and saved local progress. Character appearances are composed from the original layers during import and selected when equipment changes. The blade changes attack damage; the starter outfit and boots provide appearance changes in this slice.

- Drag in the enlarged lower-left area to use the translucent circular joystick. Releasing it clears queued movement; online play finishes the current committed tile. The pointer stays captured outside the circle. Tap clear ground elsewhere to walk to a destination.
- Move beside the training slime and press/hold the enlarged circular **weapon icon**. Tap for manual attacks. Hold for 0.6 seconds to latch auto attack, then release your finger; tap again for manual. AUTO appears on the button. Opening a screen, backgrounding or disconnecting cancels auto. The rim shows recovery without fading the weapon. With no weapon equipped, the icon shows a fist. The slime does not damage you in this first slice.
- The **bag icon** opens only the 24-slot wooden bag. Select a stored item and equip it.
- The **person icon** opens the original EO paperdoll bitmap and all 15 original equipment positions. Select worn equipment and use **Remove** to move it into the bag. The original **OK** button closes the paperdoll. Three equipment types currently work: armor, boots and weapon; the other slots remain empty until their items are implemented.
- Progress saves locally. The menu includes a confirmed reset.
- Desktop controls: WASD/arrows, hold the mouse on the weapon icon to repeat attacks, Space for one attack, I for bag, C for paperdoll, E to collect, Escape to close a screen or open the menu.

## Play online

Version **0.33** adds an original-style minimap below the hearts: tap its header
to collapse or reopen it. Orange marks you, green other players, red monsters,
purple other NPCs and blue interactive tiles. It follows the current map and
player position. Timed spikes now raise for one second on the native trigger;
trap spikes appear when occupied. The Hall of Pain approach chest now has
visible artwork at its existing solid tile. Chest tile specs always block
client movement, including when cached collision metadata is incomplete.

Version **0.32** makes both Ice Blast skills cast on a shortcut tap, without
selecting an opponent. Each cast affects up to five monsters in a **5×5 area
centered on you** (two tiles in each direction), with one TP charge and the
original damage rules. Fairy Soda now shows its original timed drunk emote,
slurred/starred chat with `*hic*`, and a subtle haze on your speech bubble.
Small soda lasts25 seconds; Big soda lasts137.5 seconds. It does not restore
HP/TP.

Version **0.24** removes the pause between walking tiles and runs at the native server’s effective 420 ms step pace. Held joystick/WASD/arrows chain continuously; nearby actors replay queued steps with a small jitter buffer. All players should update their APK for the smoother movement rendering. See [movement evidence and timing](docs/MOVEMENT.md).

The Android build defaults to **`wss://eo.kcpd.top/ws`**. Create an account and character to play on the hosted world without ADB or a running development computer. The server runs on AWS behind Caddy HTTPS and proxied Cloudflare DNS. Accounts and progress on this hosted world are separate from the local development server and offline journey. See [hosting and maintenance](deploy/README.md).

The world pack now includes all **282 maps**, 3,945 original warp records and their graphics. Walking into a valid exit changes the rendered map only after the real server completes its warp handshake. Doors open through native EO requests; keys and level restrictions remain server-controlled. Eight malformed legacy warp destinations on map 47 are blocked rather than sending a player outside a map. Gold banking, item lockers, equipment inspection, player trading and nearby/global/private chat now use the original native server flows. Tap a banker, a nearby locker, or another player to interact. The mobile HUD uses HP hearts and blue TP orbs with a dynamic floating joystick. It also shows the current level and a thin next-level EXP bar. The bag supports native potion/scroll use; Nearby chat closes on Send. Three touch skill shortcuts and a skill book use native learned spells. Tap an attack skill, then a monster anywhere on the screen, including the joystick area; Heal Self casts immediately on yourself. The book shows TP, chant time, skill level and original learning requirements. Tap a skill master to learn or forget; spend skill points with Train +1. Original spell icons, chanting poses and effects are rendered for you and nearby players. Party/group and bard skills, PvP targeting, quests, guild/party controls, additional NPC services remain future work. Character creation offers male/female bodies, 20 hairstyles, 10 original hair colors and the native creation skins (White, Tan, Pale, Orc), with a rotating preview.

Version 0.15 gives Buy, Sell and Craft a scrolling catalog and a separate item-details column. Recipes show material icons and colored Have / Need quantities, compact prices omit redundant wording, and browsing position/quantity survive world updates. Armor gender, equipment bonuses and requirements are visible in the selected-item pane.

Version 0.14 fixes NPCs behind counters, including Marble: tap a visible shopkeeper, banker or skill master to open their native service without trying to walk through the counter. Selected skills take touch priority over the floating joystick, and ordinary entity taps use their rendered sprite position. Empty ground still activates the stick.

Version 0.10 fixes mid-step joystick release, moving-NPC rejection races and the extra walk-ACK wait before attacking. Movement and nearby actors use streamed native events with no periodic full-world refresh. A nearby **Pick up** button names the drop; native pickup acknowledgement updates its bag icon and corner quantity. An enlarged joystick captures dragging outside its circle and prevents accidental map taps. Fighting NPCs show a small, temporary health strip using native remaining-HP percentages. The HUD uses original Gold artwork. Broadsword, Ancient Sword, Battle Axe, Dragon Blade, Dark Katana and Ultima Blade have original four-direction character animations as well as bag icons.

Network switching uses a single-use in-memory proof to retire only the same account’s previous connection, followed by native password verification. Login code 5 means an account is already connected. A native password-hashing patch prevents bcrypt’s 72-byte limit from truncating the password behind a long runtime salt and username. Existing vulnerable hashes require operator recovery; character data is retained. See [server recovery](server/README.md#password-hash-upgrade-and-recovery).

Version 0.9 adds native **Buy / Sell / Craft** shops using the supplied original per-NPC prices and recipes. Tap a shopkeeper’s sprite to approach and talk; the shop shows your gold, held quantities, prices and recipe ingredients. Pickup uses native ownership, distance and weight checks. Bag stack quantities appear at the top right without shifting the item icon. **Person → Stats** uses original graphic 2:34 with the original attribute/combat/character layout, including Gold, EXP and EXP to next level; item details include bonuses, requirements and bag quantity. Other NPC services show an explicit unavailable message.

Version 0.8 adds solid NPC collision, held attacks about every 0.52 seconds online, visible HP/TP and incoming hits, and a clear death/respawn sequence. Open **Person → Stats** for the six original attributes, server-calculated combat totals, experience and earned stat points. Select equipment and choose **Details** to inspect its original bonuses and requirements. Stat spending, combat and equipment totals are authoritative server operations.

Version 0.7 uses 400 ms walking animations with a 420 ms input cadence, bounded local prediction and server reconciliation. Nearby characters interpolate and animate between server updates. Movement never waits for a full map refresh.

The bag always displays Gold, including zero. Repeated offline training drops add Daggers to a stack; equipping one reduces the stored stack by one. Online quantities come from actual server inventory and pickup acknowledgements. Wide Android screens show more of the world, with controls anchored inside the device safe area.

## Run a local server

After server setup and content import, start both the real server and its local protocol adapter:

```sh
python3 scripts/dev_online.py --device YOUR_ADB_DEVICE_SERIAL
```

The launcher reuses running local services or starts them, and adds `adb reverse tcp:8079 tcp:8079` for the selected phone. For the local server, change the hosted address to `127.0.0.1` and use port `8079`. Create your own account, create a character, select it and enter Aeven. Passwords are not stored on the device. New characters receive 1,000 Gold, a Dagger, an Oak Shield, matching peasant clothes in their bag, and learned Heal Self; equip them from the bag and remove them through the paperdoll. Accounts, inventory and online position belong to the real server database. Offline progress stays in a separate device save.

The adapter translates newline-delimited JSON into genuine encrypted EO v28 sessions; each client owns an independent native session. Movement animates immediately, with native Walk replies confirming inputs in the background. Nearby players, NPCs and ground items arrive as compact streamed changes; full refreshes are reserved for explicit actions and genuine corrections. This local development route needs the computer, server, adapter and ADB connection to remain available. The optional WebSocket bridge also permits `ws://` and `wss://` addresses. Browser exports require WebSocket transport; raw TCP is unavailable in a browser.

Server NPCs and drops replace the offline training slime online. Combat and equipment use server requests and acknowledgements.

## Local workspace

The current checkout is `/home/kc/workspace/Endless online`. All supplied archives and extracted resources are under `reference/`; earlier downloaded clients, sources, toolchains, Android test state and the native runtime are under `work/`. Both directories are ignored by Git. Compatibility symlinks at the previous task paths preserve existing artifact links and cached build paths.

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

The server binds only `127.0.0.1:8078` and does not advertise itself publicly. The Android client connects through the loopback adapter on port `8079`; port `8078` remains the native EO endpoint. See [server/README.md](server/README.md) and [server/VALIDATION.md](server/VALIDATION.md).

Server validation loaded all 282 numbered maps and 490 items / 302 NPC types / 31 spells / 8 classes. Generated syntax repairs permit 35 of 36 supplied quests to load; quest 17 is disabled pending an explicit content decision. Nine maps retain 58 chest-placement warnings. These are recorded content issues, not silently suppressed compatibility claims.

The supplied graphics and EODelta archives have also been inventoried; see [resource findings](docs/REFERENCE_IMPORT.md).

## Content pipeline and tests

`tools/import_eo.py` reads the preserved source ZIPs, decodes maps and PE graphics resources, exports the selected map and images, composes classic character animation frames, repairs selected WAV containers and records provenance. See [tools/README.md](tools/README.md).

```sh
python3 tools/test_import_eo.py
python3 scripts/test_client.py --godot /path/to/Godot
# Requires the actual running server and gateway:
python3 scripts/test_online.py --godot /path/to/Godot
```

Set `EO_DATA_DIR` for real-data importer tests if the source archives are elsewhere. The gameplay test exercises the actual scene through joystick press/drag/release, independent attack input, modal/focus cancellation, collision, combat, loot, equipment, save/load and reset. The wrapper uses temporary user data, so even a failing assertion cannot overwrite a real desktop save.

## Next milestone

Add the remaining NPC/guild/party services and quests, and audit the remaining legacy world-data errors. Extend remaining character services, reconnect/resume behavior, production account protection and capacity/abuse monitoring. The current online slice is an implementation foundation, not a complete MMO.

## Content rights

Original game content is used in local development builds. Original EO maps, graphics, quests and audio have not been established as licensed for publication in a new game. Obtain permission or replace them before distributing publicly. New code uses MIT; upstream software retains its original licenses. See [THIRD_PARTY.md](THIRD_PARTY.md).


Movement controls use the original four EO tile directions. Hold **WASD** or
**arrow keys** on a keyboard, or drag the large translucent dynamic joystick on
Android. Release to stop issuing steps. The joystick has no arrow glyphs, captures
its reserved bottom-left area above NPC targeting, and retains the finger during
long drags. Tap NPCs or target skills outside that area. Dialogs and chat typing
suspend movement.
