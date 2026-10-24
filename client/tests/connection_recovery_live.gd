extends SceneTree
class Vault extends RefCounted:
	var saved: Dictionary = {}
	func available() -> bool:return true
	func save_login(data: Dictionary) -> bool:saved=data.duplicate(true);return true
	func load_login() -> Dictionary:return saved.duplicate(true)
	func forget() -> bool:saved.clear();return true
var game: Node
var folder: String
var checks: int = 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks += 1
	if not ok: push_error(why); quit(1)
	return ok
func wait_for(test: Callable, seconds: float = 38.0) -> bool:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call():return true
		await process_frame
	return false
func mark(name: String) -> void:
	var file: FileAccess = FileAccess.open(folder.path_join(name),FileAccess.WRITE); file.store_string("ready")
func letters() -> String:
	var name: String = "dev"
	for i: int in range(8):name += String.chr(97+randi_range(0,25))
	return name
func run() -> void:
	folder = OS.get_environment("ASTER_VALE_RECOVERY_CONTROL")
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	var c: Node = game.online; var account: String = letters(); var password: String = "Dev"+letters()+"42"
	var vault: Vault = Vault.new(); c.login_store=vault
	c.character_flow.options_path="user://automatic-login-live.cfg"
	c.character_flow.remember.set_pressed_no_signal(true);c.character_flow.automatic.set_pressed_no_signal(true)
	c.session.transport_closed.connect(func(reason: String) -> void: print("RECOVERY TRACE closed=",reason," attempt=",c.reconnection.attempts))
	c.session.message_received.connect(func(message: Dictionary) -> void:
		var op: String = str(message.get("op",message.get("event","")))
		if op in ["connect","login","enter","stream","ping"]: print("RECOVERY TRACE op=",op," ok=",message.get("ok",true)," code=",message.get("error_code",0)," error=",message.get("error","")," active=",c.active," recovering=",c.reconnection.running)
	)
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST"); c.username_field.text = account; c.password_field.text = password; c._authenticate("register")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Native registration/login failed"):return
	c.character_name_field.text = letters(); c._create_character()
	if not check(await wait_for(func() -> bool:return c.selected_characters.size()==1),"Native character creation failed"):return
	c._enter_selected()
	if not check(await wait_for(func() -> bool:return c.active and c.streaming),"Native entry failed"):return
	var name: String = str(c.player.name)
	var inventory: String = JSON.stringify(c.player.inventory)
	check(not c.reconnection.credentials.is_empty() and c.password_field.text.is_empty(),"Verified login is retained only in recovery memory")
	# A fresh game scene uses the saved vault and startup option, without typing.
	c.session.close();game.queue_free();await process_frame;await create_timer(.8).timeout
	game=load("res://main.tscn").instantiate();root.add_child(game);c=game.online
	c.login_store=vault;c.character_flow.options_path="user://automatic-login-live.cfg";c.character_flow.restore_login()
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Automatic startup sign-in did not reach native character selection"):return
	check(c.password_field.text.is_empty() and c.character_flow.startup_login_checked,"Automatic sign-in clears its password field after native authentication")
	for index: int in range(c.selected_characters.size()):
		if str(c.selected_characters[index].name)==name:c.character_list.select(index)
	c._enter_selected()
	if not check(await wait_for(func() -> bool:return c.active and c.streaming),"Native entry after automatic sign-in failed"):return
	mark("restart-ready")
	if not check(await wait_for(func() -> bool:return c.reconnection.running),"Native shutdown did not trigger recovery"):return
	check(not c.active and c.player.is_empty() and c.reconnection.panel.visible,"Native shutdown clears player and opens recovery screen")
	if not check(await wait_for(func() -> bool:return c.active and c.streaming),"Native restart did not restore session"):return
	check(c.player.name==name and JSON.stringify(c.player.inventory)==inventory,"Native restart restores the same saved character and items")
	mark("blackhole-ready")
	if not check(await wait_for(func() -> bool:return c.reconnection.running,20),"Silent WebSocket blackhole was not detected by heartbeat"):return
	mark("blackhole-detected")
	if not check(await wait_for(func() -> bool:return c.active and c.streaming),"Transport recovery did not restore session"):return
	check(c.player.name==name,"Transport recovery retains the same character despite a new native ID")
	mark("offline-ready")
	if not check(await wait_for(func() -> bool:return c.panel.visible and not c.reconnection.running and not c.active,40),"Permanent outage did not return to login"):return
	check(not game.started and c.player.is_empty() and c.auth_box.visible and not c.character_box.visible,"Permanent outage has visible login with no stale world state")
	check(c.reconnection.credentials.is_empty() and c.last_error.contains("Could not reconnect"),"Permanent outage clears recovery secrets and explains logout")
	var report: Dictionary = {"result":"passed","checks":checks,"automatic_startup_native_login":true,"real_native_world_restart":true,"real_silent_websocket_blackhole":true,"native_reauthentication_and_same_character_entry":true,"inventory_preserved":true,"permanent_outage_returns_to_login":true,"no_operator_account_used":true}
	var f: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"  ")+"\n")
	print("CONNECTION RECOVERY LIVE: ",JSON.stringify(report)); game.queue_free(); await create_timer(.2).timeout; quit()
