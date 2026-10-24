# Native feature completion — v0.40.0

All 15 numbered gaps in [the original audit](SERVER_CLIENT_GAPS.md) now have
server and client implementation paths. This release also repairs the audited
missing quest content. Classic graphics remain active.

## Where to find the features

1. **HP/TP drains:** native map damage updates self/peer feedback and current
   bars. Hall of Pain and other drain maps no longer retain stale TP/HP.
2. **PK combat:** native melee and offensive player-spell feedback includes
   damage, death, direction and caster TP. Opponent spells can target nearby
   players in native PK areas; the minimap title identifies those areas.
3. **Full skill/stat reset:** visit a skill master, open Skills → Reset all…,
   then confirm. Native points are refunded and learned skills/skill shortcuts
   are cleared; consumable shortcuts remain.
4. **Marriage/divorce:** tap Law Bob for named approval or divorce. Both
   approved partners visit a priest in the required outfits. The invitation and
   each vow have explicit prompts. Native fees, levels and partner checks apply.
5. **Town boards:** tap a board object to list/read/publish posts. Admins can
   remove posts subject to native permission. Rejected posts retain typed text.
6. **Jukebox:** tap its map object, choose a song and confirm payment. Native
   Gold acknowledgement precedes success; everyone on the map hears the track.
7. **Character deletion:** character selection → Delete selected…; type the
   exact selected name and confirm permanent deletion. Only owned characters
   may be deleted while outside the world; the native deletion ticket is used.
8. **Password change:** character selection → Change password. The native
   account service verifies the current password. Success clears saved login,
   automatic login, reconnect credentials and the old server resume proof.
9. **Emotes:** hamburger → Social / emotes / help → Emotes. Uses native emotes
   and the existing player-head renderer, including the sender.
10. **Whisper privacy:** the Social screen enables/disables incoming whispers
    through the native session setting. It resets on a new native login.
11. **Character books:** Social → My character book, or inspect a nearby
    player → Character book, to see native profile and visible completed quests.
12. **Admin help/reports:** Social → Contact admin / report player. Reports
    require a named player; messages go through native admin support. Requests
    have a 30-second cooldown and a 256-character limit.
13. **Find player:** Social → Find a player; results distinguish nearby,
    online elsewhere and unavailable without revealing hidden coordinates.
14. **Earthquakes:** native map effects produce bounded camera movement.
    Social → Reduce camera motion stores an accessibility preference locally.
15. **NPC speech:** native ambient and quest speech appears over its NPC and
    in nearby chat. The native quest engine now implements `AddNpcChat`.

The new service dialogs scroll, follow focused inputs and resize above the
Android keyboard. Account dialogs are drawn above character selection. World
service contexts bind to actual nearby NPCs or board/jukebox tiles; the gateway
does not grant native rewards, approvals, resets or items itself.

## Quest sources and new content

The supplied ZIP/7z resources and the original quest RAR were searched. The RAR
was extracted with `unar`: it contains 36 quest scripts. Neither it nor the
other supplied quest sources contained dialogue for vendors 13, 14, 24, 52, 53,
54 or 55. [The resource search record](validation/quest-resource-search-v0400.json)
records those results. Quest 56 was available and is restored separately.

The following are **new Aster Vale quests**, authored for this release, rather
than recovered original EO quests. Each has acceptance/cancellation, real item
hand-in, EXP/Gold rewards and native one-time completion history:

- Quest 13, Jessica (NPC 192, map 72): **A Little Kindness** — 1 Flower Bouquet;
  120 EXP and 40 Gold.
- Quest 14, Wolf Leader (NPC 193, map 117): **Bones for the Pack** — 3 Skeleton
  Bone; 400 EXP and 100 Gold.
- Quest 24, Pig Farmer (NPC 252, map 253): **Pest Control Supplies** — 3 Rat
  Tail; 180 EXP and 60 Gold.
- Quest 52, Royal Envoy (new NPC 305, map 281 at 5,8): **A Royal Offering** —
  2 Flower Bouquet; 300 EXP and 100 Gold. The King remains a combat NPC.
- Quest 53, Prisoner (NPC 300, map 10): **A Meal Behind Bars** — 2 Small Bread;
  150 EXP and 50 Gold.
- Quest 54, Shady Stefano (NPC 301, map 113): **Eyes in the Shadows** —
  3 Spider Eyes; 350 EXP and 90 Gold.
- Quest 55, Eddie Matador (NPC 302, map 49): **A Brave Entrance** —
  4 Spider Leg; 300 EXP and 80 Gold.

**Baru Supplies (original quest 56)** now has a daily Shepherd (NPC 303, map
34 at 20,21). Its original objective/removal mismatch is corrected: it consumes
5 Ice Cube (337) and 5 Ice Gem (338), and grants Baru Flock (new item **492**).
Original state names and daily reset are retained. The new Baru Tailor (NPC
304, map 5 at 37,46) crafts Baru/Baruta (430/431) for five Flocks and 10,000
Gold. Item **491 remains Skylar's 1,000-damage admin blade**.

Only the Shepherd and Royal Envoy gain configured ambient chatter. The change
does not manufacture ambient lines for every existing NPC.

## Reproduction and validation

- `server/test_feature_completion_state.py`: packet validation, drains/PK,
  account/context rejection, wedding prompts, quest item acknowledgements and
  text validation. All 135 `*_state.py` checks passed, with 21 additional
  regression unit checks, including content preservation, passing.
- `server/test_feature_content.py`: idempotent content installation and
  preservation of existing PUB entries, maps and admin weapon.
- `server/feature_native_probe.py`: **44 live native checks**, run in an
  isolated world using the binary built on the actual server host. Includes all
  seven new quest completions, speech and duplicate-reward prevention, Baru
  hand-in, actual HP/TP drains, melee/spell PK, both marriage approvals, real
  timed ceremony/vows, divorce and a full reset.
- `client/tests/features_live.gd`: **33 actual Godot/native UI checks**,
  including board posting/reading/moderation, social features, reset/shortcut
  clearing, keyboard fit, character create/delete and password change/login.
- Final client regressions passed: movement controls, mobile chests,
  disconnect recovery (23 checks), services/slots, and three-slot character
  selection/creation across four landscape sizes (153 checks).
- Screenshots of Social, board, reset and password dialogs were inspected.
  The public TLS WebSocket completed a native handshake and rejected account
  deletion/new services before authentication after rollout.

Evidence: [host native report](validation/native-features-v0400.json),
[client report](validation/client-features-v0400.json).
These checks use disposable test accounts in private worlds. They do not certify
every original map, quest branch, native combat formula or phone gesture.

Re-run the isolated combined native/UI scenario from the repository root:

```sh
python3 server/test_inn_citizenship_ui.py --scenario features \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --report work/features-ui-report.json
python3 -m unittest discover -s server -p '*_state.py'
```

## Installation and rollback

`server/setup.py` applies the NPC quest-chat and PK caster-feedback native
patches, then invokes the stopped-world content installer. For an existing
world, back up its runtime, account database, shortcut database and application
code, stop the services, install the matching native binary/Python modules and
run:

```sh
python3 server/configure_feature_content.py --runtime /path/to/runtime --world-stopped
python3 tools/sync_feature_content.py --runtime /path/to/runtime
python3 scripts/build.py android --release --toolchain work/toolchain
```

The installer preserves existing records and rejects occupied new IDs. It never
opens the character database. Do not run it against a running world. Exported
client catalog/maps must match the installed content before building the APK.
The hosted rollout used a native binary built on its Debian host; a binary from
a newer local glibc must not be copied there.

Hosted deployment succeeded with a stopped-world snapshot at
`/opt/aster-vale/backups/features-v0400-20261024T150519Z`. All three services and
public health/handshake checks passed. Account database bytes were unchanged by
the installer. To roll back, stop all three services and restore that snapshot's
runtime, previous Python modules and preferences together, then restart. A later
rollback of the saved database also discards subsequent player progress.

Android release: **0.40.0, code 66**, package `com.cloudgameboy.astervale`.
Signature and 16 KiB ZIP alignment checks passed. Existing signing identity is
retained; install with `adb install -r`, without uninstalling or clearing data.
APK SHA-256: `cb5b8cb2ef01403791e356fed5731253573adf8a15bac1f3bc00e250ed67641b`.
The release was installed on the Samsung SM-S918B through wireless ADB using
`pm install -r --user 0`. The installed APK hash matches the build and original
first-install times are preserved. The app process launched with no fatal,
script, parse or resource errors. The phone was locked during this last check,
so the new in-game screens were exercised in the isolated Godot/native tests.

The optional items outside the audit's numbered 15—extra admin buttons, pets,
rebirth and the paused enhanced-art experiment—remain separately scoped.
