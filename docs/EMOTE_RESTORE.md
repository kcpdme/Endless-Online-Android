# Original animated emotes restored — Android 0.48.2 (87)

The original EO symbols replace the newer face/bubble icon designs. The built-in image-generation tool enhanced the original sprite frames; the existing fifteen sets, four animation phases, 240 ms frame timing, ID mapping and 960 ms lifetime remain intact. The world renderer uses a 50-world-pixel animation cell with its bottom 96 pixels above the player's ground point, clearing the face/nameplate. The picker shows first-frame previews so fading hearts remain easy to identify.

The enhanced sheet is local content at `client/content/gfx/emotes_enhanced.png`: four 200px frames across and fifteen sets down (800×3000 RGBA). Linear filtering and atlas clipping improve scaling. The packer interpolates premultiplied colour values so invisible RGB matte colours do not create edge fringes. All original animated frames remain in the original `002_00038.png`; clients without the enhanced sheet fall back to that original animation automatically.

`tools/pack_emote_enhancement.gd` packs the approved enhanced 8×8 contact sheet into the runtime atlas. Run it with Godot and pass input/output PNG paths after `--`. Source contact sheets and the resulting derivative artwork live with the private original game content and are not added to the public source repository. The Android export bundles the local enhanced sheet.

## Enhancement process

Built-in `image_gen` edit mode used the original GFX002:38 frames as the identity reference, arranged into a contact sheet without changing their art. The prompt requested faithful enhancement of the old sprite symbols, their individual animation phases, spacing and transparent background, avoiding new emoji faces or badge designs. A second edit cleaned the edges while retaining the original reference. The final full prompt is saved locally at `work/emote-restore/enhancement-prompt.txt`.

The final composite was inspected against a solid game-like background as well as in the rendered game. Some raw RGB values behind fully transparent pixels are coloured; they are invisible when composited. The packer's alpha-aware scaling avoids turning those invisible colours into fringes. The generated artwork is an enhancement, not a pixel-identical copy: the old symbols and animation phases are retained, with smoother contours.

## Validation

The rendered Godot fixture checks all eleven supported social-emote mappings, all four atlas regions for six representative emotes, the exact 240 ms frame boundaries, and face/nameplate clearance. It renders the actual enhanced sun above a character and the original-symbol picker. Existing drink/area checks cover the original music/soda event state and coexistence. No live player character is used for these visual checks.

The balance profile and server mechanics are unchanged by this release. Device installation status, APK hash, signature/alignment and final check outcomes are recorded in `emote-restore-report.json`.
