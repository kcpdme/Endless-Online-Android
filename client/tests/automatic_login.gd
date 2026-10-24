extends SceneTree
class Vault extends RefCounted:
	var saved: Dictionary = {}
	var fail_save: bool = false
	func available() -> bool:return true
	func save_login(data: Dictionary) -> bool:
		if fail_save:return false
		saved = data.duplicate(true); return true
	func load_login() -> Dictionary:return saved.duplicate(true)
	func forget() -> bool:saved.clear();return true
class Wire extends "res://scripts/online_session.gd":
	var opens: Array[Dictionary] = []
	func open(host: String, port: int) -> Error:
		close();opens.append({"host":host,"port":port});connected=true;return OK
var checks: int = 0
var failed: bool = false
func _initialize() -> void:call_deferred("run")
func check(value: bool, why: String) -> void:
	checks += 1
	if not value: failed = true;push_error(why)
func run() -> void:
	root.size = Vector2i(1544,720)
	var game: Node = load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.music.stop()
	var c: Node = game.online;game.set_process(false);c.set_process(false)
	c.session.queue_free();var wire: Wire=Wire.new();c.add_child(wire);wire.set_process(false);c.session=wire
	var vault: Vault=Vault.new();c.login_store=vault
	var flow: RefCounted=c.character_flow;flow.options_path="user://auto-login-regression.cfg";DirAccess.remove_absolute(flow.options_path)
	flow.remember.show();flow.automatic.show();flow.startup_login_checked=false
	flow.try_startup_login();check(wire.opens.is_empty(),"Automatic sign-in defaults to off")
	flow.automatic.button_pressed=true
	check(flow.remember.button_pressed and not flow.automatic_enabled(),"Opting into automatic sign-in selects Remember but waits for verified login")
	c.auth_credentials={"host":"wss://saved.invalid/ws","port":8079,"username":"devsaved","password":"OnlyATest"}
	c._on_message({"op":"login","ok":false,"error":"Wrong password"})
	check(vault.saved.is_empty() and not flow.automatic_enabled(),"A failed login never saves credentials or enables automatic sign-in")
	c._on_message({"op":"login","ok":true,"data":{"characters":[]}})
	check(vault.saved.password=="OnlyATest" and flow.automatic_enabled(),"Verified opt-in login saves the vault entry and automatic choice")
	var options: String=FileAccess.get_file_as_string(flow.options_path)
	check(not options.contains("OnlyATest") and not options.contains("devsaved") and not options.contains("wss://"),"Automatic settings contain only a flag, never account credentials")
	c.character_box.hide();c.auth_box.show();flow.restore_login()
	check(c.username_field.text=="devsaved" and c.password_field.text=="OnlyATest" and flow.automatic.button_pressed,"Saved login and automatic option are restored")
	wire.close();flow.startup_login_checked=false;flow.try_startup_login()
	check(wire.opens.size()==1 and wire.opens[0].host=="wss://saved.invalid/ws","Startup signs in to the saved server without typing")
	check(c.auth_credentials.password=="OnlyATest" and c.desired_auth=="login","Automatic sign-in uses normal native password authentication")
	flow.try_startup_login();check(wire.opens.size()==1,"Startup sign-in runs only once")
	c._on_message({"op":"login","ok":false,"error_code":2,"error":"Incorrect password"});flow.try_startup_login()
	check(wire.opens.size()==1 and c.panel.visible and c.last_error=="Incorrect password","Authentication failure remains at visible login without an automatic loop")
	c.log_out();flow.try_startup_login()
	check(wire.opens.size()==1 and c.panel.visible and not c.active,"Manual logout does not immediately sign back in")
	flow.restore_login();c.host_field.text="wss://other.invalid/ws";c.host_field.text_changed.emit(c.host_field.text)
	check(c.password_field.text.is_empty() and not flow.automatic.button_pressed,"Changing the server clears the saved password and automatic checkbox")
	flow.startup_login_checked=false;flow.try_startup_login();check(wire.opens.size()==1,"An endpoint edit before startup cannot forward the saved password")
	flow.restore_login();flow.automatic.button_pressed=false
	check(not flow.automatic_enabled() and not vault.saved.is_empty(),"Disabling automatic login keeps the optional saved login")
	flow.automatic.button_pressed=true;c.auth_credentials=vault.saved.duplicate();c._on_message({"op":"login","ok":true,"data":{"characters":[]}})
	flow.restore_login();flow.forget_button.pressed.emit()
	check(vault.saved.is_empty() and c.password_field.text.is_empty() and not flow.automatic_enabled(),"Forget removes the vault login, automatic setting and prefilled password")
	flow.automatic.button_pressed=true;vault.fail_save=true;c.auth_credentials={"host":"wss://saved.invalid/ws","port":8079,"username":"devsaved","password":"OnlyATest"}
	c._on_message({"op":"login","ok":true,"data":{"characters":[]}})
	check(not flow.automatic_enabled() and vault.saved.is_empty(),"A vault write failure cannot enable automatic login")
	flow.restore_login();c.character_box.hide();c.auth_box.show();c.panel.show();game.toast_time=0;game.toast_label.hide()
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not folder.is_empty() and DisplayServer.get_name()!="headless":await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("automatic-login-options.png"))
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"opt_in_verified_login_only":true,"startup_once":true,"no_plaintext_password_settings":true,"endpoint_bound":true,"manual_logout_stays_out":true,"forget_and_disable":true}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var f: FileAccess=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n")
	DirAccess.remove_absolute(flow.options_path);print("AUTOMATIC LOGIN: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
