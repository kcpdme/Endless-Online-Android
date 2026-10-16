extends SceneTree
class SessionCapture extends "res://scripts/online_session.gd":
	var calls: Array[String] = []
	func request(operation: String, _fields: Dictionary = {}) -> int:
		calls.append(operation)
		return calls.size()
var failed: bool = false
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _run() -> void:
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.online.set_process(false)
	game.online.session.set_process(false)
	game.welcome.hide()
	game.online_mode = true
	game.started = true
	game.online.active = true
	game.online.streaming = true
	game.online._start_step(Vector2i(41, 40), "east")
	game.step_progress = 0.5
	game.player_world = game.step_from.lerp(game.step_to, 0.5)
	var halfway: Vector2 = game.player_world
	game._cancel_movement()
	check(game.stick == Vector2.ZERO and game.route.is_empty(), "Release must immediately clear future input")
	check(game.moving and game.player_world == halfway, "Online release must finish the committed tile instead of freezing halfway")
	game._process(0.21)
	check(game.player_world.distance_to(game.tile_position(game.player_tile)) < 0.01, "Rendered and committed tile positions must agree after release")
	var capture: SessionCapture = SessionCapture.new()
	capture.set_process(false)
	game.online.session.queue_free()
	game.online.add_child(capture)
	capture.set_process(false)
	game.online.session = capture
	game.online.pending_inputs.append({"seq": 1, "direction": Vector2i(1, 0), "sent_at": Time.get_ticks_msec()})
	check(game.online.request_attack() and capture.calls.has("strike"), "Completed walk animation must not require an extra network round trip before attacking")
	game.online.pending_inputs.clear()
	# A loot intent must survive a movement confirmation, including an active stick.
	game.online.collect_nearby()
	game.stick = Vector2(1, 0)
	game.online._process_interaction()
	check(game.online.collect_pending, "Moving must defer a pickup intent rather than erase it")
	check(game.online.npc_health_fraction(42) < 0.0, "Idle NPC must not show a health strip")
	game.online._process_events([{"kind": "npc_damage", "npc_index": 42, "hp_percent": 37, "damage": 6}])
	check(is_equal_approx(game.online.npc_health_fraction(42), 0.37), "Battle strip must use native remaining HP, not a guessed damage total")
	game.online.npc_health[42]["until"] = Time.get_ticks_msec() - 1
	check(game.online.npc_health_fraction(42) < 0.0, "Battle strip must hide when combat times out")
	game.online.npc_health[42] = {"percent": 50, "until": Time.get_ticks_msec() + 8000}
	game.online._process_events([{"kind": "npc_killed", "npc_index": 42, "damage": 5}])
	check(not game.online.npc_health.has(42), "Killed NPC must not retain health on its next spawn")
	check((game.hud_root.get_node("GoldIcon") as TextureRect).texture != null, "Gold HUD must use original item artwork")
	game.online_mode = false
	game.started = false
	game.queue_free()
	await process_frame
	if not failed: print("NETWORK REGRESSIONS PASS: committed-tile release, visual/server alignment, deferred loot intent")
	quit(1 if failed else 0)
