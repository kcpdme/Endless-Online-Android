extends SceneTree
## Offline sample-art regression: production renderer, geometry, selection and previews.
class Probe extends "res://scripts/main.gd":
	var samples: Array[Dictionary] = []
	var show_world: bool = false
	var pose: String = "idle"
	var phase: float = 0.0
	func _draw() -> void:
		if show_world: super._draw(); return
		if samples.is_empty(): return
		draw_rect(Rect2(0,0,1280,720),Color("182924"))
		var font: Font = ThemeDB.fallback_font
		draw_string(font,Vector2(44,52),"ASTER VALE  /  NPC ART SAMPLE",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("ead0a0"))
		draw_string(font,Vector2(44,86),"Original animations and size • 2× source artwork • " + pose,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("acb8ac"))
		for column: int in range(4):
			var x: float = 174+column*304
			draw_string(font,Vector2(x-112,138),["Piglet / Classic","Piglet / Enhanced","Banshi / Classic","Banshi / Enhanced"][column],HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("ead0a0"))
			for row: int in range(2):
				var at: Vector2 = Vector2(x,385+row*266)
				draw_set_transform(Vector2(x,at.y-120),0,Vector2(2.2,2.2))
				_draw_diamond(Vector2(0,54),Color("315342"))
				_draw_character_frame(samples[column],Vector2(0,54),"south" if row==0 else "north",pose,Color.WHITE,phase)
				draw_set_transform(Vector2.ZERO)
				draw_string(font,Vector2(x-75,at.y+35),"South / East" if row==0 else "North / West",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("acb8ac"))

var checks: int = 0
var failed: bool = false
var frame_count: int = 0
var output: String = ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func frames(raw: Variant) -> Array:
	return raw if raw is Array else [raw]
func screenshot(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot saved: "+name)
func run() -> void:
	output = OS.get_environment("ASTER_VALE_NPC_SCREENSHOTS")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	var game: Probe = Probe.new(); root.add_child(game); await process_frame
	game.set_process(false); game.online.set_process(false); game.online.session.set_process(false); game.music.stop()
	game.camera.enabled=false
	game.menu.hide(); game.welcome.hide(); game.online.panel.hide(); game.hud_root.hide()
	var art: RefCounted = game.npc_art
	art.settings_path="user://npc-art-regression.cfg"
	check(art.ready() and art.enhanced.size()==2,"Only the two pilot graphics load")
	check(art.enhanced.has("154") and art.enhanced.has("134"),"Piglet and Banshi are enhanced")
	var original_hash: String = FileAccess.get_sha256("res://content/manifest.json")
	game.samples.assign([art.classic["154"],art.enhanced["154"],art.classic["134"],art.enhanced["134"]])
	for key: String in art.classic:
		if key not in ["154","134"]: check(art.target[key]==art.classic[key],"Unselected NPC remains Classic: "+key)
	for key: String in ["154","134"]:
		var old: Dictionary=art.classic[key]; var enhanced: Dictionary=art.enhanced[key]
		check(art.valid(old,enhanced),"Production pack validates: "+key)
		for direction: String in ["south","east","north","west"]:
			check(game.online.npc_name_layout(old,direction,false)==game.online.npc_name_layout(enhanced,direction,false),"Name/health/head anchors equal: "+key+direction)
			for state: String in ["idle","frames","attack"]:
				var before: Array=frames(old[state][direction]); var after: Array=frames(enhanced[state][direction])
				check(before.size()==after.size(),"All original poses retained")
				for i: int in range(before.size()):
					frame_count+=1
					var a: Dictionary=before[i];var b: Dictionary=after[i]
					check(Vector2(a.region[2],a.region[3])==Vector2(b.region[2],b.region[3])/float(b.pixel_scale) and a.offset==b.offset,"Original logical size and foot anchor retained")
					var image: Image=game._texture(b.path).get_image().get_region(Rect2i(b.region[0],b.region[1],b.region[2],b.region[3]))
					check(image.get_used_rect().has_area() and image.get_pixel(0,0).a==0,"Every pose has artwork and transparent padding")
					if direction in ["east","west"]:
						var mirror: Dictionary=frames(enhanced[state]["south" if direction=="east" else "north"])[i]
						# Test packed pixels before Godot fills invisible border RGB for filtering.
						var raw:Image=Image.load_from_file(ProjectSettings.globalize_path(b.path)).get_region(Rect2i(b.region[0],b.region[1],b.region[2],b.region[3]))
						var mirrored: Image=Image.load_from_file(ProjectSettings.globalize_path(mirror.path)).get_region(Rect2i(mirror.region[0],mirror.region[1],mirror.region[2],mirror.region[3]))
						mirrored.flip_x();check(raw.get_data()==mirrored.get_data(),"Paired directions mirror exactly")
		var bad: Dictionary=enhanced.duplicate(true);bad.frames.south.pop_back()
		check(not art.valid(old,bad),"Incomplete walk animation rejected")
		bad=enhanced.duplicate(true);bad.attack.north[0].offset=[0,100]
		check(not art.valid(old,bad),"Shifted attack anchor rejected")
		bad=enhanced.duplicate(true);bad.idle.south=frames(bad.idle.south)[0].duplicate(true);bad.idle.south.region[0]=99999
		check(not art.valid(old,bad),"Out of atlas region rejected")
		bad=enhanced.duplicate(true);frames(bad.attack.south)[0].visible_bounds=null
		check(not art.valid(old,bad),"Malformed nested bounds safely rejected")
		bad=enhanced.duplicate(true);frames(bad.attack.south)[0].pixel_scale=[]
		check(not art.valid(old,bad),"Malformed nested scale safely rejected")
	check(not art.valid(art.classic["134"],null),"Null/malformed candidate rejected")
	check(art.select(false),"Classic preference persists")
	game.art_profile.settings_path=art.settings_path;game.art_profile.select_mode("classic")
	var config:ConfigFile=ConfigFile.new();config.load(art.settings_path)
	check(config.get_value("graphics","enhanced_npcs",true)==false,"Character setting preserves NPC preference")
	var fresh:RefCounted=preload("res://scripts/npc_art_profile.gd").new();fresh.settings_path=art.settings_path
	var pristine:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/manifest.json"))
	fresh.configure(pristine);check(not fresh.enabled and fresh.target["134"]==fresh.classic["134"],"New launch restores Classic NPC preference")
	fresh.enhanced.clear();fresh.apply();check(not fresh.ready(),"Pack absent keeps original graphics available")
	# Actual target rectangles must not grow with the source atlas resolution.
	var online:Node=game.online;online.active=true;game.online_mode=true;game.started=true
	online.player={"player_id":100,"x":20,"y":20,"name":"Offline art fixture"}
	for entry:Dictionary in [{"id":209,"index":1,"x":40,"y":40,"direction":0},{"id":230,"index":2,"x":44,"y":40,"direction":0}]:
		online.npcs.assign([entry]);var at:Vector2=game.tile_position(Vector2i(entry.x,entry.y))
		art.select(false,false);var classic_hits:Array=[]
		for y:int in range(-130,16,9):
			for x:int in range(-65,66,9):classic_hits.append(online.map_entity_target(at+Vector2(x,y)))
		art.select(true,false);var cursor:int=0
		for y:int in range(-130,16,9):
			for x:int in range(-65,66,9):
				check(online.map_entity_target(at+Vector2(x,y))==classic_hits[cursor],"Original touch rectangle retained");cursor+=1
	# Pet previews crop a single idle pose out of the Banshi atlas.
	online.catalog.spells["99999"]={"companion":{"npc_id":209}}
	var preview:Texture2D=preload("res://scripts/pet_details.gd").texture(game,{"hatch_spell":99999})
	check(preview is AtlasTexture and preview.get_size()==Vector2(100,210),"Banshi pet preview crops one pose, not the complete atlas")
	online.catalog.spells.erase("99999")
	check(game._texture(art.enhanced["134"].attack.south[0].path) is CanvasTexture,"Enhanced art uses isolated smooth filtering")
	check(not game._texture(frames(art.classic["134"].idle.south)[0].path) is CanvasTexture,"Classic artwork retains original filtering")
	game.online_mode=false;game.started=false
	for state:String in ["idle","frames","attack"]:
		game.pose=state;game.phase=.12;game.queue_redraw();await screenshot("comparison-"+state)
	# Capture each walking/attack sample using the actual production frame sampler.
	for index:int in range(12):
		game.pose="frames" if index<8 else "attack"
		game.phase=float(index%4)/9.0+.005 if index<8 else float(index-8)*.09
		game.queue_redraw();await screenshot("animation-%02d"%index)
	# Real map rendering uses the same camera scale as normal play, with offline NPCs.
	game.show_world=true;game.online_mode=true;game.started=true
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile)
	game.camera.position=game.player_world;game.camera.enabled=true;game.camera.force_update_scroll()
	online.player.merge({"x":40,"y":40,"direction":0,"gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,0,0,0]},true)
	online.npcs.assign([{"id":230,"index":1,"x":38,"y":40,"direction":0},{"id":209,"index":2,"x":42,"y":40,"direction":0}])
	for enabled:bool in [false,true]:
		art.select(enabled,false);game.queue_redraw();await screenshot("world-enhanced" if enabled else "world-classic")
	game.show_world=false;game.started=false;game.online_mode=false;game.camera.enabled=false
	game.hud_root.show();game.graphics_ui.open()
	for size:Vector2i in [Vector2i(960,540),Vector2i(1544,720)]:
		root.size=size;await process_frame
		var card:Control=game.graphics_ui.panel.get_child(0)
		check(game.get_viewport_rect().encloses(card.get_global_rect()),"Graphics dialog fits phone viewport")
		await screenshot("graphics-%dx%d"%[size.x,size.y])
	await screenshot("graphics-settings")
	game._handle_back();check(not game.graphics_ui.panel.visible and game.menu.visible,"Android Back closes Graphics")
	check(FileAccess.get_sha256("res://content/manifest.json")==original_hash,"Original manifest unchanged")
	DirAccess.remove_absolute(art.settings_path)
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"frames":frame_count,"rendered":DisplayServer.get_name()!="headless","graphics":[134,154],"logical_geometry_unchanged":true,"pet_preview_cropped":true}
	var report_path:String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not report_path.is_empty():FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("NPC ART PROFILES: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
