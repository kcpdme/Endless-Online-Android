# NPC artwork pilot — Android 0.51.0 (94)

Piglet (NPC 230, graphic 154) and Banshi (NPC 209, graphic 134) use enhanced artwork. Banshi companions share that graphic. The other Piglet variant (graphic 155) and all other NPCs retain their original artwork. This is a two-species pilot; it does not roll out the whole catalog.

The enhanced samples are enabled when their optional local pack is installed. Menu → Graphics → Enhanced NPC samples switches back to Classic immediately and saves the choice independently of character graphics. Builds without the pack continue using Classic.

## Artwork and packing

The built-in `image_gen` tool edited reference contact sheets made from the original sprites. It did not create replacement character concepts. The exact prompts are [Piglet](art-prompts/npc-piglet-enhancement.txt) and [Banshi](art-prompts/npc-banshi-enhancement.txt). Both generated source sheets were 1254×1254 RGBA; the requested reference/output sizes in the prompts are not the final runtime dimensions.

Local source outputs, deliberately outside Git and the APK:

- `work/npc-enhancement-pilot/piglet-generated.png`
- `work/npc-enhancement-pilot/banshi-generated.png`
- `work/npc-enhancement-pilot/sources.json` (original metadata and canonical pose order)

`tools/pack_npc_enhancement.gd` trims each generated cell, resamples with premultiplied alpha, fits it to the original pose bounds, derives the mirrored views and packs compact 2× atlases. It preserves every original idle, walking and attack pose, logical canvas, foot offset and visible bounds. There are 28 Piglet frames and 32 Banshi frames across four directions. Source contact sheets are not runtime resources.

Local runtime output paths:

- `client/content/characters/npc_enhanced/npc154_2x.png` — 768×368
- `client/content/characters/npc_enhanced/npc134_2x.png` — 800×840
- `client/content/characters/npc_enhanced/pack.json`

Artwork remains in the existing ignored content directory and is included in the signed local Android build, not committed. Regenerating reference images requires the original local content; `pack.json` is a separate optional registry and never overwrites the original manifest.

Packing command, from the repository root:

```bash
work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path client \
  --script "$PWD/tools/pack_npc_enhancement.gd" -- \
  "$PWD/work/npc-enhancement-pilot/sources.json" \
  "$PWD/work/npc-enhancement-pilot/piglet-generated.png" \
  "$PWD/work/npc-enhancement-pilot/banshi-generated.png" \
  "$PWD/client/content/characters/npc_enhanced" \
  "$PWD/work/npc-enhancement-pilot/pack-report.json"
```

## Runtime behavior

Only enhanced NPC textures use smooth filtering. Their original logical size and display-pixel alignment are retained; terrain, players and other classic artwork retain their existing filtering. Nameplates, health bars and tap targets account for source pixel scale. Pet/shop previews crop one atlas pose instead of showing the entire sheet. No combat stats, NPC timing, rewards or server data changed.

Pack validation rejects missing poses, altered offsets, invalid dimensions, malformed nested values, out-of-atlas regions and paths outside the optional pack. The classic definitions remain available in memory. Changing character graphics preserves the NPC preference.

## Validation

See `npc-art-pilot-report.json` for measured build size and checks. Offline tests render the actual game renderer, use disposable in-memory NPCs and do not log in as live characters.

- `npc_art_profiles.gd`: all 60 frames, mirrored views, geometry, original tap regions, malformed pack rejection, preference persistence, Banshi pet crop and Graphics layout/Android Back.
- `classic_name_inspection.gd`: 653 checks covering NPC metadata, transparent pixels and inspection behavior.
- `art_profiles.gd`: 371 character graphics and actual rendered-preview checks.
- `world_sampling.gd`: 4,372 checks, including both enhanced samples at three display scales and three zoom levels over 24 camera phases. Aligned sample pixels differ by at most 1/255 in one rounding case (allowed tolerance 2/255).
- `combat_mobility.gd`: 17 checks; mobile combat/potion/chat/despawn regression also passes. Its old fixture was corrected to identify a Priest before casting Heal Self and to provide four 120 ms attack poses.
- Signed Android release export, v2 signature and 16 KiB ZIP alignment verified. Full ADB update preserves the original first-install timestamp and verifies installed APK SHA-256.

Rendered comparisons are local in `work/npc-enhancement-pilot/previews/`: `comparison-idle.png`, `comparison-frames.png`, `comparison-attack.png`, `animation.gif`, `world-classic.png`, `world-enhanced.png`, and phone-size Graphics screenshots.

## Size budget and wider rollout

The two lossless imported textures total 840,900 bytes before APK compression and decode to 3,818,496 bytes (3.64 MiB) of RGBA texture memory. Repeated instances share the textures. No source/reference sheets enter the APK. The optional registry compresses to about 1.4 KiB.

The same two-ABI baseline APK was 254,964,773 bytes (243.153 MiB). This pilot adds about 0.82 MiB; the exact final bytes and hash are in the report. Existing ARM64 and x86_64 native libraries are unchanged at 147,888,040 stored bytes. This graphics change does not solve the existing large base package.

For a wider rollout, measure each species before including it, keep 2× runtime art, share mirrored poses where useful, and consider visually checked WebP compression. Do not bundle high-resolution source sheets or duplicate originals in a second pack. At this pilot's average, 100 additional species would add roughly 40 MiB; large packs should eventually be optional downloads with a bounded disk cache and Classic fallback. Phone-only ABI delivery and music delivery are separate opportunities to reduce the existing base package. They are not changed by this pilot.
