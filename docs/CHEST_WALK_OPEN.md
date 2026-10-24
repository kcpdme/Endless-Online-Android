# Opening chests by walking toward them

Like the original EO client, attempting to walk into an adjacent chest opens it.
The chest tile stays blocked; the character stands beside it. This works with a
held joystick direction or movement key, including approaching from farther away.
Tapping the chest still works.

The original comparison follows `ArrowKeyController.AttemptToStartWalking`,
`UnwalkableTileActions.HandleWalkToTileSpec`, and
`UnwalkableTileActionsHandler.HandleUnwalkableTileActions` in the pinned local
EndlessClient reference. A non-walkable Chest tile dispatches its chest-open
interaction. The previous Android path only faced the blocked tile.

The new blocked-step handler waits for the preceding native Walk acknowledgement,
then requests the existing native `chest_open` operation. It consumes movement
intent immediately, preventing repeated opens while waiting or after a locked
chest rejection. Native chest contents, key requirements, loot ownership, and
inventory acknowledgements continue to apply. Decorative chest artwork without
an actual Chest tile does not become a storage container.

Validation includes the existing mobile chest and movement controls regressions,
eight native chest-state tests, and an isolated real Godot→WebSocket→gateway→etheos run.
The live run holds a movement key to approach the Sand Secret chest (map 53,
6,22), verifies confirmed adjacency at (6,23), deposits Gold, reopens with the
joystick, and withdraws the native stack. Two gestures produce exactly two opens.

Run the shared isolated native UI harness with `--scenario chest`:

```sh
python3 server/test_inn_citizenship_ui.py --scenario chest --godot /path/to/godot --report /path/to/report.json
```

No server deployment or world-data changes are needed for this client fix.
