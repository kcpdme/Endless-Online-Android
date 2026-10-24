# Stepping-stone hops — v0.40.6

Original maps already contain Jump tile specification **29**. The client loaded
those tiles as walkable, but previously used ordinary leg animation with no
vertical offset. This omitted the stepping-stone hop.

The supplied EndlessClient reference implements the effect in
`CharacterRenderer.GetSteppingStoneOffset`, `CharacterAnimator.AnimateOneWalkFrame`
and `CharacterRenderPropertiesExtensions.WithNextWalkFrame`: entering or leaving
a Jump tile holds the first walking pose and lifts it by 8/16/16/8 world pixels.
`CharacterAnimationActions` also plays `SoundEffectID.JumpStone` (41).

`client/scripts/stepping_stones.gd` now applies that behavior to adjacent steps
when either endpoint is a Jump tile. It interpolates the reference
**0 → −8 → −16 → −16 → −8 → 0** height keys over the existing step duration,
which smooths the vertical transitions on phones. The full paperdoll holds its
first walking frame, including hair, boots, armor, headgear, offhand and weapon.
Standing, landing, ordinary ground and water tiles do not hop. NPCs and character
previews keep their existing behavior.

The lift affects only sprite rendering. Ground coordinates, shadows, depth
sorting, camera tracking, collision, movement requests and native **420 ms**
walking remain unchanged. Nearby-player rendering samples the active queued
segment once per frame, then shares its position, endpoints and progress with
the hop. A later queued destination cannot make the preceding step jump.
Spawns, warps and non-adjacent correction baselines do not invent hops.

Original SFX 41 plays once on a successfully sent local stone step or a newly
tracked nearby-player stone step. Drawing, duplicate snapshots, rejected/unsent
steps and warp baselines cannot repeat the cue. Existing mute/pause behavior
still applies. Head emotes and character hit testing follow the lifted body;
names retain their stable ground anchor and pixel alignment, with whole-label
collision suppression if a jumping body reaches a caption.

Verification:

- **109 GPU-rendered and behavior checks** cover all four facings, exact lift
  keys, actual sprite height, equipped-layer pose consistency, landing,
  ordinary walking, queued peer segments, unchanged NPCs, and sound ownership.
- **32 native integration checks** use two disposable characters through the
  actual Godot → WebSocket → gateway → etheos flow. On Malone Outlet map 7,
  both characters observe a 16 px peak while entering tile 13,15, crossing
  to 14,15, and leaving to 15,15; the following step to 16,15 has zero lift.
  Native acknowledgements confirm every landing coordinate. Operator
  characters and the production world are not used for this test.
- Existing movement timing checks pass at **15–144 FPS**, with no stationary
  frames or speed changes and unchanged remote ±80 ms packet-jitter behavior.
- Nameplate, network, original audio/speech and four-direction bow/NPC
  regression checks are recorded alongside the release validation.

Reproduce the native crossing test:

```sh
python3 server/test_inn_citizenship_ui.py --scenario stones \
  --godot work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --report work/stepping-stones-native-report.json
```

No asset replacements, map edits, native-server changes or account migrations
are required.

Release verification:

- Android **0.40.6 (72)** imports and exports successfully.
- APK signing verifies with the existing release certificate, SHA-256
  `fbf80de525cf74dbedbcb1ae73899c6fe9a55ea9661b31e93637f074d7e979ed`.
- Android `zipalign -c -P 16 4` passes.
- Release APK SHA-256:
  `69d81b8e88750ef5b1f2f2b90427985e7a392186f63100a3c1401c205e2021e6`.
- Full APK update installed successfully on the connected phone. Android reports
  **0.40.6 (72)**, the installed bytes match the release hash, and the original
  installation timestamp is preserved. The updated app launches and its startup
  log contains no script errors or fatal exceptions. Stone-crossing behavior is
  verified by the GPU and isolated native tests above; no live character was
  moved for the phone startup check.
