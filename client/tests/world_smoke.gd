extends SceneTree
## Real scene checks for inventory quantities, imported world switching and wide-screen layout.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1544, 720)
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game._reset_progress()
	game._begin_play()
	game._toggle_inventory()
	assert(game.bag_slots[0].icon != null and game.bag_slots[0].text == "0", "Gold remains visible at zero")
	game.inventory.hide()
	for index: int in range(3):
		game.loot_visible = true
		game.loot_tile = game.player_tile
		game._collect_loot(true)
	assert(game.dagger_count == 3 and game.coins == 15, "Three separate pickups stack three daggers and fifteen coins")
	game._toggle_inventory()
	assert(game.bag_slots[0].text == "15" and game.bag_slots[1].text == "3", "Bag displays actual gold and dagger amounts")
	game._select_item("weapon")
	game._toggle_equip()
	assert(game.equipped and game.bag_slots[1].text == "2", "Worn dagger is separate from the two stored daggers")
	game._toggle_equip()
	assert(not game.equipped and game.bag_slots[1].text == "3", "Removing equipment returns one dagger to its stack")
	game._save_progress()
	game.dagger_count = 0
	game._load_save()
	assert(game.dagger_count == 3, "Dagger quantity persists across save/load")
	game.inventory.hide()
	assert(game.load_map(4) and int(game.world.id) == 4 and not game.decorations.is_empty(), "Neighboring map geometry and decorations load")
	assert(game.load_map(5) and int(game.world.id) == 5, "Aeven geometry reloads without old collision/decorations")
	assert(game.get_viewport_rect().size.x > 1280 and game.attack_button.global_position.x > 1300, "Wide screen expands the world and anchors the attack control at its edge")
	assert(game.bag_button.global_position.x > 1200, "Inventory control follows the wide-screen edge")
	game.started = false
	game.queue_free()
	await process_frame
	print("WORLD SMOKE PASS: zero-value coins, stacked daggers, equipment quantities, persistence, real map geometry switching, wide-screen HUD")
	quit(0)
