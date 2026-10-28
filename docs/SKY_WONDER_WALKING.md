# Walking to Sky Haven — v0.44.1

Regular players can now walk to **Sky Wonder (Sky Haven)**:

1. Leave Aeven through its west exit. The existing level-8 gate still applies.
2. Continue west through West Woodlands and the connecting path to Halowdal Avenue.
3. Follow the Avenue road to the **Sky Haven** sign and stone gateway at **13–14,2**.
4. Cross the cloud bridge into Sky Wonder. The southern exit takes the same bridge back.

The map chain is **5 → 186 → 11 → 120 → 23 → 73 → 71**. Phoenix Field remains
accessible through its existing portal in Sky Wonder. Admin → Teleport →
Sky Haven still lands at **map 71, tile 34,14**.

## Repair

The imported world included the cloud bridge on map 73, with exits to Sky Wonder
and Halowdal Avenue, but no incoming connection. The unused road end on the
Avenue now connects to this bridge. This restores walking access using the
supplied maps; it does not claim to reproduce the historical entrance tile.

Map 23 gains two adjacent, level-0, keyless crossings and a sign with original
stone-post and sign artwork. Map 73 receives the name “Sky Wonder Path” and a
safe Avenue return landing at 14,5. Sky Wonder's southern exit returns through
the bridge at 11,11. Existing beach, Halowdale and Phoenix crossings are preserved.

`server/configure_sky_wonder.py` validates all three maps before writing, refuses
unexpected changes at reviewed cells, updates native map revisions, and produces
identical bytes when repeated. Setup includes this repair. No account database is
opened by the installer. `tools/export_sky_wonder.py` synchronizes the three client
maps, their catalog hashes and manifest identity with the repaired native maps.

To regenerate client content after preparing a runtime:

```bash
python3 tools/export_sky_wonder.py --runtime .local/runtime
```

Use the actual prepared runtime path if it differs. Native map changes must be
applied to a backed-up, stopped world. Class balance, items, spells, pets and the
native executable are unchanged by this repair.

## Verification and delivery

Four unit tests verify exact map preservation, sign encoding, safe repeat runs,
reference symlink protection and rejection before partial writes. Four admin
regression tests and the existing travel repair test passed.

A regular character walked the complete Aeven-to-Sky-Wonder chain in a disposable
native world: **147 actual steps, 178 checks**, including the second entrance lane,
both return lanes, Phoenix Field and the existing Avenue exits. A real Godot client
passed **69 checks** for the sign, map title, native crossings and round trip through
WebSocket and gateway adapters. A separate public TLS/WebSocket test verifies the
four new route crossings with a fresh regular character.

The live rollout backed up the stopped runtime at
`/opt/aster-vale/backups/sky-walking-20261028T054356Z`. It verified that installation
preserved account database bytes, the native executable, balance profile, admin
teleport source and all runtime content outside the three reviewed map files.
All three services recovered and the public health endpoint passed.

Android **0.44.1 / code 79** contains the matching catalog and maps. Signature,
16 KB alignment and embedded content checks passed. A full update on the connected
Galaxy S23 Ultra preserved the original install identity and installed APK bytes
matched the release. Launch reached the existing character selection screen with
no script or fatal startup errors. Walking was exercised by the native and Godot
tests above; a physical handset walking session was not repeated.

APK SHA-256: `7efce010d4c3287cadd56fb7f8e44f28bc3d48a728c800446bac4b3df31956b7`.

Sanitized native, client, public, deployment, phone and validation reports accompany
this document. Test credentials and runtime assets are excluded from Git.
