extends SceneTree
## Offline acceptance of controls, egg footprints and every skill visual.
class Wire extends "res://scripts/online_session.gd":
	var calls:Array[Dictionary]=[]
	func request(op:String,fields:Dictionary={})->int:
		calls.append({"op":op,"fields":fields.duplicate()});return calls.size()
class Probe extends "res://scripts/main.gd":
	var paths:int=0
	func _request_path(_at:Vector2i)->void:paths+=1
var game:Probe
var checks:int=0
var failed:bool=false
var output:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func run()->void:
	output=OS.get_environment("ASTER_VALE_CLASS_RUN_UI_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1544,720)
	game=Probe.new();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.enabled=false;game.music.stop()
	game.online.session.queue_free();var wire:Wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	for card:Control in game.modal_cards:card.get_parent().hide()
	game.started=true;game.online_mode=true;game.online.active=true;game.online.streaming=true
	game.online.player={"player_id":9000,"name":"Run fixture","x":40,"y":40,"gender":1,"race":0,"hairstyle":7,"haircolor":4,"equipment_graphics":[1,0,0,0,1,0,0,0,4],"hp":500,"max_hp":500,"tp":100,"max_tp":100,"spells":[],"inventory":[],"stats":{"admin":4,"class_id":7,"level":50,"stat_points":0},"combat":{"running_supported":true,"running":false,"move_seconds":.42}}
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	game._process(0);await process_frame
	var controls:Array[Control]=[game.zoom_button,game.admin_ui.button,game.party_ui.button,game.skills_ui.buttons[2],game.quest_journal.button,game.stats_button,game.character_button,game.menu_button,game.pet_ui.collection_button,game.bag_button,game.auto_attack_button,game.sit_button,game.attack_button,game.pet_ui.button,game.online.loot_button,game.run_ui.button,game.chat_button,game.emote_ui.button]
	controls.append_array(game.skills_ui.buttons.slice(0,2));controls.append_array(game.quick_items.buttons)
	for dimensions:Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame;game._layout_safe_area();game._process(0)
		check(game.auto_attack_button.size==game.bag_button.size and game.auto_attack_button.size==game.sit_button.size,"Auto target matches inventory and Sit")
		check(game.run_ui.button.visible and game.run_ui.button.size==Vector2(68,68),"Run has a visible full-size touch target")
		check(game.admin_ui.button.get_global_rect().end.x<game.pet_ui.collection_button.get_global_rect().position.x and game.pet_ui.collection_button.get_global_rect().end.x<game.zoom_button.get_global_rect().position.x,"Egg sits between Admin and Zoom")
		var run_rect:Rect2=game.run_ui.button.get_global_rect();var chat_rect:Rect2=game.chat_button.get_global_rect()
		check(is_equal_approx(run_rect.end.x+12,chat_rect.position.x) and is_equal_approx(run_rect.get_center().y,chat_rect.get_center().y),"Run sits immediately left of Chat")
		check(run_rect.get_center().distance_to(game.joystick.get_global_rect().get_center())>game.joystick.radius+34,"Run stays clear of the visible stick")
		var footer_touch:InputEventScreenTouch=InputEventScreenTouch.new();footer_touch.index=83;footer_touch.pressed=true;footer_touch.position=run_rect.get_center();game._input(footer_touch);footer_touch.pressed=false;game._input(footer_touch)
		check(not game.joystick.active and game.touch_move_id==-1 and wire.calls[-1].op=="run_mode","Footer Run touch wins over joystick activation")
		game.run_ui.pending=-1;game.run_ui.tick()
		check(game.pet_ui.collection_button.kind=="egg" and game.pet_ui.collection_button.visible,"Summoner has top egg control")
		for index:int in range(controls.size()):
			var rect:Rect2=controls[index].get_global_rect()
			check(game.get_viewport_rect().encloses(rect),"HUD fits "+str(dimensions)+" #"+str(index))
			for other:int in range(index+1,controls.size()):
				var other_rect:Rect2=controls[other].get_global_rect()
				check(not rect.intersects(other_rect) or rect.get_center().distance_to(other_rect.get_center())>(rect.size.x+other_rect.size.x)/2.0,"Touch targets separate "+str(dimensions)+" #"+str(index)+"/"+str(other))
		game.online.player.stats.class_id=4;game._process(0)
		check(not game.pet_ui.collection_button.visible and game.run_ui.button.visible,"Other classes keep Run and hide the pet collection")
		check(game.run_ui.button.tooltip_text.contains("1.50"),"Rogue running speed is explained")
		game.online.player.stats.class_id=7;game._process(0)
	wire.calls.clear()
	# Touch chooses a request without granting a client-side boost.
	var e:InputEventScreenTouch=InputEventScreenTouch.new();e.index=84;e.pressed=true;e.position=game.run_ui.button.get_global_rect().get_center();game._input(e);e.pressed=false;game._input(e)
	check(wire.calls.size()==1 and wire.calls[0].op=="run_mode" and wire.calls[0].fields.enabled,"Run touch sends exactly one boolean native request")
	check(game.paths==0 and not game.online.player.combat.running and not game.run_ui.button.button_pressed,"Run press never moves the character or predicts native permission")
	game.run_ui.pending=-1;game.online.player.combat.running=true;game.run_ui.tick();check(game.run_ui.button.button_pressed,"Native combat snapshot selects Run")
	game.online.player.combat.running=false;game.run_ui.tick()
	# Hatching ownership remains native, while book entries and shortcut defaults omit pets.
	game.online.player.spells=[{"id":28,"level":0},{"id":35,"level":0},{"id":23,"level":0},{"id":24,"level":0},{"id":51,"level":0}]
	var original_spells:Array=(game.online.player.spells as Array).duplicate(true)
	game.skills_ui.settings_path="user://pet-filter-fixture.json";game.skills_ui.shortcut_identity="";game.skills_ui.master={};game.skills_ui.panel.show();game.skills_ui.refresh()
	check(game.skills_ui.slots==[23,24],"First-use defaults skip summon and dismiss commands")
	check(game.skills_ui.list.item_count==2,"Book shows offensive Summoner skills only")
	game.skills_ui.slots.assign([28,35]);game.skills_ui.selected=28;game.skills_ui.master={"offers":[{"id":51},{"id":35},{"id":27}],"name":"Summoner Master"};game.skills_ui.refresh()
	check(game.skills_ui.slots==[0,0] and game.skills_ui.selected==23,"Legacy pet shortcuts and hidden selection are cleared")
	check(game.skills_ui.list.item_count==3,"Master offers also exclude pet commands")
	for row:int in range(game.skills_ui.list.item_count):check(not game.skills_ui.pet_command(int(game.skills_ui.list.get_item_metadata(row))),"No summon or dismiss entry in book")
	check(game.online.player.spells==original_spells,"Filtering never changes native ownership")
	game.skills_ui.selected=28;var sent:int=wire.calls.size();game.skills_ui.change("level");check(wire.calls.size()==sent,"Hidden pet command cannot be trained from a stale selection")
	game.skills_ui.panel.hide();game.skills_ui.master.clear();game.skills_ui.cancel_cast();game.online.pet_state={"selected_spell":28};game.pet_ui.tick();game.pet_ui.press()
	check(wire.calls[-1].op=="spell_cast" and wire.calls[-1].fields.spell_id==28,"Pet button still calls bound pet")
	game.skills_ui.cancel_cast();game.online.companion={"index":7,"npc_id":300};game.pet_ui.tick();game.pet_ui.press()
	check(wire.calls[-1].op=="spell_cast" and wire.calls[-1].fields.spell_id==35,"Pet button still dismisses called pet")
	game.skills_ui.cancel_cast();game.online.companion.clear();game.skills_ui.selected=0
	# Every egg and keepsake occupies exactly one existing inventory cell.
	var inventory:Array=[]
	for item:Dictionary in game.online.catalog.items.values():
		if not str(item.get("egg_state","")).is_empty():
			inventory.append({"id":int(item.id),"amount":1})
			check(game.bag_grid.dimensions(int(item.id))==Vector2i.ONE,"Egg footprint is one cell "+str(item.id))
	game.online.player.inventory=inventory;game.online._sync_inventory();game.bag_grid.refresh()
	check(inventory.size()==32,"All 16 eggs and 16 keepsakes covered")
	for item:Dictionary in inventory:
		var button:Button=game.bag_grid.buttons[str(item.id)]
		var art:TextureRect=button.get_child(0)
		check(Rect2(Vector2.ZERO,button.size).encloses(Rect2(art.position,art.size)),"Egg artwork stays inside its own cell")
		check(art.position.distance_to((button.size-art.size)/2)<.1,"Egg artwork is centered")
	# Unique icons and complete effects for every spell in the installed catalog.
	var signatures:Dictionary={};var gallery:Image=Image.create(9*64,7*78,false,Image.FORMAT_RGBA8);gallery.fill(Color("101923"))
	var count:int=0
	for key:String in game.online.catalog.spells:
		var ident:int=int(key);var spell:Dictionary=game.online.catalog.spells[key]
		var texture:Texture2D=game.skills_ui.icon(ident)
		check(texture!=null and texture.get_width()==48,"Small high-resolution spell icon "+key)
		var pixels:Image=texture.get_image();var signature:String=pixels.get_data().hex_encode().sha256_text()
		check(not signatures.has(signature),"Distinct glyph/rune combination "+key);signatures[signature]=true
		gallery.blit_rect(pixels,Rect2i(0,0,48,48),Vector2i((count%9)*64+8,(count/9)*78+8));count+=1
		var tones:Array=preload("res://scripts/spell_visuals.gd").palette(ident,spell)
		var primary:Color=Color(str(tones[0]))
		if int(spell.get("hp",0))>0:check(primary.g>primary.r and primary.g>primary.b,"All heals use green")
		if ident in [4,10,25]:check(primary.r>primary.g and primary.r>primary.b,"Fire uses red")
		if ident==5:check(primary.r>.9 and primary.g>.8 and primary.b<.3,"Thunder uses yellow")
		if ident in [14,21]:check(primary.b>.9 and primary.g>.7 and primary.r<.4,"Ice uses cyan")
		if ident==31:check(primary.g>primary.r and primary.g>primary.b,"Green Flame retains green")
		var fx:Dictionary=preload("res://scripts/spell_visuals.gd").effect(ident,spell)
		check(not fx.is_empty() and int(fx.get("frames",0))>0,"Animated native or fallback effect "+key)
		if int(spell.get("area_radius",0))>0:
			check(spell.allowed_classes.size()==1 and int(spell.allowed_classes[0])==3,"Only Magicians own area magic")
			check(not game.skills_ui.usable(ident) and not game.skills_ui.class_usable(ident),"Non-Magician admins also see area magic locked")
		if ident in [3,16,18,27,37,39,46]:check(fx.get("procedural",false) and int(spell.area_radius)==0,"Converted ability has focused animation")
		game.skills_ui.effects.append({"procedural":true,"style":preload("res://scripts/spell_visuals.gd").style(ident,spell),"color":preload("res://scripts/spell_visuals.gd").color(spell),"frames":6,"loops":1,"at":game.player_world,"kind":"orphan","id":ident,"start":Time.get_ticks_msec()})
	game.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	if not output.is_empty():
		check(gallery.save_png(output.path_join("spell-icons.png"))==OK,"Saved spell gallery")
		check(root.get_texture().get_image().save_png(output.path_join("hud.png"))==OK,"Saved HUD")
		var file:FileAccess=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"result":"failed" if failed else "passed","checks":checks,"viewports":3,"spells":count,"eggs":inventory.size(),"offline":true},"  ")+"\n")
	print("CLASS RUN UI: ",checks," checks, failed=",failed);game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
