# Player and item artwork — Android 0.53.0 (96)

The complete installed player catalog now uses faithful automatic smoothing: **1,055 appearance layers**, **47,120 source poses**, and **911 item PNGs**. Bodies, skin tones, hairstyles, clothes, armour, boots, hats, shields, both weapon layers, accessories and precomposed fallback appearances are covered. The same item textures serve inventory, shops, equipment slots and ground drops. Existing vector egg icons stay crisp without raster conversion. The previous enhanced NPC pack is preserved.

Menu → Graphics → **Enhanced players and items** controls the overlay independently of NPC art. It defaults on, persists across launches and can be switched off to return to Classic. Missing optional artwork falls back to its original source. The earlier illustrated-outfit selector appears only when its separate complete pack is installed.

## Geometry, masks and memory

The preparation stage crops transparent player canvases with two native pixels of padding, then deduplicates identical and exact mirrored RGBA poses. There are **7,124 unique patches**, packed into **1,403 atlases** of at most 2,048 × 2,048 pixels. All 47,120 original frame descriptors resolve to shared poses through a compact schema-2 registry. Clothing and weapon placement keeps the original foot anchor, animation timing and logical dimensions. Mirrored world rendering, character previews, inspection and head composition use the same orientation.

The offline pipeline applies xBRZ at 4×, then alpha-correct Lanczos resampling to 2×. Only final 2× atlases ship. Most use WebP quality 0.90; all **490 atlases containing hat/hair mask data stay lossless**. Original exact-black mask pixels are restored after resampling so hats continue to clip hair. Composite heads use smooth filtering at enhanced resolution. Item textures retain their original logical size while exposing 2× pixels, so icons and ground drops do not enlarge.

The registry validates without loading every atlas into GPU memory. Textures load on demand; map transitions clear the overlay's atlas, image and frame caches along with the existing renderer caches. If the entire catalog were resident, its RGBA atlas payload would be 150,680,784 bytes (143.70 MiB); normal rendering loads the appearances/items it uses. A crowded map can still need more memory than Classic.

Original `manifest.json` and `catalog.json` are **byte-identical to v0.52.0 inside both APKs**. This changes artwork only. No server deployment is required.

## Android size and verification

The signed APK is **278,775,817 bytes (265.86 MiB)**, an increase of **13,810,655 bytes (13.17 MiB)** over v0.52.0. Imported player/item textures total 12,325,662 bytes (11.75 MiB); the remainder includes the registry and code. Both native ABIs and their library sizes are unchanged. No scaler, npm modules, WebAssembly, crop sources or 4× working images are packaged.

Machine-readable results are in `docs/player-item-art-report.json`:

- **113,195 player/item checks** pass, including every frame's placement, all 911 images' native display/2× pixel sizes, 4,274 native hat-mask pixels, lazy loading, six class appearances, both genders, four directions, walking/attack/cast/sitting, settings persistence and phone-sized Graphics layout.
- **20,997 NPC checks**, **697 inspection checks**, **378 illustrated-art checks** and **6,120 camera sampling checks** pass. The camera test includes the enhanced followed player and fractional display scales/zoom, preserving the existing shimmer fix.
- Godot import/runtime checks, signed Android export, APK v2 signature and 16 KiB ZIP alignment pass.
- Installed on Samsung SM-S918B with the exact release hash verified and original first-install timestamp preserved. Cold launch and character-selection previews were checked before the final settings-only layout adjustment; the final installed APK hash and running process logs were verified separately. The previews visibly use enhanced players, clothing and equipment. No startup script/fatal errors were found. Phone verification stayed in UI; no live gameplay actions were performed.
- The old broad `paperdoll_mobile.gd` test still fails its single-tap assertions and then accesses a missing heal label in its outdated class-less fixture. These failures were reproduced against the unchanged `401b753` baseline. They are not counted as passing coverage; the current artwork, preview and inspection checks pass.

APK SHA-256: `dc2d7b0e2a8b1a135cfd7cd5a3f249b867c62a761d8925532280b4e6a65b8ff4`.

Local rendered comparisons are under `work/player-item-smoothing/previews/`, including `idle-south.png`, `attack-east.png`, `sit_floor-north.png` and `items.png`. The comparisons use imported runtime textures, including their final compression.

## Reproduce locally

Original and derived EO binary art remains in ignored local content folders and is packaged only in the local signed APK. Git contains code, tools, tests and reports. Reproduction requires the existing original content, Node.js and configured Godot/Android toolchains.

From the repository root, use a fresh output folder when regenerating so removed atlases do not linger:

```bash
npm ci --prefix tools/npc-smoothing --ignore-scripts --no-audit --no-fund
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client \
  --script "$PWD/tools/prepare_player_items.gd" -- \
  "$PWD/client/content/manifest.json" "$PWD/work/player-item-smoothing"
node tools/npc-smoothing/smooth-player-items.mjs work/player-item-smoothing/jobs.json
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client \
  --script "$PWD/tools/pack_player_items.gd" -- \
  "$PWD/work/player-item-smoothing/jobs.json" "$PWD/client/content/visual_enhanced"
node tools/npc-smoothing/configure-visual-imports.mjs \
  client/content/visual_enhanced work/player-item-smoothing/import-modes.json \
  client/content/characters/npc_enhanced/npc134_2x.png.import
python3 scripts/build.py check --toolchain work/toolchain
DISPLAY=:0 work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy \
  --path client --script res://tests/player_item_art.gd
python3 scripts/build.py android --release --toolchain work/toolchain
```

Set `ASTER_VALE_TEST_REPORT` for JSON results and `ASTER_VALE_ART_PREVIEWS` for rendered comparisons when running the player/item test. Rendering checks require a real display; headless mode cannot validate pixels. The scaler is an offline GPL-3.0-only tool; dependency versions, licenses and integrity hashes remain in `tools/npc-smoothing/`.
