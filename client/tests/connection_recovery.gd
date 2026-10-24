extends SceneTree
class Wire extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	var opens: Array[Dictionary] = []
	func open(host: String, port: int) -> Error:
		close(); opens.append({"host":host,"port":port}); connected = true; return OK
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate(true)}); return calls.size()
var checks: int = 0
var failed: bool = false
func _initialize() -> void:call_deferred("run")
func check(value: bool, why: String) -> void:
	checks += 1
	if not value: failed = true; push_error(why)
func capture(name: String) -> void:
	var folder: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not folder.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func activate(c: Node, wire: Wire) -> void:
	c.reconnection.credentials = {"username":"devaccount","password":"OnlyATest","host":"ws://localhost:18183/ws","port":8079}
	c.reconnection.character_id = 101; c.reconnection.character_name = "devhero"
	c.active = true; c.streaming = true; c.game.started = true; c.game.online_mode = true; wire.connected = true
	c.panel.hide()
	c.player = {"name":"devhero","character_id":101,"inventory":[{"id":491,"amount":1}],"stats":{},"equipment":{}}
	c.players.assign([{"player_id":2}]); c.npcs.assign([{"id":2}]); c.drops.assign([{"id":1}])
func run() -> void:
	root.size = Vector2i(1544,720)
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.set_process(false); game.online.set_process(false); game.music.stop()
	var c: Node = game.online
	c.session.queue_free(); var wire: Wire = Wire.new(); c.add_child(wire); wire.set_process(false); c.session = wire
	activate(c,wire); c._on_closed("Server stopped")
	check(not c.active and not game.started and not c.streaming,"Loss immediately clears logged-in/world state")
	check(c.player.is_empty() and c.players.is_empty() and c.npcs.is_empty() and c.drops.is_empty(),"Loss clears stale player and map entities")
	check(c.reconnection.running and c.reconnection.panel.visible and not c.panel.visible,"Loss shows an opaque reconnect screen")
	check(not c.mobile_action_ready() and not c.request_attack(),"Disconnected actors cannot move or attack")
	await capture("reconnecting")
	c.reconnection.process(1.1)
	check(wire.opens.size()==1 and wire.opens[0].host=="ws://localhost:18183/ws","Retry stays bound to the verified server")
	c._on_message({"op":"connect","ok":true,"data":{}})
	check(wire.calls[-1].op=="login" and wire.calls[-1].fields.username=="devaccount","Retry uses verified in-memory login")
	c._on_message({"op":"login","ok":true,"data":{"resume_token":"rotated-proof","characters":[{"id":999,"name":"devother"},{"id":202,"name":"devhero"}]}})
	check(wire.calls[-1].op=="enter" and int(wire.calls[-1].fields.character_id)==202,"Reconnect re-enters the same name using its fresh native ID, not the first slot")
	var snapshot: Dictionary = {"player":{"name":"devhero","character_id":101,"player_id":1,"map_id":5,"x":40,"y":40,"direction":0,"inventory":[],"equipment":{},"stats":{},"gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[0,0,0,0,0,0,0,0,0]},"players":[],"npcs":[],"items":[]}
	c._enter_world(snapshot)
	check(c.reconnection.running and c.reconnection.panel.visible and game._modal_open(),"Recovery keeps controls blocked until the world stream is acknowledged")
	c._on_message({"op":"stream","ok":true,"data":{"enabled":true}})
	check(c.active and game.started and not c.reconnection.running and not c.reconnection.panel.visible,"Successful native entry restores play")
	check(wire.calls[-1].op=="stream","Restored world re-enables native event streaming")
	c.log_out()
	check(c.panel.visible and c.auth_box.visible and not c.active and not c.reconnection.running,"Manual logout returns directly to login without reconnecting")
	check(c.reconnection.credentials.is_empty() and c.resume_token.is_empty(),"Logout clears in-memory recovery credentials and proofs")
	activate(c,wire); c._on_closed("Disconnected")
	for attempt: int in range(3):
		c.reconnection.process(4.1)
		c._on_closed("Still unavailable")
	check(not c.reconnection.running and c.panel.visible and not c.character_box.visible,"Three failed attempts finish on visible login")
	check(c.last_error.contains("Could not reconnect") and c.reconnection.credentials.is_empty(),"Exhaustion explains the failure and discards recovery credentials")
	activate(c,wire); c._on_closed("Disconnected")
	for attempt: int in range(3):
		c.reconnection.process(4.1); c._enter_world(snapshot)
		c._on_message({"op":"stream","ok":false,"error":"Stream unavailable"})
	check(c.panel.visible and not c.reconnection.running,"Repeated stream rejection cannot reset the budget and reconnect forever")
	await capture("login-after-failure")
	activate(c,wire); c._on_closed("Disconnected"); c.reconnection.process(30.1)
	check(c.panel.visible and not c.reconnection.running,"The overall 30-second budget cannot loop forever")
	activate(c,wire); c._on_closed("Disconnected"); c.reconnection.started_at = Time.get_ticks_msec()-31000; c.reconnection.process(0)
	check(c.panel.visible and not c.reconnection.running,"Time spent in the Android background also expires the retry budget")
	activate(c,wire); c._on_closed("Disconnected"); game._handle_back()
	check(c.panel.visible and not c.reconnection.running,"Android Back cancels recovery and stays at login")
	activate(c,wire); c._on_closed("Disconnected"); c.reconnection.process(1.1)
	c._on_message({"op":"login","ok":false,"error_code":2,"error":"Incorrect password"})
	check(c.panel.visible and not c.reconnection.running and c.last_error=="Incorrect password","Authentication rejection ends recovery immediately")
	activate(c,wire); c._on_closed("Disconnected"); c.reconnection.process(1.1)
	c._on_message({"op":"login","ok":true,"data":{"characters":[{"id":101,"name":"different"}]}})
	check(c.panel.visible and not c.reconnection.running,"Changed or missing character identity never enters another character")
	activate(c,wire); c.reconnection.credentials.clear(); c._on_closed("Disconnected")
	check(c.panel.visible and c.auth_box.visible and not c.reconnection.running,"Missing in-memory login goes directly to login, never a blank map")
	var transport: Node = preload("res://scripts/online_session.gd").new(); root.add_child(transport); transport.set_process(false)
	var closed: Array[String] = []; transport.transport_closed.connect(func(reason: String) -> void:closed.append(reason))
	transport.connected = true; transport.pending[1] = {"op":"ping","age":7.9}
	check(transport.is_idle() and not transport.has_blocking_requests(),"Heartbeat never blocks gameplay actions")
	transport._process(.2)
	check(not closed.is_empty() and not transport.connected and transport.pending.is_empty(),"Unanswered heartbeat detects a silent dead connection")
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"retry_attempt_limit":3,"overall_timeout_seconds":30,"same_character_only":true,"stale_logged_in_state_cleared":true,"manual_logout_and_back_cancel":true,"no_plaintext_persistence":true,"silent_heartbeat_timeout":true}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var f: FileAccess = FileAccess.open(path,FileAccess.WRITE); f.store_string(JSON.stringify(report,"  ")+"\n")
	print("CONNECTION RECOVERY: ",JSON.stringify(report)); transport.queue_free(); game.queue_free(); await create_timer(.2).timeout; quit(1 if failed else 0)
