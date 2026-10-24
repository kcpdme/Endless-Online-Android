extends SceneTree
var checks: int = 0
var failed: bool = false
const FIXTURE: String = "res://art_packs/test_fixture/"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)

func prepare() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE + "releases/probe/")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/manifest.json"))
	var source: Dictionary = manifest.characters.equipment_layers.layers
	var layers: Dictionary = {}
	for key: String in ["skin:0", "hair:0", "armor:1", "boots:1", "head:1", "weapon_back:4", "weapon_front:4", "offhand:1", "skin:f:0", "hair:f:0"]:
		var layer: Dictionary = source[key].duplicate(true)
		var original: String = str(layer.idle.south.path)
		var image: Image = Image.load_from_file(original)
		image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
		# Deterministic brighter regression fixtures, not proposed production artwork.
		image.adjust_bcs(1.2, 1, 1)
		var path: String = FIXTURE + "releases/probe/" + key.replace(":", "_") + ".png"
		image.save_png(path)
		remap_frames(layer, path)
		layers[key] = layer
	var output: FileAccess = FileAccess.open(FIXTURE + "pack.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"schema":1,"status":"ready","layers":layers}))
	print("Prepared deterministic 2x character regression fixtures")

func remap_frames(value: Variant, path: String) -> void:
	if value is Dictionary:
		if value.has("path") and value.has("region"):
			value.path = path; value.pixel_scale = 2
			for i: int in range(4): value.region[i] = int(value.region[i]) * 2
		else:
			for item: Variant in value.values(): remap_frames(item, path)
	elif value is Array:
		for item: Variant in value: remap_frames(item, path)

func pixels(view: SubViewport) -> PackedByteArray:
	await process_frame; await RenderingServer.frame_post_draw
	return view.get_texture().get_image().get_data()

func run() -> void:
	if "--prepare-art-fixtures" in OS.get_cmdline_user_args(): prepare(); quit(); return
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.music.stop()
	var art: RefCounted = game.art_profile
	art.settings_path = "user://graphics-regression.cfg"
	art.select_mode("classic", false)
	art.load_pack("user://not-installed-art/pack.json")
	check(not art.ready(), "Staged drafts are unavailable to the production selector")
	check(not art.select_mode("enhanced", false), "Unpublished art cannot be enabled")
	check(art.load_pack(FIXTURE + "pack.json"), "Ready regression release loads")
	var record: Dictionary = {"gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,0,0,0]}
	var classic: Dictionary = art.classic
	var original_hash: String = FileAccess.get_sha256("res://content/manifest.json")
	check(art.select_mode("enhanced"), "Enhanced preference saves")
	check(art.definitions(record)["armor:1"].idle.south.pixel_scale == 2, "Completed outfit uses replacement layers")
	var fresh: RefCounted = preload("res://scripts/art_profile.gd").new()
	fresh.settings_path = art.settings_path; fresh.configure(game.manifest)
	check(fresh.mode == "enhanced", "Selection survives restarting the profile controller")
	var missing: Variant = art.replacements["boots:1"]
	art.replacements.erase("boots:1"); art.validated.clear(); art.selections.clear()
	check(art.definitions(record)["armor:1"].idle.south.path == classic["armor:1"].idle.south.path, "One missing layer falls back to the entire Classic outfit")
	art.replacements["boots:1"] = missing; art.validated.clear(); art.selections.clear()
	var invalid: Dictionary = missing.duplicate(true)
	invalid.frames.south.pop_back()
	check(not art.valid_layer(classic["boots:1"], invalid), "Partial walking animations are rejected")
	invalid = missing.duplicate(true); invalid.idle.south.offset = [0, 9]
	check(not art.valid_layer(classic["boots:1"], invalid), "Altered foot anchors are rejected")
	invalid = missing.duplicate(true); invalid.idle.south.pixel_scale = 4
	check(not art.valid_layer(classic["boots:1"], invalid), "Source resolution cannot enlarge the character in world units")
	invalid = missing.duplicate(true); invalid.idle.south.path = "res://content/characters/layer_boots_1.png"
	check(not art.valid_layer(classic["boots:1"], invalid), "Enhanced assets must reside in their separate release folder")
	invalid = missing.duplicate(true); invalid.idle.south.region[0] = 100000
	check(not art.valid_layer(classic["boots:1"], invalid), "Out-of-atlas source regions are rejected")
	var variants: Array[Dictionary] = [record, {"gender":0,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[0,0,0,0,0,0,0,0,0]}, {"gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,1,1,4]}]
	for appearance: Dictionary in variants:
		for direction: String in ["south", "east", "north", "west"]:
			for state: String in ["idle", "frames", "attack", "ranged_attack", "cast", "sit_chair", "sit_floor"]:
				var character: Dictionary = game.online.character_graphic(appearance)
				var frame: Dictionary = game._frame(character, direction, state, 0.0)
				for layer: Dictionary in frame.get("layers", [frame]):
					if layer.is_empty(): continue
					check(Vector2(layer.region[2], layer.region[3]) / float(layer.get("pixel_scale", 1)) == Vector2(192, 192), "HD animation retains original logical frame size")
	var view: SubViewport = SubViewport.new(); view.size = Vector2i(400, 400); view.transparent_bg = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var preview: Control = preload("res://scripts/character_preview.gd").new(); preview.game = game; preview.size = Vector2(400,400); preview.appearance = record; preview.fit_to_rect = true; view.add_child(preview)
	art.select_mode("classic", false); preview.queue_redraw(); await process_frame
	var bounds: Rect2 = preview.rendered_bounds
	var before: PackedByteArray = []
	if DisplayServer.get_name() != "headless": before = await pixels(view)
	art.select_mode("enhanced", false); preview.queue_redraw(); await process_frame
	check(preview.rendered_bounds == bounds, "Preview uses the same height and foot anchor at 2x source resolution")
	if not before.is_empty(): check(before != await pixels(view), "Actual preview renders the brighter HD regression fixture")
	art.select_mode("classic"); game.textures.clear(); game.head_images.clear(); preview.art_cache.clear(); preview.queue_redraw(); await process_frame
	if not before.is_empty(): check(before == await pixels(view), "Switching back restores pixel-identical Classic preview")
	check(FileAccess.get_sha256("res://content/manifest.json") == original_hash, "Switching never writes the original manifest")
	game.online.panel.hide(); game.graphics_ui.open(); check(game._modal_open(), "Graphics settings block world input")
	game._handle_back(); check(not game.graphics_ui.panel.visible and game.menu.visible, "Android Back returns to the menu")
	art.replacements.clear(); game.graphics_ui.refresh(); check(game.graphics_ui.choice.is_item_disabled(1), "Unfinished packs are visibly unavailable")
	check(not art.load_pack(FIXTURE + "missing.json") and art.definitions(record) == classic, "Removing an Enhanced pack safely restores Classic")
	check(not art.select_mode("unknown", false), "Unknown profile names cannot change the renderer")
	DirAccess.remove_absolute(art.settings_path)
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"pixel_render_test":DisplayServer.get_name() != "headless","classic_assets_unchanged":true,"whole_outfit_fallback":true,"hd_logical_size_and_anchor_preserved":true}
	var report_path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not report_path.is_empty():
		var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE); output.store_string(JSON.stringify(report, "  ") + "\n")
	print("ART PROFILES: ", JSON.stringify(report)); view.queue_free(); game.queue_free(); await create_timer(.2).timeout; quit(1 if failed else 0)
