# Aster Vale client

Godot 4.7.2 Compatibility-renderer project. Open `project.godot` and run `main.tscn`, or use the repository build scripts.

This is a **local, offline playable slice** using an imported classic Aeven map and reference graphics. It does not connect to the server directory or any public EO service. Original content is retained as development reference; see root content provenance notes before redistribution.

## Play

- Press **Enter the vale** / **Continue your journey**.
- Tap/click clear ground to walk a collision-aware grid path. Drag in the lower-left area for the floating circular joystick; desktop also supports WASD and arrows.
- The joystick sends four native tile directions. Touch-down is neutral in both base modes; drag to walk immediately. Classic/isometric mapping and floating/fixed circles are selectable in Menu → Movement controls. Online release finishes only the committed tile and clears future movement; offline release stops at the visible position. One finger can move while another strikes; opening a modal or losing focus cancels movement.
- Walk next to the green **Training slime** and hold the enlarged circular **weapon icon**. Attacks repeat every 0.9 seconds with one short swing each. Release or slide off to stop. Tapping the slime or pressing Space attacks once. Three unarmed strikes defeat it.
- The action button has a translucent circular background with an opaque weapon/fist icon and a recovery ring. Walk over the glowing drop, tap nearby loot, or use the pouch icon / E to collect it. Pickup does not wait for attack recovery.
- The **bag icon** / I opens a separate 24-slot bag: select a stored item and equip it.
- The **person icon** / C opens the exact original 380×290 EO paperdoll artwork, scaled for touch, with its silhouette, 15 original equipment positions, information fields and original **OK** button. Select worn armor, boots or weapon, then use **Remove** to store it in the bag. The other positions remain empty.
- Soldier Plate and Blue Boots start equipped. All eight combinations of armor, boots and dagger update the world character. The Dagger changes strikes from one to two damage. A held attack never silently becomes a loot pickup.
- The menu includes reset confirmation and a welcome-screen option. Escape closes the bag or opens the menu.

Player position, coins, kills, and equipment save on movement completion, inventory changes, combat, and app pause, to `user://aster_vale_save.json`. This state belongs to this prototype and device. The slime is harmless and its state resets on restart; its drop is a practice reward rather than a production economy.

## Structure

- `scripts/main.gd`: map rendering with original layer offsets and ordering, culling, movement/pathfinding, practice combat, touch UI, local persistence and audio.
- `scripts/joystick.gd`: translucent floating joystick drawing and displacement.
- `scripts/classic_paperdoll.gd`: original EO paperdoll bitmap, 15 equipment hit regions and real equipped item icons.
- `scripts/hud_icon_button.gd`: opaque bag/person icons on circular touch surfaces.
- `scripts/weapon_button.gd`: circular action control, opaque weapon/fist/pickup art and recovery indicator.
- `scripts/wood_grain.gd`: subtle drawn timber grain and brass corner pins for the warm wooden inventory.
- `content/`: generated and owned by the importer. `world.json` + `manifest.json` are the client boundary.
- `tests/gameplay_smoke.gd`: actual scene gameplay, input dispatch, release/cancellation, outfit changes and old-save migration checks. Use the wrapper below for isolated test saves.
- `icon.svg`: original Aster Vale launcher artwork.

Run the smoke test with:

```sh
python3 scripts/test_client.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

Run directly with `-- --play` to bypass the welcome screen. `-- --play --screenshot-after=2` saves a renderer screenshot to `user://prototype-screenshot.png` after two seconds. These development arguments do not alter the normal Android launch flow.

Implemented scope: one imported map, a layered character with eight equipment appearances, walk/idle/attack frames, one training slime, loot, three equipment types, an inventory/paperdoll, a short objective, touch controls, and local save/reset. Warps, other map NPCs, spells, shops, chat, accounts, and authoritative multiplayer remain future milestones. Door/warp metadata is not an active transition in this slice.
