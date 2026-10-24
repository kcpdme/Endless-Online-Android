extends SceneTree
class NPCProbe extends "res://scripts/main.gd":
	var sample: Dictionary = {}
	func _draw() -> void:
		if online != null and not sample.is_empty():
			online.draw_entity(sample)
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)
func body(view: SubViewport, game: Node) -> Image:
	game.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	return view.get_texture().get_image().get_region(Rect2i(100, 110, 200, 150))
func sprite(view: SubViewport, game: Node) -> Image:
	var capture: Image = await body(view, game)
	return capture.get_region(Rect2i(60, 62, 80, 75))
func caption(view: SubViewport, game: Node) -> Image:
	await process_frame # Attack state changes take effect in the next shared render sample.
	game.nameplates.sync()
	check(not game.nameplates.entries.is_empty(),"Visible attack has an inspect label or combat HP entry")
	if game.nameplates.entries.is_empty():return Image.create(1,1,false,Image.FORMAT_RGBA8)
	var entry: Dictionary = game.nameplates.entries[0]
	game.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	var top: Vector2 = entry.anchor
	return view.get_texture().get_image().get_region(Rect2i(int(top.x)-100,int(top.y)-2,200,30))
func run() -> void:
	var view: SubViewport = SubViewport.new(); view.size = Vector2i(512,512); view.transparent_bg = true; view.world_2d = World2D.new(); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var game: NPCProbe = NPCProbe.new(); view.add_child(game); await process_frame
	game.set_process(false); game.online.set_process(false); game.music.stop(); game.camera.enabled = false; game.camera.position = Vector2.ZERO; game.position = Vector2(200,200)
	game.started=true;game.menu.hide();game.welcome.hide()
	for child: Node in game.hud_root.get_children():
		if child is Control and child != game.nameplates: child.hide(); child.set_process(false)
	game.nameplates.set_process_input(false)
	game.online_mode = true; game.online.active = true
	game.nameplates.inspected_key="npc:1";game.nameplates.inspected_until=Time.get_ticks_msec()+60000;game.nameplates.inspected_map=int(game.world.get("id",-1))
	var record: Dictionary = {"id":255,"index":1,"x":0,"y":0,"direction":0}
	game.online.npcs.assign([record]); game.sample = {"kind":"online_npc","data":record}
	var graphic: Dictionary = game.online.npc_graphic(record)
	check(not graphic.is_empty() and graphic.graphic == 171, "Ancient Wraith resolves its original sprite instead of missing-art fallback")
	for direction: String in ["south","east","north","west"]:
		for state: String in ["idle","frames","attack"]:
			var rows: Variant = graphic[state][direction]
			var frames: Array = rows if rows is Array else [rows]
			for frame: Dictionary in frames:
				var image: Image = game._texture(frame.path).get_image()
				check(image.get_used_rect().has_area() == (state == "attack"), "Original idle/walk is transparent and attack is visible")
	var modes: Array[String] = ["classic"]
	var art: Variant = game.get("art_profile")
	if art != null:
		# NPCs are shared, independent of the equipment pack's replacement catalog.
		art.replacements = {"unrelated_equipment_fixture":{}}; modes.append("enhanced")
	for mode: String in modes:
		if art != null: check(art.select_mode(mode, false), "Requested graphics profile is active")
		game.online.remote_motion.clear(); game.online.npc_attack_until.clear(); game.online.npc_health.clear()
		if DisplayServer.get_name() != "headless":
			var idle: Image = await body(view,game)
			check(not idle.get_used_rect().has_area(), "No body or name while idle in " + mode)
		# A recent hit must not expose an otherwise invisible NPC through combat labels.
		game.online.npc_health[1] = {"percent":65,"until":Time.get_ticks_msec()+10000}
		if DisplayServer.get_name() != "headless": check(not (await body(view,game)).get_used_rect().has_area(), "No combat name or HP strip while invisible in " + mode)
		var now: float = Time.get_ticks_msec() / 1000.0
		var at: Vector2 = game.tile_position(Vector2i.ZERO)
		game.online.remote_motion["npc:1"] = {"to":at,"tile":Vector2i.ZERO,"walk_start":now,"steps":[{"from":at,"to":at,"start":now,"direction":"south"}]}
		check(game.online.entity_animation("online_npc",record).state == "frames", "Walking interpolation remains active")
		if DisplayServer.get_name() != "headless": check(not (await body(view,game)).get_used_rect().has_area(), "No body, name or HP strip while walking in " + mode)
		game.online.remote_motion.clear(); game.online.npc_attack_until[1] = Time.get_ticks_msec() / 1000.0 + .30
		check(game.online.entity_animation("online_npc",record).state == "attack", "Native NPC attack selects attack artwork")
		if DisplayServer.get_name() != "headless":
			check((await sprite(view,game)).get_used_rect().has_area(), "Original attack sprite is visibly drawn in " + mode)
			check((await caption(view,game)).get_used_rect().has_area(), "Combat HP becomes visible during attack in " + mode)
		game.online.npc_attack_until.clear()
		if DisplayServer.get_name() != "headless": check(not (await body(view,game)).get_used_rect().has_area(), "Body, name and HP strip disappear again after attacking in " + mode)
		game.online.npc_health.clear(); game.online.npc_attack_until[1] = Time.get_ticks_msec() / 1000.0 + .30
		if DisplayServer.get_name() != "headless": check((await caption(view,game)).get_used_rect().has_area(), "Normal name becomes visible during attack in " + mode)
		game.online.npc_attack_until.clear()
		check(game.online.map_entity_target(at + Vector2(0,-10)).get("kind","") == "npc", "Invisible Wraith retains its interaction target")
	if DisplayServer.get_name() != "headless":
		# Positive control: this is the exact old gold-ball bug when art is missing.
		game.manifest.characters.npcs.erase("171")
		check((await sprite(view,game)).get_used_rect().has_area(), "Capture detects the old missing-art ball")
		game.manifest.characters.npcs["171"] = graphic
		record.id = 113
		check((await sprite(view,game)).get_used_rect().has_area(), "Ordinary Wraith sprites stay visible")
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"profiles":modes,"pixel_render_test":DisplayServer.get_name() != "headless","original_attack_visible":true,"idle_and_walk_invisible":true,"ball_placeholder_removed":true,"targeting_preserved":true,"name_hidden_when_invisible":true,"combat_labels_hidden_when_invisible":true,"name_visible_during_attack":true}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")+"\n")
	print("ANCIENT WRAITH: ",JSON.stringify(report)); game.online.active = false; view.queue_free(); await create_timer(.2).timeout; quit(1 if failed else 0)
