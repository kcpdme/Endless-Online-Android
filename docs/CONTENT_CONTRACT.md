# Prototype content contract

Working title: Aster Vale. Android-first Godot 4.7.2, GDScript, Compatibility rendering. Original EO data is development reference content; publication rights are unresolved. No public deployment.

Importer owns `tools/`, `client/content/`. Client engineer owns all other `client/` files. Server engineer owns `server/`. Coordinator owns root docs/build/export tooling. Keep these boundaries to avoid concurrent edits.

`client/content/world.json`:

```json
{"id":5,"name":"Aeven","width":100,"height":100,"tile_width":64,"tile_height":32,"fill_tile":1,"spawn":[40,40],"layers":{"ground":[{"x":0,"y":0,"id":1}],"objects":[],"overlay":[],"walls_right":[],"walls_down":[],"wall_top":[],"shadow":[],"overlay2":[],"roof":[]},"blocked":[[0,0]],"warps":[],"npcs":[]}
```

Width/height are actual tile counts (EMF encoded maximum coordinate + 1). Map selected by importer after inspecting maps. Isometric ground top-left for tile `(x,y)` is `((x-y)*32,(x+y)*16)`; entities stand at tile center `(0,16)` relative to this. Map terrain/objects use extracted graphic IDs, not Windows resource IDs. Ground fill applies where no explicit ground entry; ground zero is blank. Blocked includes blocked tile specifications. Warps remain inert in the first slice unless explicitly supported.

`client/content/manifest.json` contains `graphics` keyed `gfx_number:graphic_id`, each value `{path:"res://content/gfx/003_00001.png",width:64,height:32}`. GFX 3 ground, 4 objects, 5 overlay, 6 walls, 7 wall top, 22 shadows. A `characters` dictionary can define an extracted playable character's frame regions and layered offsets; importer and client engineers should coordinate directly on that additive schema. Include `source` provenance and import warnings. Assets may initially be individual PNGs; atlas conversion can follow profiling.

Client must be usable without a running server for the local exploration slice, and explicitly label this mode. Never display online/server-connected status without a real handshake. Keep authoritative network implementation separate from offline simulation. First session: move around the imported map, inspect touch UI, attack a training enemy, collect/equip an item, persist local prototype state. This is a first slice, not completion of the entire MMO plan.
