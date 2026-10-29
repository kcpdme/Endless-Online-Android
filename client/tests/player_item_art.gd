extends SceneTree
## Offline verification of compact character layers, mask preservation and items.
class Probe extends "res://scripts/main.gd":
	var records:Array[Dictionary]=[]
	var state:String="idle"
	var direction:String="south"
	var phase:float=.12
	var item_samples:Array[Dictionary]=[]
	var show_items:bool=false
	func _draw()->void:
		if records.is_empty():return
		draw_rect(Rect2(0,0,1600,1000),Color("182924"))
		var font:Font=ThemeDB.fallback_font
		if show_items:
			draw_string(font,Vector2(32,44),"ASTER VALE / ITEMS: ORIGINAL → ENHANCED",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("ead0a0"))
			for index:int in range(item_samples.size()):
				var sample:Dictionary=item_samples[index]
				var at:Vector2=Vector2(30+(index%4)*395,110+(index/4)*285)
				draw_string(font,at,str(sample.name),HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("ead0a0"))
				for side:int in range(2):
					var texture:Texture2D=sample.classic if side==0 else sample.enhanced
					var scale:float=minf(3,minf(140.0/texture.get_width(),180.0/texture.get_height()))
					draw_texture_rect(texture,Rect2(at+Vector2(70+side*160,115)-texture.get_size()*scale/2,texture.get_size()*scale),false)
					draw_string(font,at+Vector2(25+side*160,240),"Classic" if side==0 else "Enhanced",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("acb8ac"))
			return
		draw_string(font,Vector2(32,44),"ASTER VALE / PLAYERS: ORIGINAL → ENHANCED",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("ead0a0"))
		draw_string(font,Vector2(32,78),state+" / "+direction+" · identical equipment and animation",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("acb8ac"))
		var saved:bool=player_item_art.enabled
		for index:int in range(records.size()):
			var x:float=30+(index%3)*525;var y:float=105+(index/3)*430
			draw_string(font,Vector2(x,y+24),str(records[index].role),HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ead0a0"))
			for side:int in range(2):
				player_item_art.enabled=side==1
				draw_set_transform(Vector2(x+120+side*235,y+310),0,Vector2(3,3))
				_draw_character_frame(online.character_graphic(records[index]),Vector2.ZERO,direction,state,Color.WHITE,phase)
				draw_set_transform(Vector2.ZERO)
				draw_string(font,Vector2(x+74+side*235,y+365),"Classic" if side==0 else "Enhanced",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("acb8ac"))
		player_item_art.enabled=saved

var checks:int=0
var failed:bool=false
var output:String=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Saved render comparison")
func item_graphic(game:Node,id:int)->int:
	return int(game.online.catalog.items.get(str(id),{}).get("doll_graphic",0))
func run()->void:
	output=OS.get_environment("ASTER_VALE_ART_PREVIEWS")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1600,1000)
	var game:Probe=Probe.new();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.enabled=false;game.music.stop();game.music.player.stream=null
	game.camera.enabled=false;game.hud_root.hide();game.online_mode=true;game.welcome.hide();game.online.panel.hide();game.menu.hide()
	var art:RefCounted=game.player_item_art;art.settings_path="user://player-item-art-test.cfg";art.select(true,false)
	var manifest_hash:String=FileAccess.get_sha256("res://content/manifest.json")
	var catalog_hash:String=FileAccess.get_sha256("res://content/catalog.json")
	var expected:Dictionary={}
	for name:String in game.manifest.characters:
		if name not in ["npcs","monster"]:art.collect(game.manifest.characters[name],expected)
	check(art.ready() and art.frames.size()==expected.size(),"Every player pose is installed")
	check(art.images.size()==911,"All item PNGs are installed")
	var lazy:RefCounted=preload("res://scripts/player_item_art.gd").new();lazy.settings_path=art.settings_path;lazy.configure(game.manifest)
	check(lazy.atlas_textures.is_empty(),"Startup validation does not upload the entire character catalog")
	lazy=null
	var at:Vector2=Vector2(100,200)
	for key:String in expected:
		var old:Dictionary=expected[key];var e:Array=art.frames[key]
		var frame:Dictionary=art.frame(old)
		check(frame.get("pixel_scale",1)==2,"Every player frame resolves to 2x artwork")
		var old_rect:Rect2=game.nameplates._part_rect(old,at)
		var expected_rect:Rect2=Rect2(old_rect.position+Vector2(e[1],e[2]),Vector2(e[3],e[4]))
		check(game.nameplates._part_rect(frame,at)==expected_rect,"Cropping preserves exact native placement")
	art.clear_cache()
	for key:String in game.graphics:
		if not key.begins_with("23:"):continue
		var original:Dictionary=game.graphics[key]
		var texture:Texture2D=game._texture(original.path)
		check(texture!=null and texture.get_size()==Vector2(original.width,original.height),"Item UI/ground dimensions remain native")
		check(texture is CanvasTexture and texture.get_image().get_size()==Vector2i(int(original.width)*2,int(original.height)*2),"Item pixels retain 2x resolution behind the logical size")
	# Original black head-mask pixels must still remove the underlying hair.
	var mask_samples:int=0
	var layers:Dictionary=game.manifest.characters.equipment_layers.layers
	for gender:String in ["","f:"]:
		for hat:int in [1,4,22,24,43]:
			var head:Dictionary=layers.get("head:"+gender+str(hat),{})
			var hair:Dictionary=layers.get("hair:"+gender+"0",{})
			if head.is_empty() or hair.is_empty():continue
			var source:Dictionary=head.idle.south;var r:Array=source.region
			var image:Image=load(source.path).get_image().get_region(Rect2i(r[0],r[1],r[2],r[3]))
			var composed:Dictionary=game._frame({"head_layers":[hair,head],"clip_black":true},"south","idle",0.0)
			var actual:Image=game._texture(composed.path).get_image()
			for y:int in range(image.get_height()):
				for x:int in range(image.get_width()):
					var c:Color=image.get_pixel(x,y)
					if c.a>0 and c.r==0 and c.g==0 and c.b==0:
						mask_samples+=1
						for dy:int in range(2):
							for dx:int in range(2):check(actual.get_pixel(x*2+dx,y*2+dy).a==0,"Native hat masks still clip hair exactly")
	check(mask_samples>0,"Real native hat masks were exercised")
	# Both genders, all six classes, and their real equipment in the production renderer.
	for spec:Dictionary in [
		{"role":"Warrior","gender":1,"hair":7,"color":4,"body":509,"boots":598,"head":0,"offhand":416,"weapon":498},
		{"role":"Magician","gender":1,"hair":5,"color":2,"body":501,"boots":574,"head":173,"offhand":0,"weapon":493},
		{"role":"Archer","gender":0,"hair":11,"color":4,"body":508,"boots":590,"head":0,"offhand":425,"weapon":496},
		{"role":"Rogue","gender":1,"hair":3,"color":0,"body":505,"boots":582,"head":0,"offhand":0,"weapon":497},
		{"role":"Priest","gender":0,"hair":10,"color":8,"body":500,"boots":566,"head":0,"offhand":0,"weapon":495},
		{"role":"Summoner","gender":1,"hair":14,"color":6,"body":503,"boots":606,"head":0,"offhand":0,"weapon":494}]:
		game.records.append({"role":spec.role,"gender":spec.gender,"race":0,"hairstyle":spec.hair,"haircolor":spec.color,"equipment_graphics":[item_graphic(game,spec.boots),0,0,0,item_graphic(game,spec.body),0,item_graphic(game,spec.head),item_graphic(game,spec.offhand),item_graphic(game,spec.weapon)]})
	for state:String in ["idle","frames","attack","cast","sit_chair","sit_floor"]:
		for direction:String in ["south","east","north","west"]:
			game.state=state;game.direction=direction;game.queue_redraw();await capture(state+"-"+direction)
	for id:int in [457,533,460,156,145,411,283,2,3,1,42,40]:
		var item:Dictionary=game.online.catalog.items[str(id)]
		var source:Dictionary=game.graphics[item.icon]
		game.item_samples.append({"name":item.name,"classic":load(source.path),"enhanced":art.image(source.path)})
	game.show_items=true;game.queue_redraw();await capture("items")
	game.show_items=false;game.queue_redraw()
	# Toggle is independent of NPC/illustrated preferences and preserves the manifest.
	art.select(false);game.textures.clear();game.head_images.clear()
	check(art.frame(expected.values()[0])==expected.values()[0],"Classic restores original frame descriptors")
	var saved:ConfigFile=ConfigFile.new();saved.load(art.settings_path)
	check(saved.get_value("graphics","players_and_items",true)==false,"Player/item preference persists")
	art.select(true,false);game.textures.clear();game.head_images.clear()
	game.hud_root.show();game.graphics_ui.open()
	for dimensions:Vector2i in [Vector2i(960,540),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame
		check(game.get_viewport_rect().encloses(game.graphics_ui.panel.get_child(0).get_global_rect()),"Graphics controls fit phone viewport")
		await capture("graphics-%dx%d"%[dimensions.x,dimensions.y])
	game._handle_back();check(not game.graphics_ui.panel.visible,"Android Back closes Graphics")
	check(FileAccess.get_sha256("res://content/manifest.json")==manifest_hash and FileAccess.get_sha256("res://content/catalog.json")==catalog_hash,"No gameplay/catalog/source metadata is rewritten")
	DirAccess.remove_absolute(art.settings_path)
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"player_frames":expected.size(),"item_images":art.images.size(),"black_mask_pixels":mask_samples,"rendered":DisplayServer.get_name()!="headless","lazy_atlas_loading":true,"native_item_dimensions":true,"geometry_preserved":true}
	var report_path:String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not report_path.is_empty():FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("PLAYER/ITEM ART: ",JSON.stringify(report));game.online.active=false;game.queue_free();await create_timer(.3).timeout;quit(1 if failed else 0)
