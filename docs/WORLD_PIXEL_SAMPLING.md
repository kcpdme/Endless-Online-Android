# Stable world sampling while walking

Release 0.43.2 (Android code 77) addresses the subtle shimmer on church windows,
stationary NPCs and other detailed artwork while the player walks. The camera
was following the exact fractional movement position. With the default 1.65x
zoom and the phone's display scaling, a source texel can cover a fractional
number of display pixels. Changing the fractional camera translation changes
which texels each display pixel samples, making fine lines appear to breathe.

`client/scripts/world_camera.gd` aligns the camera's final display translation,
after zoom, viewport scaling and quake offsets. It uses one fixed sampling phase
and corrects the camera by at most half a physical display pixel on each axis.
A third-pixel phase avoids nearest-texel boundary ties at the supported zooms.
Rounding world coordinates alone would still leave a fractional display phase.
Zoom and the field of view stay the same; artwork keeps nearest filtering.

Moving characters also align their final drawing anchor to that sampling grid.
All equipment layers share one anchor. The followed player therefore stays
stable too, rather than inheriting the background's old sampling problem.
Movement prediction, network coordinates, interpolation, animation phases,
combat, collision and stepping-stone lift retain their existing values.

The camera runs after movement and shake and before inspection labels. Label
synchronization also aligns the camera before projecting a name or health bar,
so labels and actor artwork use the same transform.

## Verification

The rendered test uses the real church window graphic 6:342, Guild Bob's NPC
art and the player's layered standing artwork. Animation is frozen to isolate
sampling changes. It compares 24 fractional camera phases at each of three
zooms (1.0, 1.65 and 2.5) and three display scales (1.0, 1.25 and 1.5): 27 cases,
including large world coordinates and a quake offset. It compensates only whole
pixel translation. A small two-level RGBA tolerance permits GPU alpha-edge
rounding; the accepted run actually measured **zero channel difference in all
27 corrected cases**. The original camera reproduces changing artwork in the
same fixtures. A cropped image cannot pass by falling outside the viewport.

The 2,624 sampling checks pass. Regression coverage also passes 403 inspected
name checks, 96 occlusion checks, 109 stepping-stone checks, prediction and
reconciliation, four-direction bow/NPC rendering, and movement timing at
15/24/30/59/60/90/120/144 FPS. The timing test keeps the native 420 ms step,
introduces no stationary frames, and stays within 0.000123 world pixels of the
expected interpolated path. The movement fixture now hides its artificial
login modal before testing Android Back on Character Stats.

Reproduce rendered sampling with an available graphical display:

```sh
ASTER_VALE_TEST_REPORT="$PWD/work/world-shimmer/sampling-report.json" \
  work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --disable-vsync --display-driver x11 --rendering-method gl_compatibility \
  --path client --script res://tests/world_sampling.gd
```

Rendered tests need a real rendering backend; headless dummy rendering cannot
produce the frame images. Evidence is saved in `world-sampling-*-report.json`
beside this document. Normal walking/idle animations and animated map tiles
still change their artwork intentionally; the pixel probe isolates camera
sampling and does not claim those animation frames are identical.

## Android installation and walk check

The signed 0.43.2 / code 77 update was installed on the connected Galaxy S23
Ultra. The installed APK matches SHA-256
`a6d2d8134ffa1d0368301dc27909ff59771062eebb9341864a34a61b56b46ed2`;
signature and 16 KB ZIP alignment checks pass. The existing installation and
saved login were preserved.

A developer character entered the public world and walked beside the church
and NPCs. Native-resolution recordings before and after the update provide a
visual smoke check; their timing and compression do not establish pixel
equality. The uncompressed rendered comparison above supplies that evidence.
The handset runtime log contains no script, parse or fatal errors. The phone
was returned to the original saved account's character selection afterward.
See `world-sampling-phone-report.json` for the release and handset checks.
