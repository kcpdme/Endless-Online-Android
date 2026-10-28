extends SceneTree
var game: Node
var c: Node
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func wait_for(test: Callable, seconds: float = 15.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if test.call(): return true
		await process_frame
	return false
func choose(id: int) -> void:
	var ui: RefCounted = game.shop_ui
	for index: int in range(ui.offers.size()):
		if int(ui.offers[index].id) == id:
			ui.list.select(index); ui.list.item_selected.emit(index); return
	check(false, "Egg is offered")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PET_FIXTURE")))
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame; c = game.online
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST"); c.username_field.text = str(fixture.username); c.password_field.text = str(fixture.password); c._authenticate("login")
	check(await wait_for(func() -> bool: return c.character_box.visible), "Regular Summoner logs in")
	if failed: game.queue_free(); await process_frame; quit(1); return
	c.character_list.select(0); c._enter_selected()
	check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Regular Summoner enters native world")
	check(int(c.player.stats.admin) == 0 and int(c.catalog.balance_version) == 8, "Tier catalog reaches a regular character")
	game.pet_ui.tick()
	check(game.pet_ui.button.visible, "Summoner has a dedicated pet control")
	check(game.bag_button.get_global_rect().position.y < 100, "Inventory moved to the top row")
	check(game.chat_button.get_parent() == game.chat_ui.quick_root, "Conversations follows the bottom message composer")
	check(not game.chat_button.get_global_rect().intersects(game.chat_ui.quick_bar.get_global_rect()), "Conversations does not cover the message field")
	var keeper: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 321: keeper = npc
	check(not keeper.is_empty(), "Eggkeeper is visible beside Aeven market")
	c.session.request("shop_open", {"npc_index":int(keeper.get("index", 0))})
	check(await wait_for(func() -> bool: return game.shop_ui.panel.visible and c.session.is_idle()), "Real native Eggkeeper shop opens")
	var ui: RefCounted = game.shop_ui
	check(ui.offers.size() == 16, "All 16 native offers are visible")
	for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(1544,720)]:
		root.size = dimensions; await process_frame
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(ui.panel.get_child(0).get_global_rect()), "Egg shop fits supported phone viewport")
		for offer: Dictionary in ui.offers:
			choose(int(offer.id)); await process_frame
			check(ui.item_icon.texture != null, "Each egg previews its actual pet appearance")
			check(ui.description.text.contains("Hit limit") and ui.description.text.contains("Upkeep") and ui.description.text.contains("Death breaks"), "Tier, TP and bond rules are visible before purchase")
			check(not ui.action.disabled, "Summoner can buy each offered egg")
	choose(612); c.player.stats.class_id = 6; ui.refresh()
	check(ui.action.disabled and ui.status.text.contains("Only Summoners"), "Shop disables egg purchases for another class")
	c.player.stats.class_id = 7; ui.refresh(); ui.quantity.value = 1; ui.transact()
	check(await wait_for(func() -> bool: return ui.held(612) == 1 and c.session.is_idle()), "Shop Buy uses real native purchase and inventory acknowledgement")
	ui.close(); c.session.request("item_use", {"item_id":612})
	check(await wait_for(func() -> bool:
		for skill: Dictionary in c.player.get("spells", []):
			if int(skill.id) == 51: return c.session.is_idle()
		return false), "Normal Penguin egg hatches into its new bond")
	game.stats_ui.show_item("item:612")
	check(game.stats_ui.item_art.texture != null and game.stats_ui.item_body.text.contains("Normal tier"), "Inventory detail shows the pet and its tier")
	game.stats_ui.dismiss(); game.skills_ui.selected = 51; game.skills_ui.refresh_detail()
	check(game.skills_ui.detail.text.contains("Normal tier") and game.skills_ui.detail.text.contains("82%"), "Summon skill advertises the same tier combat values")
	game.pet_ui.press()
	check(await wait_for(func() -> bool:
		for npc: Dictionary in c.npcs:
			if int(npc.id) == 309: return true
		return false), "New pet appears through the actual native summon")
	check(await wait_for(func() -> bool: return not c.companion.is_empty() and not game.pet_ui.button.disabled), "Pet control receives native active state")
	check(game.pet_ui.caption.text == "Dismiss", "Pet control changes to Dismiss")
	game.pet_ui.press()
	check(await wait_for(func() -> bool: return c.companion.is_empty() and not game.pet_ui.button.disabled), "Dedicated control dismisses the native pet")
	check(game.skills_ui.known(51), "Dismiss retains the hatched bond")
	game.pet_ui.press()
	check(await wait_for(func() -> bool: return not c.companion.is_empty()), "Dedicated control recalls without another egg")
	check(not c.npc_graphic({"id":309}).is_empty(), "Penguin uses original rendered creature art")
	var report: Dictionary = {"result":"failed" if failed else "passed", "checks":checks, "pet_previews":16, "phone_viewports":2, "native_shop_purchase_hatch_summon":true}
	FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("PET TIERS LIVE: ", JSON.stringify(report)); c.log_out(); game.queue_free(); await process_frame; await process_frame; quit(1 if failed else 0)
