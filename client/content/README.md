# Local game content

Generated maps, graphics, audio, item definitions and the original paperdoll art
are intentionally excluded from this public repository. The game's open-source
code license does not grant redistribution rights to the original EO assets.

Provide your own licensed content matching `docs/CONTENT_CONTRACT.md`, or run the
importer against reference archives you have permission to use:

```sh
python3 -m pip install -r requirements-tools.txt
python3 tools/import_eo.py \
  --sample-data /path/to/sample-data.zip \
  --client-zip /path/to/EOzipped028.zip
```

Run those commands from the repository root. The importer writes `world.json`,
`manifest.json`, graphics, character variants, audio and paperdoll resources here.
These generated files remain ignored by Git. See `tools/README.md` and
`THIRD_PARTY.md` for formats and provenance.

For online play, export the runtime catalog after the base import:

```sh
python3 tools/export_catalog.py \
  --runtime /path/to/staged/etheos/runtime \
  --graphics-zip reference/gfx.zip
```

This adds server item/NPC definitions, all 282 map geometries, item icons, spawned
NPC art, spells and independent male armor/boots/weapon animation layers.
To refresh only equipment layers after an existing import/catalog export:

```sh
python3 tools/export_player_layers.py --graphics-zip reference/gfx.zip
```

Equipment layers currently use the male starter body, race 0, hair 1/color 0.
Alternate bodies/hair, hats/offhands and exact ranged weapon animation offsets
still need additional rendering support.
See `tools/README.md` for the catalog contract and reference archive audit.
