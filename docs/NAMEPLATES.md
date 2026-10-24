# Stable overhead names — v0.40.3

Overhead names previously rasterized at 10–11 px inside the game world, then
passed through the 1.65× camera zoom and device scaling. Fractional positions
changed the sampled letter edges during camera movement. Idle captions also
shared scenery drawing order and lacked the combat caption's outline.

An isolated reproduction using the project font and filtering produced 24
different aligned glyph images across 24 fractional positions. Rasterizing
screen-sized text at aligned screen coordinates produced one identical image.

`client/scripts/nameplates.gd` now draws NPC and nearby-player captions in the
HUD CanvasLayer, below HUD controls and modal windows. It uses 17 px NPC and
18 px player text, preserving approximately the previous default-zoom size.
Text has a consistent dark outline and linear filtering independent of the
nearest-filtered artwork. Baselines align after the complete viewport/device
transform, including non-integer phone scaling. Only text coordinates are
rounded; movement, camera positions and sprite interpolation stay fractional.

A per-frame render-pose cache shares the exact interpolated sample between
nameplates and sprite drawing. Native snapshots invalidate the cache. Ground
items retain independent positions. Combat HP bars use the same overlay with
a clear gap above the entire caption at minimum/default/maximum zoom. Moving
both captions and their strips into one overlay prevents scenery from covering
part of an idle name and keeps combat visibility consistent.

The original NPC head anchors and player color remain. Ancient Wraith names
and HP strips follow the visibility of the current artwork: hidden at idle
and while walking, visible during the original visible attack, then hidden
again. The overlay ignores input, hides during dialogs, and clears on logout
or connection loss. Local-player name visibility is unchanged.

Verification:

- **161 rendered/behavior checks** passed, including actual glyph-image
  invariance across 24 fractional camera positions at display scales 1× and
  1.5×, intermediate movement sampling, non-overlapping HP/name pixels at
  camera zoom 1× / 1.65× / 2.5×, Wraith visibility, modal/input isolation and
  independent item positions.
- **53 Ancient Wraith checks** passed with actual rendered pixels in both
  Classic and the reversible Enhanced test profile.
- **102 speech/audio checks** passed. Movement controls, network regressions,
  queued movement timing, seating/weight, and bow/NPC rendering also passed. The movement fixture emits its existing
  shutdown-only ObjectDB/resource warnings; the same warnings occur in the
  older v0.37 log. No new script or parsing errors were observed.
- The four-direction bow/boss screenshots were inspected for readable names
  and HP spacing. Android APK signing and 16 KiB alignment checks passed.
- Android **0.40.3 / code 69** installed as a full update on the connected
  phone. Installed bytes matched the release, and the original installation
  identity was retained. Phone launch diagnostics were checked separately;
  movement/glyph behavior was exercised in isolated tests rather than moving
  the user's live character.

APK SHA-256: `aea2b37015af3fbd5811b0b00e2dd5e01824e8316361faf73ae4194b166d809b`.

This is a client rendering change. Production EXP stays 5× and item/Gold drops
stay 100%. No server restart, account migration or art-pack conversion is
required. Reverting the source commit and reinstalling a signed build restores
the previous renderer while preserving account and device login data.
