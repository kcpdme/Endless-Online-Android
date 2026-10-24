# Reversible character art packs

Classic character art remains in `client/content/characters/`. Its original
manifest is never rewritten by this workflow. New local assets live alongside
it in `client/art_packs/painted_v1/`; maps are outside the pack's scope.

```text
painted_v1/
  source/                  Read-only copies, layer definitions and SHA-256 hashes
  draft/                   Writable copies and in-progress layered animations
  concepts/                Painted style concepts and generation briefs
  releases/<stage>/        Published, independently versioned assets and descriptor
  pack.json                Active release descriptor; status=draft until ready
```

Source, draft and concepts contain `.gdignore` and are explicitly excluded from
all exports. The original-derived local assets remain ignored by Git, as do the
existing original assets. Commit the renderer, tooling, tests and documentation.
Keep the local baseline backup for recovering artwork; Git alone does not back
up the ignored content.

From the repository root, create a new pack once:

```sh
python3 tools/character_art_pack.py stage --pack painted_v1
python3 tools/character_art_pack.py verify --pack painted_v1
```

Staging copies every existing equipment layer, preserves the originals, and
makes an additional baseline under `artifacts/graphics-backups/classic-<time>/`.
Existing pack folders cannot be overwritten. `source/baseline.json` locates the
backup. Verification hashes the original, source copy and backup independently.

Edit only the draft PNGs and `draft/layers.json`. Preserve each animation's
states, directions, frame counts, original logical size and feet offset. For
2x/3x/4x source resolution, add `pixel_scale` to each frame and scale its source
region by the same factor. The destination size and offset remain in Classic
world pixels. This initial contract retains the full logical frame canvas;
trimmed-frame packing can be added in a later version of the contract.

Complete and visually check a whole appearance: skin, hair and every visible
equipment layer, including front/back weapon and offhand layers when equipped.
List completed layer keys in `draft/reviewed_layers.json`, then publish a new
stage name:

```sh
python3 tools/character_art_pack.py publish --pack painted_v1 --release stage01
```

The publisher rejects unchanged Classic copies, incomplete animations, changed
anchors, out-of-atlas regions and paths outside the draft. It copies reviewed
assets into a new release, retains previous release paths for earlier completed
layers, saves a per-release descriptor, and atomically updates `pack.json` last.
Reusing a release name is refused. A failed publish keeps the active descriptor.

In a build containing a ready pack, Menu → Graphics switches between Classic
and Enhanced immediately and saves the device preference. Missing or invalid
layers fall back to the **entire Classic appearance**, preventing a painted body
from mixing with unfinished Classic clothes. Character creation, selection,
barber previews and online players share the same resolver. Classic is the
default. Enhanced stays disabled while the pack is still a draft.

To roll back the artwork, choose **Classic**. To choose an earlier Enhanced
stage for a later build, restore `pack.json` from that release's descriptor;
older release assets remain present. To roll back the renderer too, the Git
checkpoint is `art-classic-baseline-v0.38.0` (commit `ab2bc84`). None of these
operations changes an account, character appearance ID, inventory, server or map.

Validation:

```sh
python3 -m unittest discover -s tools -p test_character_art_pack.py -v
godot --headless --path client --script res://tests/art_profiles.gd -- --prepare-art-fixtures
godot --headless --path client --editor --import
godot --path client --script res://tests/art_profiles.gd
```

The runtime test uses deterministic brighter 2x fixtures under `test_fixture/`,
excluded from exports. A graphical run verifies that reverting restores an
identical Classic preview; a headless run checks metadata and fallback only.
The fixtures are regression data, not production painted artwork.
