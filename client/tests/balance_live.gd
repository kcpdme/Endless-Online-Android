extends SceneTree
var game: Node
var c: Node
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func wait_for(test: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		if test.call(): return true
		await process_frame
	return false
func run() -> void:
	root.size = Vector2i(1280,720)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_BALANCE_FIXTURE")))
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	c = game.online
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = str(fixture.username); c.password_field.text = str(fixture.password); c._authenticate("login")
	check(await wait_for(func() -> bool: return c.character_box.visible), "Balance fixture logs in")
	if failed: game.queue_free(); await process_frame; quit(1); return
	c.character_list.select(0); c._enter_selected()
	check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Balance fixture enters the native world")
	check(int(c.catalog.get("balance_version",0)) == 8, "Client receives current balance version")
	check((c.catalog.get("items",{}) as Dictionary).has("543"), "New equipment arrives through live catalog synchronization")
	check(str((c.catalog.classes as Dictionary).get("3",{}).get("build_hint", "")).contains("INT"), "Class build guidance is available")
	check(str((c.catalog.items as Dictionary).get("493",{}).get("name", "")) == "Tempest Staff", "New weapon name is visible")
	check(int((c.catalog.items as Dictionary).get("493",{}).get("level_requirement",0)) == 45, "Equipment displays its real level requirement")
	check(str((c.catalog.spells as Dictionary).get("22",{}).get("name", "")) == "Holy Light", "Repurposed spell displays its real effect name")
	check((c.catalog.spells as Dictionary).get("32",{}).has("icon"), "New native skill reuses a working original icon")
	var ui: RefCounted = game.skills_ui
	check(not ui.usable(1) and ui.usable(9), "Mage retains Priest heal ownership but cannot use it")
	check(not c.npc_graphic({"id":306}).is_empty(), "Native companion uses an existing rendered creature")
	check(str(ui.info(28).get("effect_kind", "")) == "companion", "Summon skill advertises its real native effect")
	check(c.equipment_classes(c.catalog.items["131"]).contains("Priest") and c.equipment_classes(c.catalog.items["131"]).contains("Summoner"), "Shared caster clothes display every eligible profession")
	check(not c._equipment_problem(c.catalog.items["533"], 0).is_empty(), "Mage cannot equip the Rogue Hidden Blade")
	check(c._equipment_problem(c.catalog.items["493"], 0).is_empty(), "JSON class access permits the Mage's own staff")
	check(c.catalog.items.has("611") and c._catalog_texture(str(c.catalog.items["609"].icon)) != null, "Pet egg has a working inventory icon")
	check(str(c.catalog.spells["28"].get("learn_source", "")).contains("egg"), "Pet summon explains its egg bond")
	for egg: String in ["609","610","611"]:
		check(int(c.catalog.items[egg].special) == 4 and bool(c.catalog.items[egg].get("bond_lost_on_death", false)), "Egg is bound and explains its mortal bond")
	for summon: String in ["28","33","34"]:
		check(int(c.catalog.spells[summon].max_level) == 0 and bool(c.catalog.spells[summon].get("bond_lost_on_death", false)), "Living bond cannot spend permanent training points")
	check(int(c.catalog.spells["49"].get("area_targets", 0)) == 3, "Mage has early bounded area magic")
	ui.press(2); ui.selected = 9; ui.refresh_detail()
	check(ui.detail.text.contains("/ 10"), "Spell training shows its actual cap")
	check(ui.detail.text.contains("Attack power") and ui.detail.text.contains("TP 38"), "Skill detail shows scaled power and current TP cost")
	ui.selected = 14; ui.refresh_detail()
	check(ui.detail.text.contains("Up to 5 monsters within 2 tiles"), "Area targeting description matches native radius and target cap")
	ui.panel.hide(); game.stats_ui.refresh()
	check(game.stats_ui.details.text.contains("INT first"), "Character stats explain the class's useful attributes")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1544,720)]:
		root.size = dimensions; await process_frame
		ui.panel.show(); await process_frame
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(ui.panel.get_child(0).get_global_rect()), "Updated skill dialog fits the phone")
	ui.panel.hide()
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE)
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"live_native_catalog":true,"class_build_guidance":true,"scaled_spell_preview":true,"level_45_equipment":true}
	file.store_string(JSON.stringify(report,"  ")+"\n"); print("BALANCE LIVE: ", JSON.stringify(report))
	c.log_out(); game.queue_free(); await process_frame; await process_frame; quit(1 if failed else 0)
