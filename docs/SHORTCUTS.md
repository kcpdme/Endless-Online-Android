# Skill and consumable shortcut persistence

Version 0.35.2 / Android code 49.

The four combat shortcuts are two learned skills and two consumable item IDs.
Previously `quick_skills.json` and `quick_items.json` lived only in Godot's
`user://` directory. They were keyed by server address and character name, so
ordinary relogging worked, but lost app data, uninstall/reinstall, or a package
change restored defaults. No shortcut preference was sent to the server.

## Saved behavior

The authenticated gateway stores each group of two slots in a dedicated SQLite
database keyed by native account and character name. It derives both identities
from the successful native login and entered character, never request fields.
Temporary login character IDs are not storage keys. Native character saves,
inventory counts, learned spells, equipment and combat remain authoritative and
are not modified by a preference save.

`enter` includes a `shortcuts` object containing any saved `items` and `skills`
groups. `shortcuts_set` accepts flat fields `kind` (`items` or `skills`), `first`
and `second`. All IDs must be integers in native two-byte bounds. Skills must be
learned; items must have a consumable type in the native EIF catalog. Owning a
stack is not required to preserve a depleted shortcut. Zero explicitly clears
a slot; an absent group is distinct from `[0, 0]`.

On first login with no saved server group, the client uploads its existing local
choices, or initial defaults if no local choices remain. Once saved, server
choices restore into fresh client data. A durable local pending record retains
changes made before an acknowledgement. Saves are serialized per group, so an
older acknowledgement cannot erase a newer pending selection. Failed saves
retry after five seconds and on reconnection; they do not block walking or
combat. A forgotten skill clears its own shortcut and persists that clearing.
Other characters and accounts keep separate assignments.

Choices already erased before this version cannot be reconstructed from the
old server: it never received them. Assign them once in this version to save
them for subsequent installs. Before that first successful server save,
uninstalling still removes local choices and unacknowledged changes.

## Android updates

`scripts/install_android.py` uses `adb install --no-incremental -r --user 0`.
An earlier incremental install reported success while the package could not be
resolved afterward. The full-update helper verifies the installed APK checksum,
reported version, and that Android's original `firstInstallTime` is unchanged.
It never uninstalls or clears application data. Keep the existing package and
release signing certificate.

## Server deployment

Deploy `server/shortcuts.py` and the updated `server/gateway.py`. Create
`/opt/aster-vale/preferences` owned by `astervale:astervale`, mode 0700. The
service configuration sets `ASTER_VALE_SHORTCUT_DB` to
`/opt/aster-vale/preferences/shortcuts.sqlite3` and grants write access only to
that preferences directory under `ProtectSystem=strict`. The native database
and world process need no changes. Back up this preferences database alongside
the native world database using SQLite's backup API.

Older clients continue to play but cannot upload new shortcut changes. A
client connecting to an older gateway retains its local shortcut behavior.

## Verification

- `server/test_shortcuts.py`: persistence across store reconstruction, two-group
  updates, explicit empty slots, account/character isolation, native item and
  skill validation, authentication and client-supplied identity rejection.
- `client/tests/shortcut_persistence.gd`: local migration, clean local-data
  restoration of all four slots, depleted items, explicit zeros, old ACKs,
  failed saves, reconnect retries, forgotten skills and nonblocking saves.
- `server/test_shortcuts_live.py`: two separate real Godot processes with fresh
  user directories against native login/entry. The first assigns and saves;
  the second restores all four without writing defaults or changing native
  inventory and learned spells. Supports local TCP and public WSS.
- Existing movement, joystick startup, combat, guild, equipment, gameplay and
  world regression scripts pass with the new synchronization.

Reports are in `shortcut-persistence-*-report.json` beside this document.
