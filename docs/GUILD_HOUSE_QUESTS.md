# Guild-house layout and native quest journal

Version 0.37.1 / Android code 52. Same package and signing certificate.

## Guild Bob

The window's keyboard handler set its position to negative half-width/height.
Godot interprets that position relative to the parent, which moved the window
into the top-left corner and clipped most of it. The handler now updates the
centered anchor offsets instead, using the available safe-area height and
lifting the card above the keyboard. The content scrolls inside the visible
card. Earlier fixture checks did not run this per-frame handler; the updated
checks run it and require the complete card to stay inside the viewport.

The form signature is also recorded whenever a tab renders. An unrelated world
refresh no longer destroys the tab's input controls. Guild state refreshes do
not reopen an existing service over another screen; opening a fresh guild
context or receiving a new invitation still displays the window.

Native creation/recruitment rules remain in place: the hosted world requires
50,000 Gold and ten founding members; a recruiter must accept applications and
the guild bank pays the 1,000-Gold recruitment cost. Membership, ranks, Gold and
permissions remain native-server decisions.

## Quest journal

The parchment/check icon sits immediately to the left of chat. The skill book
moves one position further left. The icon uses the same 68-pixel circular touch
control as the adjacent controls; touch ownership prevents synthesized mouse
events from opening it twice or starting movement.

Ongoing and Completed tabs use native Quest_List requests (family 50, action 18,
pages 1 and 2). Ongoing rows show the native quest name, current objective and
progress/target when a numeric target exists. Completed rows show native
history. Open or Refresh fetches current server data. Empty lists have an empty
state; closing/back and late replies never reopen the journal. Logout clears
the cache before another character signs in.

Native quest-count headers include hidden/finished contexts that are omitted
from the rows. The parser reads delimiter-framed rows and publishes only a
complete valid response. Objective icons map native values 3/5/8/10 to the
original item/talk/kill/step images in GFX2:68. The atlas is exported by the
catalog tool or the standalone `tools/export_quests.py`. Original assets remain
excluded from Git. NPC conversations and reward choices remain separate.

## Validation

- 29 guild scene checks, including the running layout handler at four widths
  and bounds above a simulated software keyboard.
- Actual Guild Bob touch in native map 108, lookup feedback, form retention
  through a world refresh, Back and closed-window retention: 13 checks locally
  and on the hosted server.
- Full guild lifecycle in an isolated native world: creation/support/founding,
  recruitment authorization and bank charges, description/ranks, promotion,
  demotion/removal, private chat, leave and disband. The isolated test uses three
  founders; hosted settings and existing character data are untouched.
- 46 quest scene checks: four landscape sizes, icon spacing, native touch,
  progress/history, empty/error/loading states, Back, late replies and logout.
- Actual local/hosted native sessions display saved Pjedro objectives, Rat
  Problems at 3/20, Pirate Quest history and original icons through the HUD.
- 164 Python tests, including malformed/empty/hidden-count quest-list replies,
  atomic state updates, page validation and read-only requests while seated.
- Existing character creation, heal/party/Bard, Fairy Soda, shortcut, joystick,
  movement, combat, music/NPC-quest, audio, gameplay and world checks pass.

The quest-list API deploys only the gateway adapter. Its deployment report
confirms no active sessions at restart and no native-world restart. Local,
public, APK and phone JSON reports accompany this document.
