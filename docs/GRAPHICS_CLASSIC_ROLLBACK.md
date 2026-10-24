# Classic character graphics restored

The phone review of the painted pilot found that walking and melee animation
need substantially more work. The pilot is paused at the user's request.

Version 0.39.1 / code 57 restores the character renderer, character previews,
login and Graphics panel from the verified 0.38.2 checkpoint `bf3faca`.
All art packs are excluded from exports. An old saved Enhanced setting is
reset and saved as Classic when no ready pack is installed. Original clothing,
weapons, walking, melee and sitting remain the original assets and frames.
The earlier shared Ancient Wraith fix remains included.

The experiment is preserved in branch `codex/painted-pilot-paused`, commit
`5a12ba1`. The generated artwork stays separately under
`client/art_packs/painted_v1/` and in
`artifacts/graphics-backups/painted-pilot02.zip`. Original character artwork
and its separate baseline backup are unchanged. The ignored assets require
that backup in addition to the Git branch. Experimental assets are not shipped.

Install as a signed in-place APK update; do not uninstall or clear app data.
The higher version code preserves Android update compatibility with 0.39.0.
