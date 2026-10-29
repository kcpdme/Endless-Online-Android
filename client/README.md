# Aster Vale client

Godot 4.7.2 Compatibility-renderer Android client for the authoritative native
EO world, connected through the Python/WebSocket gateway. Open `project.godot`
and run `main.tscn`, or use `python3 scripts/build.py android --release`.
Original content remains development reference; see the root provenance notes.

## Play

Sign in or create an account on the full-screen welcome page, then select one
of three character slots. New characters choose body, skin, hair and hair color.
Remember login and automatic login use the Android Keystore. Server loss blocks
world input immediately, retries the same character, then returns to login if
recovery fails. Normal play requires a server connection.

Drag the joystick or tap clear ground to walk; desktop supports WASD/arrows.
Touch-down is neutral. Menu → Movement controls offers classic/isometric mapping
and floating/fixed circles. Release finishes the committed online tile. Another
finger can attack while moving. Opening a modal or losing focus cancels movement.

The top magnifier switches between Normal and 125% world views and remembers the
choice on this device. Incoming messages and NPC information show in the compact
chat feed for eight seconds; typing or scrolling keeps it open. Its down arrow
hides the feed immediately. Conversations retain the full history, and the
message composer stays available when the feed is hidden.

The bag, paperdoll, skills, messages, quest journal, party and admin controls are
available from the HUD. Admin controls are visible only to native admins; actions
are validated on the server. Nearby NPCs and world objects open native services.
The hamburger menu fills the screen and includes Social / emotes / help, login
settings and movement controls. See [the v0.40.0 guide](../docs/FEATURE_COMPLETION.md)
for boards, jukeboxes, marriage, profile books and other restored features.

Character stats, equipment, inventory, quests and four combat shortcuts are
server-authoritative. Device preferences and secure login credentials remain on
the device. Enhanced player, item and NPC art is active by default; Menu → Graphics
offers a Classic fallback.

## Structure and testing

- `scripts/main.gd`: world rendering, input, movement, HUD and event routing.
- `scripts/online_controller.gd`: gateway session and native world state.
- `scripts/native_features.gd`: restored service, social and account screens.
- `scripts/character_flow.gd`: three-slot selection and appearance creation.
- `content/`: generated importer output, including catalog, maps and art.
- `tests/`: isolated state, input, layout and native integration checks.

Run client checks with an isolated user-data directory. For example:

```sh
python3 scripts/test_client.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
python3 server/test_inn_citizenship_ui.py --help
```

The latter includes the `features` scenario and runs a private native world,
gateway and actual Godot UI without changing production accounts.
