# Classic wooden dialogs and combat controls — v0.55.0 (99)

Stats has its own bar-chart icon between Quests and Character on the top HUD.
The equipment screen shows the original EO paperdoll, without its former outer
heading or Stats button. The summoner's pet-collection icon sits directly below
Stats; its summon/dismiss control remains beside the combat controls.

The small circular sword/arrows button to the right of Inventory enables or
disables hold-to-auto attack. Gold indicates enabled; a slash indicates manual.
Enabled preserves the existing behavior: hold the weapon for 600 ms to latch,
then tap the weapon to return to manual. Disabled repeats attacks only while the
weapon is held and stops on release. Disabling also clears any active latch.
The preference is saved in `user://combat.cfg`; the active attack itself is never
saved. Opening a dialog, focus loss and the existing combat cancellation paths
still stop attacks. Attack speed and server combat rules are unchanged.

Gameplay dialogs retain a full-screen input shield with zero opacity. Opening
Inventory, Trade, Bank, Shops, Quests or another modal leaves the world at its
normal brightness and blocks world interactions. Full-screen login, recovery and
the main settings page retain their own deliberate opaque backgrounds.

Dialog cards scale uniformly up to 118% when the available safe area permits,
and shrink to fit smaller screens with 16 pixels of clearance. The paperdoll
bitmap reaches approximately 236% of its original dimensions on a 720-pixel-high
landscape viewport. Native equipment targets and the original OK button stay
aligned with that bitmap. Chat retains its keyboard-aware layout and now also
fits a narrow viewport; town forms retain their own responsive layout.

`tools/prepare_classic_dialogs.py` adapts the original GFX002 resources: 50 for
Trade, 51 for Chest, 52 for Shop/Locker, 53 for Bank, the upper half of 59 for
the quest journal, and 67 for NPC quest dialogs. These IDs match the local
EndlessClient `TradeDialog` and `ScrollingListDialog.GetBackgroundTexture`
implementations. Original outside bevels and blank shop timber are retained;
fixed labels and buttons are replaced by the live mobile controls. Nine-slice
styles tile the timber without stretching baked text. Insets, lists, buttons
and editors use the original blank shop inset. Paperdoll bitmap hit targets and
compact stat-allocation buttons retain their existing styles.

Seven generated PNGs total 224,034 bytes. They and their region/hash provenance
remain private under ignored `client/content/ui`, like the existing EO artwork.
The source extraction tooling is committed. The signed APK is 279,007,780 bytes,
198,470 bytes larger than v0.54.1; native libraries compare byte-for-byte unchanged.

Verification is recorded in [classic-dialogs-report.json](classic-dialogs-report.json).
The offline rendered suite passes 480 checks for separate Stats access,
native/emulated touch and desktop clicks, preference persistence, manual and
latched attacks, transparent modal input protection, unchanged world pixels,
original paperdoll targets, and layouts at 960×540, 1280×720 and 1544×720.
Existing chat/zoom, scrolling, movement, class guidance, chest, quest journal and
character-flow suites also pass. Fixtures use captured transport requests and
isolated local characters; no live player actions are performed.

The broader legacy importer suite passes 11 of 12 tests. Its existing
`test_export_complete_and_frame_dimensions` assertion rejects the intentionally
blank original Wraith (graphic 171) walking frames. The identical assertion also
fails with the unchanged HEAD importer. The new dialog textures reproduce
byte-for-byte, and the corners of all six frames match their original resources.

Android release export, signature and 16 KiB ZIP alignment pass. A full update
was installed on the connected SM-S918B, verified as version 0.55.0/code 99 with
matching SHA256 and its original first-install record. The foreground app was
left alone; device validation covers package installation and integrity, while
interactive verification uses the rendered offline fixtures. Local captures and
logs are under `work/classic-dialogs/`.
