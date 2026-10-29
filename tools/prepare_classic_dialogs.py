#!/usr/bin/env python3
"""Adapt private, original GFX002 dialog frames to resizable mobile controls.

No generated artwork or baked labels/buttons: retain EO's outer bevels and
blank timber, and let the native client draw its accessible live controls.
The source EGF and all outputs remain private/ignored like the paperdoll.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageEnhance
from import_eo import PEBitmaps

VARIANTS = {"shop": 52, "trade": 50, "bank": 53, "chest": 51,
            "quests": 59, "quest_dialog": 67}


def export_dialogs(ui, output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    # Blank footer timber, below the shop's inset and above its outside bevel.
    timber = ui.image(52, transparent=False).crop((14, 253, 250, 278))
    files = {}

    def tile(image, box, texture):
        left, top, right, bottom = box
        for y in range(top, bottom, texture.height):
            for x in range(left, right, texture.width):
                patch = texture.crop((0, 0, min(texture.width, right-x), min(texture.height, bottom-y)))
                image.paste(patch, (x, y))

    for name, graphic in VARIANTS.items():
        source = ui.image(graphic, transparent=False)
        if name == "quests":
            source = source.crop((0, 0, source.width, source.height//2))
        frame = source.copy()
        # Preserve the original outside eight pixels; remove fixed-size widgets.
        tile(frame, (8, 8, frame.width-8, frame.height-8), timber)
        path = output / f"dialog_{name}.png"
        frame.save(path, optimize=True)
        files[path.name] = {"graphic": f"2:{graphic}", "size": list(frame.size),
                            "frame_pixels": 8, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    # Original shop title inset has no writing; use its beveled edges for live
    # buttons, editors and lists, with the same timber darkened for readability.
    source = ui.image(52, transparent=False)
    inset = source.crop((10, 10, 272, 35))
    tile(inset, (3, 3, inset.width-3, inset.height-3), ImageEnhance.Brightness(timber).enhance(.68))
    path = output / "dialog_inset.png"
    inset.save(path, optimize=True)
    files[path.name] = {"graphic": "2:52", "region": [10, 10, 262, 25], "frame_pixels": 3,
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    report = {"source": "gfx/gfx002.egf", "timber_region": [14, 253, 236, 25],
              "mapping_reference": "EndlessClient/Dialogs/ScrollingListDialog.cs:GetBackgroundTexture; TradeDialog.cs",
              "files": files}
    (output / "classic_dialogs.json").write_text(json.dumps(report, indent=2)+"\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("egf", type=Path)
    parser.add_argument("--output", type=Path, default=Path("client/content/ui"))
    args = parser.parse_args()
    result = export_dialogs(PEBitmaps(args.egf.read_bytes()), args.output)
    print(f"Prepared {len(result['files'])} original EO UI textures in {args.output}")
