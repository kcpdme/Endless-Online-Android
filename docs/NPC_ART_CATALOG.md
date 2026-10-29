# Complete NPC artwork rollout — Android 0.52.0 (95)

All **171 distinct positive graphic IDs used by the installed NPC catalog** have enhanced artwork. This covers **4,992 directional animation frames**, including townspeople, monsters, bosses and pets. Eleven previously unexported but valid original sprite sets are included too: King, Chest, Doll, Drone Flyer, Butter, Gator, Cacadem, Onigiri, Rabther, Alex Borg and Mini Army. Doll is shared by two NPC definitions.

As requested, the rollout uses faithful automatic smoothing. The 169 remaining sprite sets use xBRZ edge reconstruction followed by alpha-correct resampling. The previously approved illustrated Piglet and Banshi keep their exact canonical pixels. This pass smooths original designs; it does not generate new costumes, faces or monster concepts.

Menu → Graphics → **Enhanced NPC artwork** switches between the enhanced and Classic definitions and preserves the player's preference. Every original definition that was already installed remains unchanged. New original sets have been added so Classic also covers the complete catalog.

## Runtime assets and size

The local pack is `client/content/characters/npc_enhanced/pack.json`, with one `npc<ID>_2x.png` atlas per graphic in the same directory. Final artwork remains in the existing ignored content directory and is packaged in the signed local APK, not committed to Git. The optional registry leaves the original manifest definitions intact.

There are 2,496 stored south/north poses. East/west share their pixels through horizontal flipping; two transparent pixels around each atlas cell prevent neighboring-frame bleed. Original frame dimensions, offsets, animation counts, idle animation flags and pose fallbacks are preserved. War Bear's shorter walking frame remains shorter. Ancient Wraith's idle/walk remain invisible and its attack remains visible.

Only these NPC textures use smooth filtering. Region-aware pet previews and inspection alpha tests use the correct frame and mirrored orientation. Map transitions clear the existing texture and nameplate image caches, so visiting new maps does not accumulate the entire enhanced catalog indefinitely.

All 171 runtime textures total **9,398,316 bytes (8.96 MiB)** before APK ZIP compression. They use WebP quality 0.90; the two painted samples stay lossless. The full catalog would decode to 184,883,712 bytes (176.32 MiB) of RGBA if every atlas were simultaneously resident; normal map rendering uses the relevant textures rather than every species. Startup validation briefly loads each atlas to check its size.

The signed APK is **264,965,162 bytes (252.69 MiB)**, an increase of **9,142,033 bytes (8.72 MiB)** over the previous two-NPC pilot. Both existing native ABIs are retained, with unchanged native-library size. The APK contains no npm modules, WebAssembly scaler, source contact sheets, generated image sheets, painted source backups or 4× working images. This rollout controls artwork growth; it does not reduce the existing engine/music base package.

## Verification

Machine-readable results: `docs/npc-art-catalog-report.json`.

- 20,997 NPC checks cover all 4,992 frames: metadata, visible/invisible poses, logical geometry, exact source mirrors, mirrored GPU rendering, mirrored transparent-pixel inspection, targeting, settings persistence, pet preview cropping and mobile dialog layout.
- 697 classic inspection/nameplate checks pass.
- 57 rendered Ancient Wraith checks pass, including body/labels disappearing while invisible and returning on attack.
- 6,120 camera sampling checks pass over 63 scale/zoom/source cases, including an automatically smoothed mirrored Goat and townsman. Remaining GPU rounding is within the existing 2/255 tolerance.
- Eight original-art/metadata tests pass. The catalog test now compares original Aeven spawns to the native map while allowing the existing custom Tailor and Eggkeeper, and requires graphics for every positive catalog graphic ID.
- Signed export, v2 signature and 16 KiB ZIP alignment pass. APK inventory confirms 171 runtime atlases and excludes working/source assets.
- Items, spells, classes, NPC gameplay definitions and maps compare equal before and after the change. Only catalog graphics availability and its local manifest checksum changed. No server deployment is required.

Rendered local previews are `work/npc-enhancement-all/comparison-runtime.png` and `work/npc-enhancement-all/previews/`. The comparison uses the actual imported runtime textures, including compression. See the report for phone installation and unlock-dependent UI verification status.

## Reproduce locally

Requires the existing original content, `reference/gfx.zip`, Node.js and the configured Godot toolchain. Approved source atlases and their original registry are kept locally in `client/art_packs/npc_painted_sources/` with `.gdignore`; they are excluded from the application. The tool preserves them without additional image generation.

From the repository root:

```bash
python3 tools/export_missing_npcs.py --graphics reference/gfx.zip
npm ci --prefix tools/npc-smoothing --ignore-scripts --no-audit --no-fund
mkdir -p work/npc-enhancement-all/poses
node tools/npc-smoothing/prepare.mjs client/content/manifest.json work/npc-enhancement-all/sources.json
node tools/npc-smoothing/smooth.mjs work/npc-enhancement-all/sources.json client work/npc-enhancement-all/poses work/npc-enhancement-all/smoothing-report.json
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client \
  --script "$PWD/tools/prepare_npc_pilot.gd" -- \
  "$PWD/work/npc-enhancement-all/sources.json" "$PWD/client/art_packs/npc_painted_sources" "$PWD/work/npc-enhancement-all/poses"
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client \
  --script "$PWD/tools/pack_npc_catalog.gd" -- \
  "$PWD/work/npc-enhancement-all/sources.json" "$PWD/work/npc-enhancement-all/poses" \
  "$PWD/client/content/characters/npc_enhanced" "$PWD/work/npc-enhancement-all/pack-report.json"
python3 scripts/build.py check --toolchain work/toolchain
node tools/npc-smoothing/configure-imports.mjs client/content/characters/npc_enhanced
python3 scripts/build.py check --toolchain work/toolchain
python3 scripts/build.py android --release --toolchain work/toolchain
```

The exporter is idempotent: it adds only missing original graphics and leaves gameplay sections unchanged. The general full-content exporter now also considers unplaced catalog graphics, so future imports retain complete coverage.
