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
	check(int(c.player.stats.admin) == 0 and int(c.catalog.balance_version) == 14, "Tier catalog reaches a regular character")
	game.pet_ui.tick()
	check(game.pet_ui.button.visible, "Summoner has a dedicated pet control")
	check(game.bag_button.get_global_rect().position.y > 500, "Inventory restored to the bottom-right row")
	check(not game.bag_button.get_global_rect().intersects(game.pet_ui.button.get_global_rect()) and not game.bag_button.get_global_rect().intersects(game.sit_button.get_global_rect()), "Inventory remains separate from Summon and Sit touch targets")
	check(game.chat_button.get_parent() == game.chat_ui.quick_root, "Conversations follows the bottom message composer")
	check(not game.chat_button.get_global_rect().intersects(game.chat_ui.quick_bar.get_global_rect()), "Conversations does not cover the message field")
	game.emote_ui.tick()
	check(game.emote_ui.button.visible and game.emote_ui.button.get_global_rect().position.x > game.chat_ui.quick_bar.get_global_rect().end.x, "Emote button is right of Send")
	for row: Control in game.emote_ui.rows:
		check((row.get_child(0) as TextureRect).texture != null, "Quick emote has high-resolution artwork")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 77; touch.pressed = true; touch.position = game.emote_ui.button.get_global_rect().get_center(); game._input(touch)
	await create_timer(0.25).timeout
	check(game.emote_ui.popup.visible, "Holding opens translucent vertical emote choices")
	var slide: InputEventScreenDrag = InputEventScreenDrag.new()
	slide.index = 77; slide.position = game.emote_ui.rows[2].get_global_rect().get_center(); game._input(slide)
	check(game.emote_ui.selected == 2 and game.touch_move_id == -1, "Dragging selects an emote without moving the character")
	touch.pressed = false; touch.position = slide.position; game._input(touch)
	check(await wait_for(func() -> bool: return game.drink_effects.social_emotes.has(int(c.player.player_id))), "Release sends the actual native emote and displays it above the owner")
	check(int(game.drink_effects.social_emotes[int(c.player.player_id)].id) == 4, "Selected Angry emote is used")
	check(not game.emote_ui.popup.visible and game.emote_ui.pointer == -99, "Release closes and relinquishes the gesture")
	game.chat_ui.quick_root.position.y -= 400
	game.emote_ui.layout()
	check(game.emote_ui.popup.get_global_rect().position.y >= 0, "Vertical picker stays on screen above a lifted keyboard composer")
	game.chat_ui.tick(); game.emote_ui.layout()
	var last_sent: int = game.emote_ui.last_sent
	touch.pressed = true; touch.position = game.emote_ui.button.get_global_rect().get_center(); game._input(touch)
	await create_timer(0.25).timeout
	slide.position = Vector2(20, 100); game._input(slide); touch.pressed = false; touch.position = slide.position; game._input(touch)
	check(game.emote_ui.last_sent == last_sent and not game.emote_ui.popup.visible, "Sliding outside cancels without sending an emote")
	# One tap leaves the menu open, a second tap selects, outside taps are consumed.
	touch.pressed=true;touch.position=game.emote_ui.button.get_global_rect().get_center();game._input(touch)
	touch.pressed=false;game._input(touch)
	check(game.emote_ui.popup.visible and game.emote_ui.pointer==-99, "Single tap leaves the emote menu open")
	await create_timer(0.9).timeout
	touch.pressed=true;touch.position=game.emote_ui.rows[0].get_global_rect().get_center();game._input(touch)
	touch.pressed=false;game._input(touch)
	check(not game.emote_ui.popup.visible, "Tapping a choice closes the picker")
	touch.pressed=true;touch.position=game.emote_ui.button.get_global_rect().get_center();game._input(touch)
	touch.pressed=false;game._input(touch)
	touch.pressed=true;touch.position=Vector2(20,100);game._input(touch)
	check(not game.emote_ui.popup.visible and game.touch_move_id==-1, "Outside tap dismisses without moving")
	touch.pressed=false;game._input(touch)
	touch.pressed=true;touch.position=game.emote_ui.button.get_global_rect().get_center();game._input(touch)
	touch.pressed=false;game._input(touch)
	await create_timer(3.1).timeout
	check(not game.emote_ui.popup.visible, "Unselected picker closes after three seconds")
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
			check(ui.description.text.contains("Hit limit") and ui.description.text.contains("Upkeep") and ui.description.text.contains("permanent"), "Tier, TP and bond rules are visible before purchase")
			check(not ui.action.disabled, "Summoner can buy each offered egg")
	choose(612); c.player.stats.class_id = 6; ui.refresh()
	check(ui.action.disabled and ui.status.text.contains("Only Summoners"), "Shop disables egg purchases for another class")
	c.player.stats.class_id = 7; ui.refresh(); ui.quantity.value = 2; ui.transact()
	check(await wait_for(func() -> bool: return ui.held(612) == 2 and c.session.is_idle()), "Shop Buy uses real native purchase and inventory acknowledgement")
	var gold_before_sale: int = c.bag_amount(1)
	ui.tabs[1].pressed.emit(); choose(612); ui.quantity.value = 1
	check(not ui.action.disabled and ui.description.text.contains("40%") and ui.description.text.contains("40 Gold"), "Egg Sell tab exposes exact 40 percent buyback and its explanation")
	ui.transact()
	check(await wait_for(func() -> bool: return ui.held(612) == 1 and c.session.is_idle()), "Egg Sell uses a real native inventory acknowledgement")
	check(c.bag_amount(1)==gold_before_sale+40, "Native sale pays exactly 40 Gold per Normal egg")
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
	check(await wait_for(func() -> bool: return c.companion.is_empty() and game.pet_ui.button.disabled), "Dismissal starts shared recovery")
	check(game.skills_ui.known(51) and c.bag_amount(628)==1, "Dismiss retains permanent pet and Hatched Egg")
	check(game.pet_ui.collection_button.visible, "Summoner has a top collection icon")
	game.pet_ui.open(); await process_frame
	check(game.pet_ui.panel.visible and game._modal_open(), "Collection opens as a blocking game modal")
	check(game.pet_ui.list.item_count==1, "Hatched pet appears in collection")
	check(not c.npc_graphic({"id":309}).is_empty(), "Penguin uses original rendered creature art")
	game.pet_ui.panel.hide()
	var report: Dictionary = {"result":"failed" if failed else "passed", "checks":checks, "pet_previews":16, "phone_viewports":2, "native_shop_purchase_hatch_summon":true}
	FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("PET TIERS LIVE: ", JSON.stringify(report)); c.log_out(); game.queue_free(); await process_frame; await process_frame; quit(1 if failed else 0)
