# Movement behavior and regression history

The original-style path does not request a full map refresh every step. This was
verified in the supplied 2012 EODelta server `src/handlers/Walk.cpp`, the pinned
etheos runtime, and Ethan Moffat's open-source EndlessClient (not the proprietary
original Windows executable).

- [EndlessClient CharacterActions.Walk](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EOLib/Domain/Character/CharacterActions.cs): sends direction, timestamp and expected destination, without requesting Refresh.
- [CharacterAnimator.StartMainCharacterWalkAnimation](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/Character/CharacterAnimator.cs): starts local animation alongside the send, without waiting for an acknowledgement.
- [WalkReplyHandler](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EOLib/PacketHandlers/Walk/WalkReplyHandler.cs): updates newly visible entity IDs and items.
- [WalkPlayerHandler](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EOLib/PacketHandlers/Walk/WalkPlayerHandler.cs): animates another character from a compact movement event.
- EODelta Walk handler: calls Refresh when server coordinates disagree with the client's expected destination. The currently deployed etheos also refreshes a rejected step. Both register a 0.4-second walk action.
- etheos Map::Walk: sends a five-byte movement payload to nearby players and a two-byte successful walk-reply payload to self, plus newly visible items/entities as needed. These lengths exclude packet framing and encryption. They are not the full map file or a full visible-world snapshot.

The v0.6 adapter added `sleep(0.07)` and `refresh()` to every walk. Refresh then
waited behind the native 400 ms action cooldown. The Godot client additionally
waited for that response before starting its animation, blocked input while
any RPC was pending, and refreshed the world every 600 ms. Nearby actors were
rendered as idle sprites from these periodic snapshots.

The host was lightly loaded (load average about 0.1, about 1 GB available RAM,
world process about 20 MB RSS). Extra server capacity would not remove these
serialized waits. No C++ world-server rewrite or machine upgrade was required.

Version 0.7 adds an asynchronous movement operation, positive native Walk_Reply
confirmation, compact entity deltas, full-duplex WebSocket forwarding, immediate
Godot prediction with reconciliation, and independently interpolated walking
animations for nearby players and NPCs. Full refresh remains available for
correction, explicit actions and legacy clients. Version 0.10 removes the idle recovery timer. Native EO still
validates collision, movement rate, inventory and map transitions.

A 60-FPS real Godot scene was driven with a held joystick for 14 seconds through
the public trusted-TLS endpoint. Before: 11 steps, 905 ms initial delay and
1,258 ms mean step interval. After: about 33 inputs, approximately 17 ms initial
visual response and 433 ms between steps. The native confirmation sequence was
allowed to settle, then client/server map coordinates were compared. These are
measured runs, not a guarantee for every phone or network. The v0.7 client used
400 ms animations and a 420 ms input cadence; display-frame scheduling adds a
small interval. A blocked tile can still produce a server correction.

Checks include the real streamed walk ACK, an independent observer receiving a
peer movement without Refresh, NPC movement pushes, incorrect-coordinate
correction, a real rejected step, burst delivery of outstanding movement,
Aeven/map4 round-trip with EMF identity checks, legacy RPC compatibility, the
Godot reconciliation regression, public WSS login/movement/equipment, offline
save isolation, offline gameplay, inventory quantities and full-screen layout.


## Version 0.10: release, moving targets and collection

Three further client/adapter regressions were reproduced. Releasing the stick
froze the sprite between tiles even though the predicted tile was already
committed; a later ten-second idle Refresh exposed the mismatch. The adapter
also rejected a predicted step if a moving NPC had entered that tile by packet
arrival. Original EndlessClient checks NPC occupancy locally; native etheos
`Map::Walk(Player)` checks terrain and player occupancy. Finally, attack waited
for an outstanding Walk ACK after the visual step had finished, adding a round
trip while chasing a rat.

Release now clears future movement and finishes only the committed online tile.
Native Walk/Attack queue order replaces the extra ACK barrier. Client-side NPC
collision remains, and the adapter no longer adds a second moving-NPC check.
Ordinary world events drive updates; there is no periodic full-world Refresh.
Real terrain/player collisions still require native corrections.

Collection intent now survives movement and its ACK. A named Pick up control
uses the original UID, distance-two and ownership rules. The new asynchronous
collect operation returns a receipt immediately; only native Item_Get updates
the bag and quantity. A rejected protected/overweight pickup expires as a clear
feedback event without blocking movement or NPC packets.

A real Godot touch test with injected 120 ± 80 ms delay in each direction passed
eight steps, mid-step release, Rat Tail pickup, visible bag icon/quantity and
eleven idle seconds with zero corrections and zero native Refresh packets. A
separate 300 ± 150 ms-per-direction test chased and killed an actual Rat,
including an attack before the walk ACK, without a chase Refresh or correction.
These controlled results do not remove real mobile network latency.

The design follows [Gambetta's prediction/reconciliation explanation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
and [entity interpolation](https://www.gabrielgambetta.com/entity-interpolation.html):
render local movement immediately, discard only acknowledged inputs, replay
outstanding inputs and interpolate other actors independently.


## Version 0.24 / code 26: continuous walking at the effective native pace

The v0.23 build still paused between tiles. A real rendered two-session test
measured a mean **433.76 ms** between step starts. A held direction accumulated
about **62.64 ms stationary time across two tile transitions** (usually four
stationary frames at 60 FPS). The 400 ms animation finished before the separate
420 ms walk gate, and that gate was decremented by a child node after the main
movement update. Discarding animation time beyond a tile boundary added further
frame quantization. Restarting the animation clock per tile interrupted gait.
This was a client scheduling regression, not evidence of an overloaded host.

The pinned etheos Walk handler and the supplied EODelta handler both register
400 ms actions. The deployed etheos first auto-queues every incoming packet with
a 20 ms dispatch stage (`EOClient::Execute` / `eoclient.cpp`); the handler
register then queues its Walk action. Sustained walking therefore needs about
420 ms per tile, not just the handler's 400 ms. A 400 ms client initially looks
smooth but gradually fills the bounded prediction queue. The sustained test
was extended to 84 uninterrupted steps to catch that drift. EndlessClient's CharacterAnimator queues/replays continued
walking directly at the boundary rather than displaying an idle pose between
steps. Its source has five walk states (standing plus four poses), with nine
10 ms ticks per frame; that is not the same as the server action queue interval.
This build uses **420 ms per tile / about 2.38 tiles per second**, aligned to the deployed
native server, while retaining that uninterrupted replay behavior.

- The committed local animation is the movement clock. There is no second
  cooldown. A continued step starts in the same frame and receives the leftover
  frame time; walking poses keep their phase and complete a cycle per tile.
- A release stops future input and finishes only its committed tile. Attack
  recovery, doors/warps, four outstanding predictions and server corrections
  still gate movement. No full-world refresh or ACK wait was added.
- Nearby players/NPCs queue adjacent confirmed steps at fixed speed instead of
  re-interpolating from a fractional position whenever a packet arrives. A
  100 ms presentation buffer absorbs ordinary packet jitter; it does not delay
  local input. Each displayed step uses its own direction. Numeric JSON IDs
  are normalized so sprites, speech bubbles and hit testing share the same track.
  Tracks are bounded
  and pruned, and spawns/warps/nonadjacent updates reset them. Unreceived future
  movement is never extrapolated through walls. Severe network stalls can still
  exhaust the buffer and require authoritative correction.
- The Python adapter retains its existing 0.42-second metadata and 42-tick
  native timestamps. An intermediate 0.40-second experiment was restored after
  tracing the dispatch stage; hosted files were backed up/hash-checked and now
  match their prior Git versions. Gateway/WebSocket services were restarted;
  the C++ world and operator data were unchanged. Other players need this APK
  to use the new rendering.

`movement_timing.gd` tests the actual local movement at 15, 24, 30, 59, 60, 90,
120 and 144 FPS, including frame rates that do not divide a tile duration evenly.
It checks constant position/velocity, no stationary frames, continuous pose
phase and release. Deterministic remote delivery with up to about 80 ms jitter
checks constant motion, queued facing, final stop, warp reset and cleanup.
`movement_controls_live.gd` measures all eight keyboard keys and four joystick
directions, followed by two 12-tile holds and an 84-tile continuous return path,
using two real native
sessions. The observer must remain within EO's visibility range: fixtures are
on map40 at (20,10) and (26,12). An observer at (20,14) loses sight of the
12-tile endpoint, which is expected visibility behavior, not a movement failure.

Evidence: `movement-v26-baseline-report.json`, `movement-v26-timing-report.json`,
`movement-v26-live-report.json` and `movement-v26-public-report.json`. The local live run
asserts zero stationary frames on both rendered tracks. The public WSS run
asserts zero local stationary frames, matching native endpoints, stop after
release and zero corrections, and records remote gaps as WAN measurements
(`remote_strict_jitter_assertions=false`). A public packet stall longer than the
100 ms remote buffer can still interrupt the observer; the deterministic
jitter test and local live run separately verify the interpolation itself.
Operator accounts are never used for these tests.

A read-only host check during validation showed load averages0.26/0.13/0.09,
about1087MiB available memory and native world RSS25496KiB. These observations
and the reproduced client timing fault do not justify a server upgrade.


One public run overlapped an81MB wireless ADB installation and recorded a
network stall: the four-prediction cap was reached, with104 local stationary
frames and175 observer idle frames over84 completed steps. The transfer may
contribute to Wi-Fi latency; it is not evidence of native CPU saturation.
`movement-v26-congested-wifi-report.json` retains that result. Keep network
validation separate from APK transfer, and do not enlarge the prediction queue
or overclock movement to hide a stalled connection.


After the wireless transfer finished, the isolated public84-step run measured
420.06ms average step starts, zero local stationary frames and zero native
corrections. Its observer recorded14 idle frames over that sustained walk;
real WAN jitter can still exceed the100ms buffer. The local two-session
84-step run recorded zero idle frames for both tracks. These results distinguish
the fixed per-tile scheduling bug from occasional network delivery gaps.
