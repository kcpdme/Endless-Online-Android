# Mobile movement audit — 23 October 2026

Implementation update: v0.35.0 applies the shorter touch turn hold, threshold/reversal improvements, optional isometric/fixed controls and bounded floor traversal. See [implementation evidence](MOVEMENT.md#version-035--code-47-mobile-controls). The analysis below records the behavior before those changes.

The next improvement should be touch responsiveness and steering clarity. Keep the native four-direction tile movement and the current 420 ms walking cadence. The current code already chains walking smoothly; its touch controls deliberately inherit keyboard behaviors that can feel slow or indirect on a phone.

Movement was analysed only in this change. No joystick, movement timing, collision, prediction, or camera behavior was changed.

## What “original Endless” means in this comparison

The proprietary original Windows client was not instrumented. Evidence comes from the supplied EODelta Walk handler, pinned etheos server, and the open-source EndlessClient implementation at commit `d4764cb8b1bad6501c33f38a596d80d3d79c47bb`. These establish native protocol behavior and a reference implementation; they do not establish exact original executable touch behavior or timings. The original desktop controls do not supply a mobile joystick specification.

- [ArrowKeyController](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Controllers/ArrowKeyController.cs) turns a standing character before walking, continues turns at walking boundaries, and validates the next tile.
- [InputHandlerBase](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Input/InputHandlerBase.cs) uses a shared 200 ms keyboard-input interval. The current game's dedicated 200 ms turn timer approximates that result; it is not an identical input scheduler.
- [CharacterAnimator](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/Character/CharacterAnimator.cs) and [CharacterActions](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EOLib/Domain/Character/CharacterActions.cs) support immediate local animation and compact walk packets rather than a full-world refresh per step.
- The local pinned etheos Walk handler registers a 400 ms action, preceded by its 20 ms packet-dispatch stage. The existing 420 ms cadence matches the effective sustained pace of this server configuration. It is not a claim that every EO server or client must use 420 ms.

## Findings and proposed order

### 1. Shorten the mobile turn-to-walk delay

`main.gd:_manual_step` gives joystick and keyboard the same turn-first behavior. When standing and selecting a different heading, it turns immediately but requires another 200 ms hold before walking. A shorter gesture can rotate the character without moving at all. The delay comes after crossing the joystick dead zone, so the physical thumb motion adds more time. Same-heading movement and tap-to-walk routes bypass this turn delay.

This is the strongest code-based explanation for movement feeling hesitant when starting or making small adjustments. The fresh `short_movement.gd` run confirms the behavior in all 32 starting-heading/input combinations.

**Proposed first experiment:** keep the existing keyboard behavior; on touch, test 60–100 ms turn holds, starting at 80 ms. Preserve a small deliberate turn-only gesture for combat facing. Also compare immediate touch walking as an optional mode. Do not change native movement speed. The proposed timings are usability experiments, not measured optimal values.

### 2. Make the joystick's direction match what the player sees

`joystick.gd:_snap_direction` selects a cardinal input axis, which is then interpreted as an EO tile axis. The actual screen projection in `main.gd:tile_position` is isometric. At zoom 1:

- Drag right → tile `(1, 0)` → screen down-right `(32, 16)`.
- Drag down → tile `(0, 1)` → screen down-left `(-32, 16)`.
- Drag left → tile `(-1, 0)` → screen up-left `(-32, -16)`.
- Drag up → tile `(0, -1)` → screen up-right `(32, -16)`.

A circular analog-looking control therefore behaves like four keyboard buttons, while the visible character moves diagonally. This can feel indirect even with perfect network conditions. Straight screen-horizontal movement cannot be produced by a single native tile direction.

**Proposed experiment:** offer an isometric touch mode that chooses among the four projected travel directions, with subtle selected-sector highlighting. Keep the current mapping available for existing players. Retain four native directions and collision rules; do not alternate tile axes automatically to simulate free analog movement. Test corner approaches and combat facing before choosing a default.

### 3. Make small reversals and starts easier

The current dead zone is 18 logical viewport pixels, against 84 pixels of maximum input displacement: about 21% of the stick's input radius. Direction switching has a 1.25 dominance ratio. That creates about a 12.7° hysteresis band around diagonal input boundaries, which is useful for preventing chatter.

The floating origin follows a long drag. Once the finger is 84 pixels from that origin, a complete reversal must travel back through the center and past the opposite 18-pixel dead zone: just over 102 logical pixels before the opposite direction is selected. The drawn circle has a 128-pixel radius, but that is not the input travel radius. Near screen edges the displayed center is clamped separately from the input origin, which can make the knob and finger relationship less obvious.

**Proposed experiment:** add a fixed-base option, test a 12–16 pixel activation threshold with a smaller release threshold, and keep modest directional hysteresis. Ensure the displayed center and logical origin remain consistent during long drags near edges. Recheck accidental movement and jitter before reducing thresholds globally. These distances are canvas coordinates, not measured physical millimetres on a phone.

### 4. Preserve committed-tile movement, but explain stops better

A release finishes the current online tile and clears future input. Likewise, a new direction while moving takes effect at the next tile boundary. Each can take up to the remaining portion of a 420 ms step. This is expected grid movement rather than an extra input/ACK delay.

**Proposed improvement:** show the selected next tile or chosen direction subtly while the finger is held. Verify that release clears queued intent immediately and that the latest deliberate heading wins at the next boundary. Avoid stopping halfway through an already committed online step; that would separate the displayed and authoritative positions. Prioritize shortening the initial touch-turn delay over trying to cancel committed steps.

### 5. Profile frame pacing and network stalls separately

Fresh deterministic engine tests pass continuous local motion at simulated 15, 24, 30, 59, 60, 90, 120 and 144 FPS, with zero stationary simulation frames. Controlled remote delivery with roughly 80 ms timing variation also passes. These tests validate interpolation and time accounting; they do not measure actual Android frame presentation or touch-to-photon latency.

The renderer still scans the full map grid before culling tiles, scans decorations and sorts visible entities each draw. On Aeven's 87×87 map that means 7,569 floor-candidate checks per frame. Texture loading is cached, but the first appearance of an uncached asset loads synchronously. These are profiling candidates, not established causes of the reported phone experience.

The client limits outstanding predicted moves to four, equivalent to 1.68 seconds of issued steps at this cadence. A stalled connection can fill that limit and pause movement. The 100 ms remote-actor buffer can also empty, affecting other players' animation independently of local input.

Earlier stored evidence distinguishes these cases: the isolated public 84-step run recorded zero local stationary frames and 14 observer idle frames; the run overlapping a wireless APK transfer recorded 104 local stationary frames and reached the prediction cap. These are historical measurements, not a fresh test of today's hosted connection.

**Proposed profiling:** record input-to-first-motion latency, turn-to-walk latency, wrong-direction corrections, release-to-rest time, p50/p95/p99 frame times, cold texture loads, pending-move depth and walk-ACK latency. If rendering spikes correlate with hesitation, first restrict floor traversal to visible tile bounds, cache static drawing/order and preload nearby assets. If network stalls correlate, show a connection indicator and investigate delivery. Do not increase prediction depth or walk speed simply to conceal stalls.

## Validation before accepting a movement change

Use a real phone on both Wi-Fi and mobile data, including a warm-device run. Compare current controls with the proposed 80 ms touch-turn variant and the two direction mappings. Exercise starts from every heading, short adjustments, reversals after long drags, narrow doors, corners, NPCs under the stick, simultaneous attack, chat focus, modal opening, foreground/background transitions and release mid-step.

Keep sustained walks of at least 84 steps to detect pacing drift. A useful initial target is first movement within 100 ms after a deliberate touch direction crosses its activation threshold when no attack, collision or network gate applies. Keep zero scheduling-induced gaps during continuous walking and no additional steps issued after release. Evaluate perceived steering accuracy separately from server ACK latency.

No phone is currently connected to ADB, so this audit cannot establish the actual device's input latency, thermal state, network quality, or rendering frame times. The recommendations are ranked hypotheses grounded in current code and regression evidence.

## Fresh checks and related fix

- `short_movement.gd`: 32 heading/input combinations passed, including turn-only taps and the 200 ms hold.
- `movement_controls.gd`: keyboard, four-way stick, hysteresis, dead zone, reversal, pointer capture, NPC overlap and modal/focus checks passed.
- `movement_timing.gd`: all eight simulated frame rates and controlled remote jitter passed. It still reports the existing two-resource shutdown leak; `scripts/build.py check` likewise imports successfully but fails on that shutdown diagnostic, also present in earlier validation logs.
- `gameplay_smoke.gd`: passed.
- `guild_mobile.gd`: 12 checks passed, including actual sprite/button touches, opening through the response dispatcher, error feedback, landscape fit, Back and disconnect.
- Server unit suite: 134 tests passed.
- Signed release APK v0.33.2 / code 45: export, signature and 16 KiB alignment checks passed. No device was available for installation.
- Hosted adapter: deployed with a backup and zero active sessions, restarting only the gateway. Public TLS WebSocket checks passed native Guild Bob opening, information/member not-found replies and close; see `guild-public-report.json` and `guild-deployment-report.json`.
- Isolated real etheos session: Guild Bob Open, guild information, member list, both native not-found reply widths and close passed; see `guild-native-report.json`.

Guild Bob's original failure was missing type-11 NPC dispatch, gateway operations and a guild window. Those are now implemented for native opening, public information and member lookup. The subsequent v0.34.0 implementation completes founding invitations/confirmation, joining/recruiting, deposits, descriptions, rank names and member ranks, removal, leaving/disbanding and guild chat; see `GUILDS.md` and `guild-full-native-report.json`.
