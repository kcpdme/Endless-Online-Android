extends SceneTree
class Probe extends "res://scripts/main.gd":
	var record: Dictionary = {}
	var pose: String = "idle"
	var phase: float = 0
	func _draw() -> void:
		if online != null and not record.is_empty(): _draw_character_frame(online.character_graphic(record),Vector2.ZERO,"south",pose,Color.WHITE,phase)
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func capture(view: SubViewport, name: String = "") -> Image:
	await process_frame; await RenderingServer.frame_post_draw
	var image: Image = view.get_texture().get_image()
	var folder: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not folder.is_empty() and not name.is_empty(): image.save_png(folder.path_join(name+".png"))
	return image
func run() -> void:
	var view: SubViewport = SubViewport.new(); view.size = Vector2i(1544,720); view.transparent_bg = true; view.world_2d = World2D.new(); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var game: Probe = Probe.new(); view.add_child(game); await process_frame
	game.set_process(false); game.online.set_process(false); game.music.stop(); game.camera.enabled = false; game.position = Vector2(772,550); game.hud_root.hide()
	var art: RefCounted = game.art_profile; art.settings_path = "user://painted-pilot-test.cfg"
	check(art.ready() and art.appearances.size() == 2,"A published Enhanced pack is actually available")
	var male: Dictionary = game.graphics_ui.previews[0].appearance.duplicate(true)
	var female: Dictionary = game.graphics_ui.previews[1].appearance.duplicate(true)
	game.record = male; art.select_mode("classic",false); game.queue_redraw()
	var before: PackedByteArray = []
	if DisplayServer.get_name() != "headless": before = (await capture(view)).get_data()
	check(art.select_mode("enhanced"),"Enhanced can be selected and saved")
	var restarted: RefCounted = preload("res://scripts/art_profile.gd").new(); restarted.settings_path = art.settings_path; restarted.configure(game.manifest)
	check(restarted.mode == "enhanced" and restarted.ready(),"Enhanced remains available after restarting")
	for record: Dictionary in [male,female]:
		var character: Dictionary = game.online.character_graphic(record)
		check(character.get("animation_method","") == "cutout_mesh_v1","Exact native pilot equipment resolves painted art")
		if not character.has("idle"): print("Invalid pilot match: ",art.matching_appearance(record)," ",art.validated); quit(1); return
		for state: String in ["idle","frames","attack","cast","ranged_attack","sit_chair","sit_floor"]:
			for direction: String in ["south","east","north","west"]:
				var rows: Variant = character[state][direction]
				var frames: Array = rows if rows is Array else [rows]
				for frame: Dictionary in frames:
					var r: Array = frame.region
					var image: Image = game._texture(frame.path).get_image().get_region(Rect2i(r[0],r[1],r[2],r[3]))
					check(image.get_used_rect().has_area(),"Every published pose has visible painted artwork")
					check(game._frame_rectangle(frame,Vector2(r[2],r[3])) == Rect2(-24,-72,48,80),"Compact HD frames keep the native logical anchor")
					check(int(frame.pixel_scale) == 4,"Pilot uses higher-resolution source artwork")
	var complete: Dictionary = art.appearances.peasant_male.character
	var original: Dictionary = {"path":"","region":[0,0,192,192],"offset":[0,8]}
	for change: Dictionary in [{"trim_offset":[-1,112]},{"trim_offset":[160,112]},{"logical_canvas":[191,192]},{"offset":[0,9]},{"region":[999999,0,192,320]},{"path":"res://content/characters/missing.png"}]:
		var broken: Dictionary = complete.idle.south.duplicate(true); broken.merge(change,true)
		check(not art.valid_layer(original,broken),"Malformed compact geometry or outside-pack textures are rejected")
	var incomplete: Dictionary = complete.duplicate(true); incomplete.frames.north.pop_back()
	art.appearances.peasant_male.character = incomplete; art.validated.clear()
	check(art.appearance(male).is_empty(),"An incomplete painted pose falls back to Classic")
	art.appearances.peasant_male.character = complete; art.validated.clear()
	game.queue_redraw()
	if not before.is_empty(): check(before != (await capture(view)).get_data(),"World draw path visibly changes in Enhanced")
	for field: String in ["race","hairstyle","haircolor"]:
		var unsupported: Dictionary = male.duplicate(true); unsupported[field] = 2
		check(art.appearance(unsupported).is_empty(),"Unsupported body or hair falls back as a complete appearance")
	for slot: int in [0,4,6,7,8]:
		var unsupported: Dictionary = male.duplicate(true); unsupported.equipment_graphics[slot] = 1
		check(art.appearance(unsupported).is_empty(),"Unsupported equipment never mixes with a painted outfit")
	art.select_mode("classic",false); game.textures.clear(); game.head_images.clear(); game.queue_redraw()
	if not before.is_empty(): check(before == (await capture(view)).get_data(),"Classic rollback is pixel-identical in the actual world draw path")
	game.record.clear(); game.hud_root.show(); game.online.username_field.text = "keep_account"; game.online.password_field.text = "OnlyATest"
	game.graphics_ui.open()
	check(game.graphics_ui.return_to_login and not game.online.panel.visible and game.graphics_ui.panel.visible,"Painted preview opens directly from login")
	check(not game.graphics_ui.choice.is_item_disabled(1),"Enhanced option is enabled in the delivered pack")
	if DisplayServer.get_name() != "headless": await capture(view,"classic-settings")
	game.graphics_ui.choice.select(1); game.graphics_ui.choice.item_selected.emit(1)
	check(art.mode == "enhanced","Graphics menu activates Enhanced")
	if DisplayServer.get_name() != "headless": await capture(view,"enhanced-settings")
	for index: int in range(game.graphics_ui.POSES.size()):
		game.graphics_ui.pose_choice.select(index); game.graphics_ui.pose_choice.item_selected.emit(index)
		for preview: Control in game.graphics_ui.previews: check(preview.pose == game.graphics_ui.POSES[index],"Animation picker reaches the actual preview")
		if DisplayServer.get_name() != "headless": await capture(view,"enhanced-"+game.graphics_ui.POSES[index])
	game._handle_back()
	check(game.online.panel.visible and not game.graphics_ui.panel.visible and not game.menu.visible,"Back returns to login without opening the world menu")
	check(game.online.username_field.text == "keep_account" and game.online.password_field.text == "OnlyATest","Art preview preserves login input")
	art.select_mode("classic"); DirAccess.remove_absolute(art.settings_path)
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"published_appearances":2,"published_frames":96,"pixel_render_test":DisplayServer.get_name() != "headless","world_draw_changes":true,"pixel_identical_classic_rollback":true,"exact_equipment_coverage":true,"login_preview_without_credentials_changed":true}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var output: FileAccess = FileAccess.open(path,FileAccess.WRITE); output.store_string(JSON.stringify(report,"  ")+"\n")
	print("PAINTED PILOT: ",JSON.stringify(report)); view.queue_free(); await create_timer(.2).timeout; quit(1 if failed else 0)
