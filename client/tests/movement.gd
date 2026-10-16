extends SceneTree
## Prediction/reconciliation regression. Pure synthetic snapshots; no account or disk writes.
var game: Node
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, reason: String) -> void:
	if not condition:
		failed = true
		push_error(reason)

func _run() -> void:
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.started = false
	game.online_mode = true
	var c: Node = game.online
	c.active = true
	c.streaming = true
	var me: Dictionary = {"name": "devfixture", "player_id": 100, "map_id": 5, "x": 40, "y": 40, "direction": 3}
	c._apply_snapshot({"player": me.duplicate(), "players": [], "npcs": [], "items": []}, true)
	# Simulate 300 ms+ RTT: two predictions coexist before the first server acknowledgement.
	c.pending_inputs.assign([{"seq": 1, "direction": Vector2i(1, 0), "sent_at": Time.get_ticks_msec()}, {"seq": 2, "direction": Vector2i(1, 0), "sent_at": Time.get_ticks_msec()}])
	c._start_step(Vector2i(42, 40), "east")
	game.player_world = game.step_from.lerp(game.step_to, 0.5)
	game.step_progress = 0.5
	var visual: Vector2 = game.player_world
	me.x = 41
	c._apply_snapshot({"player": me.duplicate(), "position_seq": 1, "position_update": true})
	check(game.player_tile == Vector2i(42, 40) and game.player_world == visual and game.step_progress == 0.5, "ACK must replay in-flight input without restarting animation")
	check(c.pending_inputs.size() == 1, "Only acknowledged predictions may be discarded")
	# A peer/NPC event contains authoritative self metadata but cannot rewind predicted motion.
	c._apply_snapshot({"player": me.duplicate(), "position_update": false})
	check(game.player_tile == Vector2i(42, 40) and game.player_world == visual, "Peer-only updates must preserve local prediction")
	me.x = 42
	c._apply_snapshot({"player": me.duplicate(), "position_seq": 2, "position_update": true})
	check(c.pending_inputs.is_empty() and not c.waiting_for_walk, "Native acknowledgement must settle prediction")
	# Real server rejects a collision. Return to authoritative tile, clear queued route.
	c.pending_inputs.assign([{"seq": 3, "direction": Vector2i(1, 0), "sent_at": Time.get_ticks_msec()}])
	c._start_step(Vector2i(43, 40), "east")
	game.route.append(Vector2i(44, 40))
	c._apply_snapshot({"player": me.duplicate(), "position_seq": 3, "position_update": true, "correction": true})
	check(game.player_tile == Vector2i(42, 40) and game.route.is_empty() and c.pending_inputs.is_empty(), "Rejected move must reconcile to the authoritative tile")
	# Nearby entities interpolate independently of the local player's idle/moving flag.
	game.moving = false
	var peer: Dictionary = {"player_id": 200, "x": 40, "y": 41}
	c._track_entities("player", c._dict_array([peer]), "player_id")
	var origin: Vector2 = game.tile_position(Vector2i(40, 41))
	peer.x = 41
	c._track_entities("player", c._dict_array([peer]), "player_id")
	c.remote_motion["player:200"].start = Time.get_ticks_msec() / 1000.0 - 0.21
	var halfway: Vector2 = c._remote_position("player:200", Vector2.ZERO)
	check(halfway.distance_to(origin.lerp(game.tile_position(Vector2i(41, 41)), 0.5)) < 0.2, "Remote movement must interpolate rather than teleport")
	c._track_entities("player", c._dict_array([]), "player_id")
	check(not c.remote_motion.has("player:200"), "Departed entities must release movement tracks")
	# Input releases still stop local movement immediately.
	game._cancel_controls()
	check(not game.moving and game.stick == Vector2.ZERO, "Releasing controls must stop movement")
	game.online_mode = false
	game.queue_free()
	await process_frame
	if not failed: print("MOVEMENT PASS: immediate prediction, in-flight replay, no ACK rewind, authoritative correction, remote interpolation, immediate stop")
	quit(1 if failed else 0)
