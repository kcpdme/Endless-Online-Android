# Mobile admin tools

The crown beside Party opens a centered Admin dialog. Only an online character
whose native Welcome reports an admin role sees the icon. Native touch and mouse
handling consume the tap before world healing targets; opening cancels movement
and armed targeting. Back closes the dialog. Logout and disconnect clear its state.

Teleport is the first tab. Its server-owned presets are:

| Destination | Map | X | Y |
| --- | --- | --- | --- |
| Apozen | 119 | 24 | 29 |
| Apozen Overlord | 136 | 49 | 18 |
| Wraith Room | 277 | 11 | 31 |
| Reaper Cave | 109 | 7 | 13 |
| Octopus | 155 | 8 | 11 |
| Monkey Island | 271 | 25 | 54 |
| Pyramid | 229 | 82 | 112 |
| Admin Room | 21 | 12 | 6 |
| Anundo | 161 | 32 | 36 |
| Atlantis | 255 | 12 | 19 |
| Kingworms Room | 229 | 20 | 20 |
| Sky Haven | 71 | 34 | 14 |
| Dragon Cave | 270 | 8 | 14 |
| Aeven | 5 | 40 | 40 |

Anundo uses the town landing outside its inn. Atlantis uses the original
arrival from Atlantis Pathway, on the first Atlantis map. Reopen the Admin
menu to fetch these server-supplied entries; no APK update is required.
Kingworms Room lands directly inside the pyramid's King Wurm chamber, separate
from the existing Pyramid entrance preset. Sky Haven uses the Sky Wonder map's
original arrival from Phoenix Field.
Dragon Cave uses its original entrance from map 269; its native map title is
Atlantis Pathway. Aeven lands in the open town centre.

These tiles are walkable, outside portal tiles and fixed monster spawn centers.
Monsters can still attack an admin at these destinations. Add future destinations
to `server/admin_actions.py`; clients render the returned list.

Item grants exactly one item to the bag using a positive native EIF ID. Spawn
creates exactly one temporary native NPC at the character's location (native
placement may move it nearby if occupied), using a positive ENF ID. There is no
free-form command field, arbitrary teleport coordinate, quantity or client role.

The typed gateway operations are `admin_open`, `admin_teleport` with a destination
key, `admin_item` with an integer `item_id`, and `admin_spawn` with an integer
`npc_id`. Every operation checks the session's native admin role. Command rank
configuration and local overrides are read from native configuration. The world
executes its existing `warp`, `sitem` and `snpc` commands, retaining final native
rank and duty checks (Welcome can advertise an elevated role for client features).
No character privileges, command permissions or world databases are rewritten.

Success requires a native map completion at the preset coordinates, an Item_Get
with UID zero and the expected ID/quantity, or a new Range_Reply NPC appearance.
Busy controls prevent duplicate submissions. Native refusal, invalid IDs, movement,
casting, trade and transition errors leave the action unconfirmed. There is no
automatic mutation retry.

Validation: `python3 -m unittest test_admin_actions -v` from `server`, plus the
isolated real-client integration:

```sh
python3 server/test_inn_citizenship_ui.py --scenario admin \
  --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --report work/admin-live-report.json --screenshots work/admin-screenshots
```

The integration checks cover all fourteen native teleports, one acknowledged item,
NPC spawning, invalid IDs, touch ownership with an armed heal, dialog bounds at
1280×720 and 1544×720, Back/logout, and a separate regular account attempting all
four operations with a forged admin field. All fixtures use disposable accounts
and an isolated native runtime.

Anundo and Atlantis validation reports: `admin-ten-native-ui-report.json` and
`admin-anundo-atlantis-deployment-report.json`. The latter records the live
source hash, backup, health check and unchanged native-world identity.

Kingworms Room and Sky Haven validation reports:
`admin-twelve-native-ui-report.json` and
`admin-rooms-deployment-report.json`.

Dragon Cave and Aeven passed 70 isolated native/client checks across all fourteen
destinations. They are deployed on the hosted gateway; the world process and
database were left unchanged. See `admin-fourteen-native-ui-report.json` and
`admin-dragon-aeven-deployment-report.json`.
