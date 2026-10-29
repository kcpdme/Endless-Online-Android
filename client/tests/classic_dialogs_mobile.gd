extends SceneTree
## Offline rendered fixtures: classic panels, modal input, HUD and attack preference.
class Wire extends "res://scripts/online_session.gd":
	var calls:Array[Dictionary]=[]
	func request(op:String,fields:Dictionary={})->int:
		calls.append({"op":op,"fields":fields.duplicate()});return calls.size()
class Probe extends "res://scripts/main.gd":
	var paths:int=0
	var strikes:int=0
	func _request_path(_at:Vector2i)->void:paths+=1
	func _attack()->void:strikes+=1;attack_clock=.52
var game:Probe
var checks:int=0
var failed:bool=false
var output:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func touch(at:Vector2,pressed:bool,index:int=61)->void:
	var e:InputEventScreenTouch=InputEventScreenTouch.new();e.index=index;e.position=at;e.pressed=pressed
	Input.parse_input_event(e);await process_frame;await process_frame
func mouse(at:Vector2,pressed:bool,emulated:bool=false)->void:
	var e:InputEventMouseButton=InputEventMouseButton.new();e.position=at;e.pressed=pressed;e.button_index=MOUSE_BUTTON_LEFT
	if emulated:e.device=InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(e);await process_frame;await process_frame
func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Saved "+name)
func hide_dialogs()->void:
	for card:Control in game.modal_cards:card.get_parent().hide()
	# Reset the in-memory fixture without sending a real service-close request.
	game.services_ui.mode=""
	game.modal_input_until=0
func layout()->void:
	game._layout_dialogs();await process_frame;await process_frame
func run()->void:
	output=OS.get_environment("ASTER_VALE_CLASSIC_UI_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1544,720)
	game=Probe.new();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.enabled=false;game.music.stop()
	game.online.session.queue_free();var wire:Wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	hide_dialogs();game.started=true;game.online_mode=true;game.online.active=true;game.online.streaming=true
	game.online.player={"player_id":9000,"name":"Offline fixture","x":40,"y":40,"gender":1,"race":0,"hairstyle":7,"haircolor":4,"equipment_graphics":[1,0,0,0,1,0,0,0,4],"hp":500,"max_hp":500,"tp":100,"max_tp":100,"spells":[],"inventory":[],"stats":{"class_id":7,"level":50,"stat_points":0}}
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	game.combat_settings_path="user://combat-ui-fixture.cfg";game.auto_attack_enabled=true
	game._refresh_auto_attack_mode();game._process(0);await process_frame
	var controls:Array[Control]=[game.zoom_button,game.admin_ui.button,game.party_ui.button,game.skills_ui.buttons[2],game.quest_journal.button,game.stats_button,game.character_button,game.menu_button,game.pet_ui.collection_button,game.bag_button,game.auto_attack_button,game.sit_button,game.attack_button,game.pet_ui.button,game.online.loot_button]
	for dimensions:Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame;game._layout_safe_area();game._process(0)
		for index:int in range(controls.size()):
			var rect:Rect2=controls[index].get_global_rect()
			check(game.get_viewport_rect().encloses(rect),"HUD control fits "+str(dimensions)+" #"+str(index))
			for other:int in range(index+1,controls.size()):
				var other_rect:Rect2=controls[other].get_global_rect()
				check(not rect.intersects(other_rect) or rect.get_center().distance_to(other_rect.get_center())>(rect.size.x+other_rect.size.x)/2.0,"Circular HUD targets stay separate #"+str(index)+"/"+str(other))
		check(game.stats_button.position.x>game.quest_journal.button.position.x and game.stats_button.position.x<game.character_button.position.x,"Stats is between quests and character")
		for entry:Dictionary in [{"name":"paperdoll","panel":game.character_panel},{"name":"inventory","panel":game.inventory},{"name":"stats","panel":game.stats_ui.panel},{"name":"shop","panel":game.shop_ui.panel},{"name":"quest","panel":game.quest_ui.panel},{"name":"journal","panel":game.quest_journal.panel},{"name":"pet","panel":game.pet_ui.panel}]:
			hide_dialogs();entry.panel.show();await layout()
			var card:Control=entry.panel.get_child(0)
			check(game.get_viewport_rect().encloses(card.get_global_rect()),str(entry.name)+" fits "+str(dimensions))
			check(entry.panel.color.a==0 and entry.panel.mouse_filter==Control.MOUSE_FILTER_STOP,"World stays undimmed with modal input protection")
			if entry.name!="paperdoll":check(card.get_theme_stylebox("panel") is StyleBoxTexture,"Original EO frame used for "+str(entry.name))
			else:
				check(card.get_child_count()==1 and card.get_child(0)==game.paperdoll,"Paperdoll keeps only original graphic and its native controls")
				check((game.paperdoll.get_node("ClassicOk") as Button).get_theme_stylebox("normal") is StyleBoxFlat and (game.paperdoll.get_node("ClassicOk") as Button).get_theme_stylebox("normal").bg_color.a==0,"Native paperdoll OK artwork remains visible beneath its transparent target")
		for mode:String in ["bank","locker","chest","trade"]:
			hide_dialogs();game.services_ui.open(mode,{"gold":12000,"items":[],"offers":{},"name":"Offline partner"});await layout()
			check(game.get_viewport_rect().encloses(game.services_ui.card.get_global_rect()),mode+" fits "+str(dimensions))
			check(game.services_ui.card.get_meta("classic_dialog_kind")==("shop" if mode=="locker" else mode),"Uses original "+mode+" frame")
		hide_dialogs()
	# Input outside an alpha-zero modal is still owned by the UI, never the world.
	root.size=Vector2i(1544,720);await process_frame
	game.character_panel.show();await layout()
	var before_paths:int=game.paths;var before_strikes:int=game.strikes
	await touch(Vector2(1500,400),true);await touch(Vector2(1500,400),false)
	await mouse(Vector2(1500,400),true);await mouse(Vector2(1500,400),false)
	check(game.paths==before_paths and game.strikes==before_strikes and wire.calls.is_empty(),"Undimmed modal blocks touch/mouse world actions and server requests")
	# Compare a world pixel far outside the panel, without any moving HUD control.
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var with_panel:Color=root.get_texture().get_image().get_pixel(1500,400)
		game.character_panel.hide();await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_pixel(1500,400).is_equal_approx(with_panel),"Opening panel does not darken the world")
	game._process(0)
	var stats_at:Vector2=game.stats_button.get_global_rect().get_center()
	await mouse(stats_at,true,true);check(not game.stats_ui.panel.visible,"Synthetic mouse waits for native Stats touch")
	await touch(stats_at,true);await touch(stats_at,false);await mouse(stats_at,false,true)
	check(game.stats_ui.panel.visible and not game.character_panel.visible,"Top Stats touch opens the separate attribute dialog once")
	game.stats_ui.close_stats();game._process(0)
	await mouse(stats_at,true);await mouse(stats_at,false)
	check(game.stats_ui.panel.visible and not game.character_panel.visible,"Desktop Stats click opens only Stats")
	game.stats_ui.close_stats();game._process(0)
	var auto_at:Vector2=game.auto_attack_button.get_global_rect().get_center()
	await mouse(auto_at,true,true);check(game.auto_attack_enabled,"Synthetic mouse cannot double-toggle auto mode")
	await touch(auto_at,true);await touch(auto_at,false);await mouse(auto_at,false,true)
	check(not game.auto_attack_enabled and not game.auto_attack_button.button_pressed,"Small HUD toggle disables auto attack")
	game._begin_attack(77);game.attack_held_at=Time.get_ticks_msec()-700;game.attack_clock=0;game._process(0)
	check(not game.auto_attack and not game.attack_hold_can_latch,"Long manual hold cannot latch auto attack")
	game._end_attack_gesture();var manual_strikes:int=game.strikes;game._process(1)
	check(game.strikes==manual_strikes,"Manual attacks stop on release")
	game.auto_attack_enabled=true;game._load_combat_settings();check(not game.auto_attack_enabled,"Manual mode survives settings reload")
	await mouse(auto_at,true);await mouse(auto_at,false)
	check(game.auto_attack_enabled and game.auto_attack_button.button_pressed,"Desktop click enables auto attack once")
	game._begin_attack(78);game.attack_held_at=Time.get_ticks_msec()-700;game._process(0);game._end_attack_gesture()
	check(game.auto_attack and game.attack_button.automatic,"Enabled long press latches auto attack after release")
	var auto_strikes:int=game.strikes;game._process(1)
	check(game.strikes==auto_strikes+1,"Latched mode continues attacking after release")
	game._toggle_auto_attack_mode()
	check(not game.auto_attack and not game.attack_button.automatic and game.attack_touch_id==-1,"Disabling clears a running latch immediately")
	game._toggle_auto_attack_mode();game._begin_attack(79);game.attack_held_at=Time.get_ticks_msec()-700;game._process(0);game._end_attack_gesture();game.inventory.show()
	check(not game.auto_attack and game.attack_touch_id==-1,"Opening a dialog cancels combat even with auto enabled")
	check(wire.calls.is_empty() and game.paths==before_paths,"All HUD and combat fixtures stay offline")
	hide_dialogs();game._process(0);game.chat_ui.tick();game.toast_label.hide()
	game.online.player.level=50;game.online.player.stats.weight=20;game.online.player.stats.max_weight=100
	game.online.player.inventory=[{"id":1,"amount":100000},{"id":21,"amount":2},{"id":80,"amount":1},{"id":143,"amount":1}]
	game.online._sync_inventory();game.online.refresh_game_ui();await capture("hud")
	game.character_panel.show();await layout();await capture("paperdoll")
	game.character_panel.hide();game.stats_ui.show_stats();await layout();await capture("stats")
	hide_dialogs();game.inventory.show();await layout();await capture("inventory")
	hide_dialogs();game.shop_ui.open({"name":"Egg shop","items":[],"buy":[],"sell":[],"craft":[]});await layout();await capture("shop")
	for mode:String in ["trade","bank","locker","chest"]:
		hide_dialogs();game.services_ui.open(mode,{"gold":12000,"items":[],"offers":{},"name":"Offline partner"});await layout();await capture(mode)
	hide_dialogs();game.quest_journal.receive({"quest_journal":{"page":"progress","entries":[{"name":"Newbie Island","description":"Explore the island and collect supplies for your first dagger.","progress":2,"target":5}]}});game.quest_journal.panel.show();await layout();await capture("quests")
	hide_dialogs();game.quest_ui.receive({"quest_dialog":{"npc_id":1,"npc_index":1,"quest_id":1,"quests":[{"id":1,"name":"A new adventure"}],"pages":["Welcome, traveller. Explore the island, collect your first supplies, and speak to the captain when you are ready to sail."],"links":[]}});await layout();await capture("quest-dialog")
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"viewports":3,"rendered":DisplayServer.get_name()!="headless","network_requests":wire.calls.size(),"world_undimmed":true,"original_eo_frames":6,"attack_preference_persists":true}
	if not output.is_empty():var file:FileAccess=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("CLASSIC DIALOGS/HUD: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
