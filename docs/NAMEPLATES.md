# Stable overhead names — v0.40.4

Names originally rasterized at 10–11 px in the game world and were enlarged
by camera/device scaling. Fractional camera positions changed sampled letter
edges. Version 0.40.3 fixed that by drawing screen-sized, pixel-aligned names
in a HUD overlay, but introduced a layering regression: NPC and player names
could cover character bodies, including a crow sharing the player's tile.

`client/scripts/nameplates.gd` now calculates captions in screen coordinates
and submits them inside `main.gd`'s world draw pass, before the sorted actors
and scenery. A temporary draw transform cancels the camera/world transform,
so names retain their screen resolution and physical-pixel alignment. The
transform resets before any actor draws. Character silhouettes cover names
where they overlap; the remaining letters stay visible. Actor artwork keeps
its original depth order. No silhouette masks, duplicate sprites, or additional
render targets are needed.

NPC text remains 17 px; nearby-player text remains 18 px with its original
color and dark outline. HP strips retain their gap above the caption and
share the same occlusion behavior. Only text coordinates snap to physical
pixels. Movement and camera positions stay fractional, and a per-frame pose
cache keeps captions and sprites on the same interpolation sample.

Ancient Wraith names and HP strips remain hidden at idle and while walking,
appear during the visible attack, and disappear afterward. Captions ignore
input, hide during modal dialogs, and clear on disconnect. The local player
still has no overhead name.

Verification:

- **36 rendered occlusion checks / 12 scenarios** use the actual world draw
  pipeline and Classic character sprites. Crow and nearby-player captions
  overlap a character at camera zoom 1×, 1.65× and 2.5× with display scaling
  1× and 1.5×. Covered pixels match the character-only reference; exposed
  pixels retain their caption. One 8-bit channel rounding step is allowed
  at blended edges. See `nameplate-occlusion-report.json`.
- **209 nameplate checks** cover 24 fractional camera positions at each
  display scale, glyph bounds, HP spacing at all three zooms, interpolation,
  Wraith visibility, modals, input and independent ground items. Glyph
  channels vary by at most 1/255 at 1.5× scaling from transform cancellation;
  there is no glyph-edge or bounds movement. At 1× the images are identical.
- **53 Ancient Wraith checks** pass with rendered pixels in both Classic
  and the reversible Enhanced test fixture.
- Four-direction bow/NPC rendering and network regressions pass.
- The signed **0.40.4 / code 70** APK passed signing and 16 KiB alignment
  verification and installed as a full update on the connected Samsung phone.
  Installed bytes match the release and the original installation identity
  is preserved. The app launches with no script or fatal errors in its process
  log. Overlap behavior was tested in isolated render fixtures rather than
  moving the user's live character.

APK SHA-256: `d00a2ddcdba0e46e6df61ac3f96c1384d51115846512e585d4ee29d8ba1ff9c8`.

This is a client rendering fix. No server or account migration is needed.
