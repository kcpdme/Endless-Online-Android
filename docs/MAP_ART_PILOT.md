# Environment smoothing pilot

An opt-in offline comparison uses Aeven Church (map 15), including its floors,
brick walls, roof trim, windows, pews, altar, candles and decorations. No production
renderer, original asset, map, collision or installed APK is changed.

The existing pinned xBRZ sprite tool creates 4× working images. Alpha-correct
Lanczos downsamples these to 2×. The pilot uses WebP quality 90 for decorations
and lossless WebP for floor tiles. Original floor boundary colours and alpha
footprints are retained exactly, with nearest floor sampling to prevent new
dark joins between neighbouring isometric diamonds. Decorations use linear
sampling. ImageTexture logical size overrides preserve native placement and
animation-frame dimensions in the existing renderer.

The 31 graphics / 31 frames total **69,664 bytes encoded**, compared with 21,453
bytes for their original PNGs. Their decoded 2× RGBA pixels total 1,354,608 bytes.
These figures describe this room's assets, not a whole-world APK forecast. No
pilot textures are in the shipped client. Shared tile IDs are processed once.

Reproduce from the repository root with existing private content installed:

```sh
python3 tools/prepare_map_pilot.py prepare --map 15 --output work/map-pilot
node tools/npc-smoothing/smooth-player-items.mjs work/map-pilot/jobs.json
python3 tools/prepare_map_pilot.py pack --output work/map-pilot
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/map-pilot/test-data" \
  XDG_CONFIG_HOME="$PWD/work/map-pilot/test-config" \
  ASTER_VALE_MAP_PILOT="$PWD/work/map-pilot" \
  work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --path client \
  --audio-driver Dummy --script res://tests/map_art_pilot.gd
```

The actual game renderer produces `original.png` / `smoothed.png` at 1920×1080
and the matching close views `detail-original.png` / `detail-smoothed.png` at
1280×720. Original and smoothed captures use identical cameras and a frozen
animation phase. All 31 prepared images retain exactly 2× source dimensions;
the 13 floor images retain byte-exact source alpha footprints at that scale.
Pilot texture logical dimensions are asserted at render time. The isolated
scene performs no live account actions. Render logs contain no script errors.

The images, intermediate crops and private source paths remain under ignored
`work/map-pilot/`. Review outdoor terrain, animated water, tile joins, moving
camera stability, phone frame times and the global texture cache before a
whole-world rollout. This pilot establishes visual feasibility for one room.
