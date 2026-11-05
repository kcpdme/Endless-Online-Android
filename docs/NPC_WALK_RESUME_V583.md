# NPC clearance and held walking — Android 0.58.3

Holding a direction against an NPC previously waited for its full displayed walk
to clear the tile before sending a movement request. The nearby-NPC collision
guard then waited for native acceptance. Animation buffering and network latency
were therefore paid consecutively, making the character appear unresponsive even
after the road cleared. No explicit two-second input cooldown was present.

The client now sends a deferred step once the NPC's authoritative coordinates
leave the destination. It overlaps native confirmation with the departing
animation. An early acceptance keeps the player's sprite stationary and idle
until the NPC clears; movement then begins on the next frame. Late acceptance
still waits for the server. Only one contested step can be outstanding, and
rejected steps retain held input for retry. Solid terrain, occupied native NPC
tiles, player ghost rules, turn timing and walking cadence retain their checks.
Reconciliation replays only predicted steps: a delayed acknowledgement for an
earlier walk cannot start a later contested step before its own acceptance.
Release finishes only an already accepted step. Map changes, forced stops and
connection resets clear the presentation wait.

## Verification

- `client/tests/npc_walk_resume.gd`: 24 keyboard/joystick cases covering four
  directions at 30, 60 and 120 FPS; 120 assertions. The previous client fails all
  24 departure-request cases. The updated client checks early request, no overlap
  before clearance, no duplicate request, first-clear-frame movement without
  accumulated time, and release after acceptance.
- Collision suite: 24 checks, including native rejection presentation, earlier
  and late acknowledgement cases, player ghost timing and NPC facing. Movement reconciliation, continuous movement
  at 15–144 FPS, 32 turn/input combinations, and 180 joystick touch traces pass.
- Signed Android 0.58.3, code 109, exported successfully.

## Bone Spider investigation

The deployed map 102 contains exactly one natural Bone Spider (NPC 183), centered
at 40,40, with a 375-second respawn timer. Admin warp lands at 40,35. Its graphic
125 has 28 nonempty idle, walk and attack frames across all four directions.

`server/test_bone_spider_live.py` starts a disposable native world, enters at the
admin landing, verifies the natural NPC in the native snapshot, kills it and
observes the same spawn return. This passed both locally and on the host using
the deployed binary and a private copy of its actual runtime. The private test
sets SpawnRate to 1% to exercise the 375-second record without a six-minute wait;
map geometry, spawn records and NPC definitions remain byte-identical. Production
settings and its player database are not changed or opened by the test.

No missing-spawn or missing-art defect was found. After a kill, the live respawn
interval is approximately 6 minutes 15 seconds, with whole-second death timestamps
and spawn polling affecting the precise time. Native idle NPC
movement has no home leash, so a surviving Bone Spider can wander away from the
central landing on this 81×81 map. The audit does not establish its position or
remaining respawn time inside the already-running production process.

Local diagnostic logs and the host test receipt are under
`work/npc-walk-resume-v583/` and are excluded from source control.
