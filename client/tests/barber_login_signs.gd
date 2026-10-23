extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary]=[]
	func request(op: String, fields: Dictionary={}) -> int:
		serial+=1;calls.append({"op":op,"fields":fields.duplicate()});return serial
class Bridge extends RefCounted:
	var encoded: String=""
	func loadCredentials() -> String:return encoded
class Vault extends RefCounted:
	var saved: Dictionary={}
	func available() -> bool:return true
	func save_login(data: Dictionary) -> bool:saved=data.duplicate(true);return true
	func load_login() -> Dictionary:return saved.duplicate(true)
	func forget() -> bool:saved.clear();return true
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(why)
func tap(control: Control) -> void:
	await process_frame;await process_frame
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=88;e.position=root.get_final_transform()*control.get_global_rect().get_center();e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func shot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1600,720)
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.music.stop()
	var c: Node=game.online
	check(c.panel.visible and not game.started and not game.welcome.visible,"Startup is direct fullscreen login without a welcome game dialog")
	check(c.panel.color.a==1 and c.auth_box.visible,"Login backdrop is opaque")
	check(ResourceLoader.exists(str(game.manifest.login_art.path)),"Original EO title art is present")
	await shot("login-original")
	c.session.queue_free();var wire: Capture=Capture.new();c.add_child(wire);wire.set_process(false);c.session=wire
	var store: RefCounted=preload("res://scripts/login_store.gd").new();var bridge: Bridge=Bridge.new();store.backend=bridge
	check(store.load_login().is_empty(),"Empty Android credential store starts without a JSON error")
	bridge.encoded="{invalid";check(store.load_login().is_empty(),"Invalid saved login is ignored without breaking startup")
	var vault: Vault=Vault.new();c.login_store=vault;c.character_flow.remember.show();c.character_flow.remember.set_pressed_no_signal(true)
	c.auth_credentials={"host":"wss://example.invalid/ws","port":8079,"username":"devlogin","password":"FixturePassword"}
	c._on_message({"op":"login","ok":false,"error":"Invalid login"});check(vault.saved.is_empty(),"Failed login never saves a password")
	c._on_message({"op":"login","ok":true,"data":{"characters":[]}})
	check(vault.saved.password=="FixturePassword" and c.password_field.text.is_empty() and c.auth_credentials.is_empty(),"Only successful native login saves opt-in credentials and clears transient copies")
	c.character_flow.restore_login();check(c.username_field.text=="devlogin" and c.password_field.text=="FixturePassword" and not c.character_flow.restored_login.has("password"),"Saved login restores host, account and password")
	c.host_field.text="wss://other.invalid/ws";c.host_field.text_changed.emit(c.host_field.text);check(c.password_field.text.is_empty() and not c.character_flow.remember.button_pressed,"Changing endpoint never sends the stored password to another host")
	c.character_box.hide();c.auth_box.show();c.character_flow.restore_login();await tap(c.character_flow.forget_button);check(vault.saved.is_empty() and c.password_field.text.is_empty() and c.character_flow.restored_login.is_empty(),"Forget erases saved login and prefilled password")
	game.toast_time=0;game.toast_label.hide()
	c.panel.hide();game.started=true;game.online_mode=true;c.active=true;c.streaming=true
	c.player={"name":"devfixture","player_id":100,"character_id":1,"map_id":5,"x":40,"y":40,"level":5,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"hairstyle":1,"haircolor":0,"gender":1,"race":0,"equipment_graphics":[0,0,0,0,0,0,0,0,0],"inventory":[{"id":1,"amount":5000}],"spells":[],"equipment":{}}
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);c.npcs.assign([{"id":32,"index":7,"x":40,"y":39}])
	c.map_click(Vector2i(40,39),"npc");c._process_interaction();check(wire.calls.back().op=="barber_open","Babs dispatches native haircutter service")
	c._on_message({"op":"barber_open","ok":true,"data":{"barber":{"map_id":5,"npc_id":32,"npc_index":7,"price":1000,"max_style":20,"max_color":9}}})
	var ui: RefCounted=game.world_services;check(ui.barber_panel.visible and game._modal_open(),"Haircutter opens a movement-blocking preview")
	ui.style.select(20);ui.color.select(9);ui.update_preview();check(int(c.player.hairstyle)==1 and ui.preview.appearance.hairstyle==20,"Hair preview does not mutate player before purchase")
	await shot("barber-preview")
	await tap(ui.buy);check(ui.confirm.visible and wire.calls.back().op=="barber_open","Haircut asks before spending Gold")
	ui.confirm.hide();ui.confirm.confirmed.emit();check(wire.calls.back()=={"op":"barber_buy","fields":{"style":20,"color":9}},"Purchase sends chosen style and color")
	check(c.bag_amount(1)==5000 and c.player.hairstyle==1,"No optimistic spending or haircut")
	game._handle_back();check(not ui.barber_panel.visible and wire.calls.back().op=="barber_close","Back closes barber context")
	var signs: int=0
	for path: String in game.manifest.map_paths.values():
		var map: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		for sign: Dictionary in map.get("signs",[]):
			ui.open_sign(sign);check(not ui.sign_text.text.is_empty() and ui.sign_panel.visible,"Every imported sign has readable original body text");signs+=1
	check(signs>50,"All road signs are covered")
	ui.open_sign({"text":"Road SignRoad to Beach, Castle and Sky Wonder. (level 8)","title_length":9});check(ui.sign_title.text=="Road Sign" and ui.sign_text.text.begins_with("Road to Beach"),"Sign title and body use original length boundary")
	await shot("road-sign")
	game._handle_back();check(not ui.sign_panel.visible,"Back dismisses road sign")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"original_signs_read":signs,"direct_fullscreen_login":true,"opt_in_verified_login_only":true,"endpoint_bound_password_prefill":true,"forget_saved_login":true,"barber_preview_confirm_native_only":true}
	var out: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);out.store_string(JSON.stringify(report,"  ")+"\n");print("BARBER LOGIN SIGNS: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
