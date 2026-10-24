# Endless Online Android

A first playable foundation for an independent Endless Online–inspired Android game, using Godot 4.7.2, typed GDScript, and 2D isometric rendering. The current app's working title is **Aster Vale**. This is an independent project, not an official Endless Online release.

This public repository contains source code, content import tools, build scripts and server setup. **Original EO assets, reference downloads, APKs, signing keys and personal game saves are not included.** Supply content before running or exporting the client; see [local content setup](client/content/README.md).

## Play the Android build

After importing content and building, install `builds/aster-vale-debug.apk` on an Android device (Android 7 / API 24 or later). This development build includes ARM64 and x86_64. Open **Aster Vale**, log in, select your character and join the persistent shared world. The build is signed with a development key, not configured for Google Play release.

The current Android package is **`com.cloudgameboy.astervale`**, version 0.39.1
(code 57). It installs separately from the earlier `io.astervale.prototype` app;
online accounts remain on the same server. Release APK and AAB exports use the
same private release signing key.

The app starts directly on a full-screen account login/create screen with
original EO title artwork. On Android, **Remember login on this device** saves
a successfully verified login in an Android Keystore-encrypted, backup-excluded
vault. **Forget saved login** removes it. Changing the account/server clears the
prefilled password. Saving is optional and off by default.

The player entry flow is online-only. Character selection shows each character's
native skin, body, hairstyle, hair color and equipped boots, armor, helmet,
shield and weapon. Full-screen selection has three large slots; empty slots open
full-screen creation with Male/Female, skin, hair and a rotating preview.
Tap a card, then enter the selected character.

Character-art development uses [separate reversible packs](client/art_packs/README.md).
Classic assets remain intact; painted drafts live in `client/art_packs/painted_v1/`
and are excluded from exports. Menu → Graphics can select a completed Enhanced
release or restore Classic immediately. Enhanced is unavailable until a complete
appearance is ready; unfinished combinations fall back to Classic together.

- Drag the lower-left joystick to move; tap clear ground to walk there.
- Tap the weapon for manual attacks; hold to latch auto attack and tap to stop.
- The bag and character icons open native inventory and equipment.
- Tap Babs in Aeven’s hair salon to preview a haircut/color and confirm its
  native Gold price. Tap road signboards to read their original text.
- Two consumable and two skill shortcuts save per character on the server.
- Targeted healing shortcuts let you tap yourself or another player in the world.
  Group Heal and Aura cast directly on your native party. Bard opens a 36-note instrument keyboard.
- The parchment icon beside chat opens native ongoing quests and completed
  history, including objectives and available progress counters.
- **Menu → Party** manages invitations, members, party chat and leaving.
  Inspect another player to invite them. The leader can remove members;
  leaving as leader disbands the party after confirmation.
- **Menu → Log out** ends the online session. There is no offline-play or reset
  control in the player flow; existing legacy local saves are left untouched.

Install signed updates with `python3 scripts/install_android.py`. It uses a full
APK update (`--no-incremental -r`), verifies installed bytes and version, and
checks that Android kept the app's original installation timestamp.

## Play online

Version **0.39.1** restores Classic character graphics after the painted pilot
review. Painted assets are excluded from exports, and a saved Enhanced choice
returns to Classic. The experimental artwork and code are archived for future
animation work. See [Classic restoration](docs/GRAPHICS_CLASSIC_ROLLBACK.md).

Version **0.38.2** restores Ancient Wraith's original transparent idle/walking
frames and visible attack artwork. It removes the gold missing-art ball in
both Classic and Enhanced character-graphics modes. See
[original Wraith verification](docs/ANCIENT_WRAITH.md).

Version **0.38.0** adds the native Aeven haircutter, working map signboards,
direct full-screen account entry with original EO artwork, and optional secure
Android saved login. See [haircutter, signs and login verification](docs/BARBER_LOGIN_SIGNS.md).

Version **0.37.1** fixes the guild-house window being clipped into the top-left
corner when its keyboard layout handler runs. Guild forms also survive world
refreshes. A parchment icon beside chat opens the original native quest
progress/history list, with saved objectives, counters and original icons. See
[guild-house and quest-journal verification](docs/GUILD_HOUSE_QUESTS.md).

Version **0.37.0** expands login and creation to full-screen layouts, with three
large native character slots and original body, skin, hair style and color
choices. All normal friendly heals default to world selection: tap the skill,
then yourself or another player. Heal Self stays immediate. Bard music emotes
now preserve speech bubbles, including Fairy Soda hiccups and haze. Small and
Big Soda behavior was checked with two native clients on the hosted world. See
[character flow and Fairy Soda verification](docs/CHARACTER_FLOW.md).

Version **0.36.0** completes native party invitations/joining, membership, HP,
EXP/level-up handling, party chat, leaving and leader removal. Group Heal and
Aura heal party members through native acknowledgements. Targeted heals use
native player IDs (v0.37.0 defaults to world selection). Bard plays the 36 original notes for the equipped Harp or Guitar,
locally and for nearby players. Login cards render actual native character
appearance and equipment. The entry flow is online-only. See
[party, healing, Bard and login validation](docs/PARTY_HEAL_BARD.md).

Version **0.35.2** saves the two skill and two consumable shortcuts on the server
for each character. Existing local choices migrate on first login; a fresh install
restores server choices. Empty slots and depleted consumables remain assigned as
chosen. Interrupted saves retry from a local pending record without reverting a
newer selection. See [shortcut persistence](docs/SHORTCUTS.md).

Version **0.35.1** fixes wrong-direction joystick starts. Both bases stay neutral on touch-down and choose movement from the drag. Joystick drags walk immediately without the old 80 ms turn hold or an extra Face request; keyboard turn timing stays classic. Straight up/down/left/right input is stable in isometric mode too. See [startup regression evidence](docs/MOVEMENT.md#version-0351--code-48-correct-and-immediate-touch-starts).

Version **0.35.0** improves phone movement: 80 ms touch turn holds, a smaller start dead zone with a separate stop threshold, and shorter long-drag reversals. Open **Menu → Movement controls** to choose classic/isometric steering and a floating/fixed joystick base. Choices save on the device. Keyboard turn timing and native 420 ms walking stay unchanged. Floor rendering now visits bounded viewport tiles. See [movement implementation and validation](docs/MOVEMENT.md#version-035--code-47-mobile-controls).

Version **0.34.0** completes Guild Bob and Guild Master services: information/member lookup, founding invitations and confirmation, joining through a recruiter, deposits, descriptions, nine rank names, promotions/demotions, member removal, leaving, disbanding and private guild chat. Original server costs, founding-member requirements and permissions apply. Invitations and applications arrive through native events. Destructive actions and Gold payments require confirmation in the UI. The earlier [mobile movement audit](docs/MOVEMENT_MOBILE_AUDIT.md) explains the comparison with classic EO and the reasoning behind v0.35.0.

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

The world pack now includes all **282 maps**, 3,945 original warp records and their graphics. Walking into a valid exit changes the rendered map only after the real server completes its warp handshake. Doors open through native EO requests; keys and level restrictions remain server-controlled. Eight malformed legacy warp destinations on map 47 are blocked rather than sending a player outside a map. Gold banking, item lockers, equipment inspection, player trading and nearby/global/private chat now use the original native server flows. Tap a banker, a nearby locker, or another player to interact. The mobile HUD uses HP hearts and blue TP orbs with a dynamic floating joystick. It also shows the current level and a thin next-level EXP bar. The bag supports native potion/scroll use; Nearby chat closes on Send. Two touch skill shortcuts and a skill book use native learned spells. Tap an attack skill, then a monster anywhere on the screen, including the joystick area; Heal Self casts immediately on yourself. The book shows TP, chant time, skill level and original learning requirements. Tap a skill master to learn or forget; spend skill points with Train +1. Original spell icons, chanting poses and effects are rendered for you and nearby players. PvP targeting and additional NPC services remain future work. Character creation offers male/female bodies, 20 hairstyles, 10 original hair colors and the native creation skins (White, Tan, Pale, Orc), with a rotating preview.

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

For signed release files, supply a private signing JSON containing `path`
(keystore), `alias` and `password`. Keep that file and the keystore outside Git.
The default location is `<toolchain>/release-signing.json`:

```sh
python3 scripts/build.py android --release --toolchain work/toolchain
python3 scripts/build.py android-aab --toolchain work/toolchain
```

Outputs are `builds/aster-vale-release.apk` and `builds/aster-vale-release.aab`.
The AAB build installs the pinned official Godot Android source template and
uses Gradle. `--signing-config /private/path/signing.json` selects another
existing signing configuration. Reuse the same key for future updates.

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
