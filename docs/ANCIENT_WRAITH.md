# Ancient Wraith original transparency

Ancient Wraith is native NPC definition 255, graphic 171. Ghost Mansion #4
(map 277) has three native spawn groups of three. Definitions, spawns, combat
and the server are unchanged by this fix.

Both supplied original archives have the same GFX021 data. Graphic 171's source
resources 6801–6812 are intentionally transparent (standing and walking), while
6813–6816 contain the original visible attack artwork. The importer previously
rejected any NPC with no visible standing frame. That omitted Ancient Wraith
from the manifest, triggering the client's generic gold missing-art circle.

The importer now explicitly preserves Ancient Wraith's original transparent
idle/walk poses and visible attack poses, including original mirroring, bounds
and offsets. Truly missing standing art on other NPCs still reports a failure;
their existing unused-pose standing fallbacks are retained. Blank unexpected
Wraith attack art is also rejected, so invisibility does not hide an import bug.

For an already imported content pack:

```sh
python3 tools/export_wraith.py --graphics reference/gfx.zip
```

This narrow export repairs only this NPC and catalog availability/checksum
metadata. It preserves the separate character-layer baseline. Full catalog
exports use the same policy automatically. Classic and Enhanced graphics share
this NPC data, so switching character art cannot reintroduce the ball.

Validation compares all exported frames pixel-for-pixel against original GFX021,
checks the transparent/visible state boundary and nine unchanged native spawns,
and verifies other NPC fallback behavior. The actual Godot NPC draw path is
captured in both graphics profiles: idle/walk draw no body or ball, attacking
draws the original Wraith, and ending the attack returns to transparency. Hit
targets remain available. A positive control removes the art temporarily to
prove the test captures the old ball, then checks that ordinary Wraiths remain
visible.

See `ancient-wraith-source-report.json` and `ancient-wraith-render-report.json`.
The original client references are local `NPCSpriteDataCache.IsBlankSprite`,
`NPCSpriteSheet` and `NPCRenderer.DrawToRenderTarget` from pinned EndlessClient.

Names and combat HP strips now follow the same transparent pose metadata as the
body. Idle/walking Wraiths have no world label, including after a recent hit.
Their original attack animation reveals both the sprite and name; both hide
again when that animation ends. Visible attack artwork also anchors the name
above the head instead of using the empty standing frame. This is shared by
Classic and Enhanced, without changing combat, targeting, or minimap markers.
