# Classic inspection names — v0.40.5

Version 0.40.3 stopped camera-related shimmer by drawing screen-resolution
names in a HUD overlay, but left every name visible over the world. Version
0.40.4 put names behind actors. That protected body pixels but left pieces
of words around silhouettes. The phone reproduction showed Guild Bob's name
running into Skylar even on the verified 0.40.4 build.

The supplied EndlessClient reference uses inspection labels rather than
permanent labels. The implementation follows its rules:

- NPC/player names appear on desktop hover. NPC hover must hit a nontransparent
  sprite pixel. On phone, tapping an actor reveals its name for three seconds;
  tapping elsewhere clears it. Existing interaction, movement and spell
  targeting still run through their original handlers.
- NPC label tops use the original per-graphic metadata:
  `tile_position.y - 32 - name_label_offset`. This stays stable across ordinary
  animation frames and directions. Guild Bob uses offset 42; Crow uses 4.
  Ancient Wraith's transparent idle art still suppresses its name and HP;
  its visible attack uses a standing-height fallback for the missing metadata.
- A normal name hides while combat HP, speech or a spell shout is present.
  NPC HP uses the classic 40-world-pixel width and name anchor. Spell-shout,
  speech, Fairy Soda emotes and audio rendering are otherwise unchanged.
- Own-character inspection works too. Player labels use a stable standing-body
  anchor with the classic sitting adjustment.

At default zoom, names retain the readable 17 px NPC and 18 px player sizes
and existing colors. Zoom changes the font size in whole screen pixels rather
than stretching a small world-space glyph texture. Glyphs render at screen
resolution and their baselines align after viewport/device scaling. They share the sprite's cached
interpolation sample; sprites and camera retain fractional movement.

A mobile collision safeguard hides a **whole** inspected name if it overlaps
another actor's standing/current artwork bounds. It needs 6 px clearance before
returning, compared with 2 px on entry, so an actor near the boundary cannot
make the label toggle with every pixel. No letters are repositioned around a
body. Captions draw once in the HUD layer above scenery and below controls;
scenery cannot cut or resample their letters.
Inspection clears on dialogs/disconnect and cannot carry across map changes.

Reference source, supplied locally at EndlessClient commit
`d4764cb8b1bad6501c33f38a596d80d3d79c47bb`:

- [NPCRenderer.Initialize / Update / UpdateDrawAreas](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/NPC/NPCRenderer.cs)
- [CharacterRenderer.UpdateNameLabel / GetNameLabelPosition](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/Character/CharacterRenderer.cs)
- [NPCMetadataProvider](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/Metadata/NPCMetadataProvider.cs)
- [HealthBarRenderer.Update](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/HealthBarRenderer.cs)

Verification:

- **653 inspection checks**: default hidden names, real desktop hover, phone
  inspection/expiry, transparent-pixel rejection, original metadata in all
  four directions, speech/shout/HP priority, self inspection, and lifecycle.
- **403 nameplate checks**: NPC and player glyph images are identical across
  24 fractional camera positions at display scaling 1× and 1.5×. Also covers
  shared interpolation, combat HP rendering at zoom 1× / 1.65× / 2.5×,
  Wraith visibility, independent items, input isolation and modals.
- **96 rendered checks / 18 overlap scenarios plus six scenery checks**: Crow, Guild Bob and a
  player, each at all three zooms and both display scales. Whole names hide
  during overlap, leave no rendered fragments, stay hidden under subpixel
  movement, and return after clearance. An opaque world rectangle cannot
  cut away their glyphs.
- **57 Ancient Wraith checks** with rendered pixels in Classic and the
  reversible Enhanced test fixture.
- **102 speech/audio checks**, movement controls, network regressions, and
  four-direction bow/NPC rendering pass.

The signed **0.40.5 / code 71** release passed APK signing and 16 KiB
alignment verification and installed as a full update on the connected Samsung
phone. Installed bytes match the release, the original installation identity
is preserved, and launch diagnostics contain no script/fatal errors. Render
and interaction tests used isolated fixtures rather than moving the user's
live character.

APK SHA-256: `90138b0f11b3eee437625eef6b2bebdd9511dcaba151c0425c8a826d3760e62b`.

No server or account migration is needed.
