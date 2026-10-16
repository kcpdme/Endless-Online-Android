# Movement regression and v0.7 correction

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
measured runs, not a guarantee for every phone or network. The new client uses
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
