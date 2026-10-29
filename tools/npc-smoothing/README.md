# Offline sprite smoothing

This preparation tool is outside the Godot project. Its JavaScript, WebAssembly, npm modules and 4× intermediate images are never Android runtime dependencies.

`smooth.mjs` uses pinned [`@kayahr/xbrz` 1.1.2](https://github.com/kayahr/xbrz), the alpha-aware xBRZ implementation by Klaus Reimer based on Zenju's algorithm. That dependency and this wrapper use GPL-3.0-only; see `LICENSE.md`. PNG decoding/encoding uses `pngjs` 7.0.0 (MIT). Source and integrity hashes are recorded in `package-lock.json`; install with `npm ci --ignore-scripts --no-audit --no-fund`.

`prepare.mjs` reads the original manifest and describes every south/north idle, walking and attack frame. `smooth.mjs` reconstructs 4× edges, preserving RGBA transparency. It reuses the scaler for equal dimensions and identical source frames. The Godot packer then downsamples with premultiplied alpha to 2×, avoiding transparent-edge halos. East/west reference the same pixels with a render-time horizontal flip. The original logical bounds and offsets are retained, including frames with different heights.

Approved illustrated Piglet/Banshi poses are supplied separately by `tools/prepare_npc_pilot.gd`. They are preserved without resampling. `configure-imports.mjs` applies WebP quality 0.90 to automatically smoothed atlases and keeps those two painted samples lossless.

The complete local workflow and verification are documented in `docs/NPC_ART_CATALOG.md`.

`smooth-player-items.mjs` uses the same pinned scaler for the complete player and item catalog. `tools/prepare_player_items.gd` trims transparent player canvases, shares identical/mirrored poses and keeps item images at their native dimensions. `tools/pack_player_items.gd` creates compact 2× atlases and the schema-2 registry. `configure-visual-imports.mjs` prepares WebP import settings before Godot imports these atlases; head/hair atlases remain lossless because exact black pixels encode the original hair mask. The scaler cache is bounded to 32 instances.

The player/item workflow, runtime behavior, Android size and verification are documented in `docs/PLAYER_ITEM_ART.md`. All tooling and intermediate images stay outside the shipped client.
