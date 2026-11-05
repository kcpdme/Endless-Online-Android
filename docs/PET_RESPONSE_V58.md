# Pet targeting, action latency and joystick turning — Android 0.58.1

The November 5, 2026 update repairs companion facing and navigation, NPC/player
collisions, delayed actions after repeated turns, and joystick turn-before-walk.
Admin → Teleport adds **Mushroom Area (Centaur Approach)**, map 146 at 10,8.
The three hosted services have the server changes; Android version 0.58.1,
code 107 contains the client changes.

## Companion behavior

The native pet scans combat NPCs within seven tiles of its owner. It prioritizes
a recent commanded enemy, then enemies fighting its owner, then nearby aggressive
NPCs. All candidates must have a reachable adjacent attack tile. A single
25×25 bounded flood fill supplies routes for the candidates and owner following;
it can take a step away from an enemy to get around walls. Unreachable commanded
enemies permit a reachable nearby combat NPC as a fallback, including passive
Tentacles blocking the way on the Octopus map. Unprovoked passive NPCs otherwise
remain untouched. A combat NPC attempting to hit its living owner requests
protection even when that attack misses.

The pet faces its target before attacking. Companion updates now carry direction
and an explicit attack flag: NPC index zero is valid and must not be mistaken for
an upkeep notification. The adapter also accepts the earlier packet layouts and
infers facing from pet/enemy coordinates when possible. The client preserves
missing directions and uses the attack facing instead of a queued walking facing.
Damage, TP upkeep, collection recovery, rewards and PvP restrictions retain their
existing rules.

## Latency diagnosis

The live host had roughly 1 GiB of available memory, low CPU load and no active
swap or I/O wait in the sampled interval. The world process used approximately
23 MiB and the gateway 17 MiB. There was no evidence that another worker thread
or server capacity was causing the reported delay.

A reproducible queue problem existed instead: every native request first paid a
20 ms staging delay and then re-entered the queue with its gameplay delay. The
phone permits facing changes every 125 ms, while Face consumed 120+20 ms.
Repeated turns therefore accumulated work and delayed later attacks and pickup.
Packets now enter the queue once with their registered delay; execution still
checks state, timestamps, cooldowns, movement speed and queue limits.

Using the same disposable world and 64 direction changes at 125 ms intervals:

| Native acknowledgement measurement | Previous binary | Fixed binary |
| --- | ---: | ---: |
| Pickup after repeated turning | 1,327 ms | 161 ms |
| Archer hit immediately after a walk and face | 571 ms | 489 ms |
| Pickup while idle | 40 ms | 40 ms |

The second case deliberately requests the shot immediately after the walk
acknowledgement, while the normal movement cooldown still applies. Times measure
actual native damage/pickup, not just an adapter receipt. The public WSS path
measured approximately 286–323 ms round trip from this workstation; network
propagation remains in addition to native action timing. These measurements do
not promise identical timing on every phone connection.

## Collision and controls

The native world rejects ordinary and ghost walking onto an NPC. NPCs also
respect the origin of a player whose displayed step is still in progress. The
client reserves both ends of NPC walking animations and waits for native
acceptance on potentially contested steps; clear-area prediction remains instant.

Joystick input now uses the same turn gate as keyboard input: a new heading
turns a stationary player first, a continued hold walks after 200 ms, and input
already matching the facing walks immediately. Releasing a turn cancels the
pending walk. Direction changes during continuous walking chain at the next tile
boundary. The neutral touch-down, fixed/floating bases and classic/isometric
mapping remain supported.

## Original EO and other-game comparison

The checked-out EndlessClient at `d4764cb8b1bad6501c33f38a596d80d3d79c47bb`
implements this stationary turn-first distinction in
`EndlessClient/Controllers/ArrowKeyController.cs`, with a 200 ms input interval
in `EndlessClient/Input/InputHandlerBase.cs`. Its
`EOLib/Domain/Character/WalkValidationActions.cs` blocks NPC-occupied tiles.
This is an open-source EO client reference, not Vult-r's private server source.

[Guild Wars 2's pet documentation](https://wiki.guildwars2.com/wiki/Pets)
describes assisting the owner's target and defending the owner, with valid paths
required for attacks. The requested nearby-aggressive scan and crowded-target
fallback are Aster Vale's policy. [Original EO's NPC development post](https://www.endless-online.com/devpost/0458.html)
also describes bounded short-distance BFS among its navigation choices. Neither
source establishes the exact pet implementation of the private original server.

## Verification and deployment

- Native integration: 21 checks, including Banshi's four attack directions,
  autonomous aggression, passive protection, boxed-in Tentacle fallback, wall
  detours, NPC collision and post-turn latency. The previous binary fails the
  corresponding repaired behaviors and the turning-backlog threshold.
- Hosted machine: the 20-check pet/collision/attack/pickup suite passed against a
  disposable copy of the actual deployed runtime, without opening its player DB.
- Existing native EXP, explicit player ghosting and party reward regression:
  22 checks passed. Adapter state tests: 145 passed; admin tests: four passed.
- Godot: 180 actual touch traces covering both base modes, both direction modes,
  three frame rates, five landing positions and drag jitter; 32 heading/input
  cases; 18 collision/facing checks; continuous movement tests at 15–144 FPS.
- Public WSS: fresh test-account registration/login, character creation, Tutorial
  Island entry, stream, strike receipt and clean disconnect passed.
- The signed APK was installed through ADB, verified byte-for-byte, and retained
  Android's original first-install timestamp. The new admin destination was
  visible on the phone.

Deployment saved the old binary and adapter modules plus a stopped-world SQLite
backup under `/opt/aster-vale/backups/pet-response-v58-20261105T131044Z`.
All 413 checked runtime data/config files stayed identical. No player database
was replaced or edited by deployment. All three services passed health checks.
The detailed local receipts, logs and screenshots are under
`work/pet-response-v58/` and are excluded from source control.
