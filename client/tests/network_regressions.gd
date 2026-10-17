extends SceneTree
class SessionCapture extends "res://scripts/online_session.gd":
	var calls: Array[String] = []
	var arguments: Array[Dictionary] = []
	func request(operation: String, _fields: Dictionary = {}) -> int:
		calls.append(operation)
		arguments.append(_fields.duplicate())
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
	# Names follow opaque standing art; attack poses must not move labels away.
	var npc_graphics: Dictionary = (game.manifest.characters as Dictionary).npcs as Dictionary
	for id: String in ["2", "35", "54"]:
		var graphic: Dictionary = npc_graphics[id] as Dictionary
		var layout: Dictionary = game.online.npc_name_layout(graphic, "south", false)
		check(is_equal_approx((layout.head as Vector2).y - (layout.name as Vector2).y, 5.0), "NPC name must sit five pixels above visible head")
		var battle: Dictionary = game.online.npc_name_layout(graphic, "south", true)
		check((battle.health as Rect2).end.y < (layout.head as Vector2).y, "Battle strip must fit above head without hiding the name")
	# Short and long peer names share the same body center, including Skylar's
	# asymmetric bow/helmet/offhand loadout; equipment never shifts the label.
	for name: String in ["skylar", "a", "abcdefghijklmnop"]:
		var width: float = ThemeDB.fallback_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var offset: Vector2 = game.online.player_name_offset(name)
		check(is_zero_approx(offset.x + width / 2.0) and is_equal_approx(offset.y, -66.0), "Peer name must center its actual width on the head without changing height")
	# A peer's actual native attack direction drives both swing frames, even
	# when the previously-rendered movement direction differs.
	var peer: Dictionary = {"player_id": 200, "direction": 0, "gender": 1, "race": 0, "hairstyle": 1, "haircolor": 0, "equipment_graphics": [1,0,0,0,1,0,0,0,33]}
	game.online.players.assign([peer])
	game.online._process_events([{"kind": "peer_attack", "player_id": 200, "direction": 2}])
	var animation: Dictionary = game.online.entity_animation("online_player", peer)
	check(animation.state == "attack" and animation.direction == "north" and int(peer.direction) == 2, "Peer swing must use native attack facing immediately")
	var appearance: Dictionary = game.online.character_graphic(peer)
	var first: Dictionary = game._frame(appearance, str(animation.direction), "attack", 0.01)
	var second: Dictionary = game._frame(appearance, str(animation.direction), "attack", 0.20)
	check(not appearance.is_empty() and JSON.stringify(first) != JSON.stringify(second), "Observer must render both original weapon attack frames")
	game.online.peer_attacks[200].until = Time.get_ticks_msec() / 1000.0 - 1.0
	check(game.online.entity_animation("online_player", peer).state == "idle", "Peer animation must finish rather than freeze in an attack pose")
	# Original level thresholds, including the fact that EXP is cumulative.
	game.online.player["level"] = 1
	game.online.player["stats"] = {"experience": 599}
	game._refresh_ui()
	check(is_equal_approx(game.stats_ui.vitals.experience_fraction, 0.5) and game.stats_ui.vitals.level_label == "Lv. 1", "EXP must show halfway between cumulative level thresholds, not a fraction of all lifetime EXP")
	game.stats_ui.vitals.update_experience(2, 1065)
	check(is_zero_approx(game.stats_ui.vitals.experience_fraction), "New level must start an empty next-level bar")
	game.stats_ui.vitals.update_experience(50, 0)
	check(is_zero_approx(game.stats_ui.vitals.experience_fraction), "Operator-granted level with lower EXP cannot draw a negative bar")
	game.stats_ui.vitals.update_experience(250, 2079687500)
	check(game.stats_ui.vitals.exp_label == "MAX", "Level cap must not offer an impossible next level")
	game.chat_ui.open()
	game.chat_ui.channel.select(0)
	game.chat_ui.entry.text = "Nearby regression"
	game.chat_ui.send_message()
	check(not game.chat_ui.panel.visible and capture.calls.has("chat_send"), "Sending Nearby chat closes the modal and sends through the real chat operation")
	game.chat_ui.open()
	game.chat_ui.channel.select(1)
	game.chat_ui.entry.text = "Global regression"
	game.chat_ui.send_message()
	check(game.chat_ui.panel.visible, "Global chat stays open for an ongoing conversation")
	game.chat_ui.close()
	game.online.player["inventory"] = [{"id": 2, "amount": 2}]
	game.online.player["equipment"] = {}
	game.online.bag_action("item:2")
	check(capture.calls.has("item_use"), "Potion bag action must request native item use rather than equipment")
	game.online_mode = true
	game.online.active = true
	game.online.defeated = false
	game.skills_ui.casting.clear()
	game.online.pending_inputs.clear()
	game.online.recovering = false
	game.online.transition_pending = false
	game.online.walk_clock = 0.0
	game.moving = false
	game.attack_clock = 0.0
	game.player_tile = Vector2i(40, 40)
	game.facing = "west"
	game.online.npcs.assign([{"id": 2, "index": 77, "x": 41, "y": 40}, {"id": 2, "index": 78, "x": 40, "y": 41}])
	var position_before: Vector2i = game.player_tile
	game.online.request_step(Vector2i(1, 0))
	check(game.facing == "east" and game.player_tile == position_before and capture.calls[-1] == "face", "Blocked NPC must allow turning without walking through it")
	game.facing = "north"
	game.online.request_attack()
	check(int(capture.arguments[-1].direction) == 2 and game.facing == "north", "Attack must not auto-redirect to another adjacent NPC")
	game.damage_numbers.clear()
	game.online.npcs.clear()
	game.online.previous_npc_tiles[77] = Vector2i(41, 40)
	game._toast("keep")
	game.online._process_events([{"kind": "npc_killed", "npc_index": 77, "player_id": 1, "damage": 12345, "drop": {"uid": 0}}])
	check(game.damage_numbers.size() == 1 and str(game.damage_numbers[0].value) == "12345", "Killing blow must retain the full server damage after NPC removal")
	check(game.toast_label.text == "keep", "Enemy kills must not generate notifications")
	game.online._process_events([{"kind": "npc_damage", "npc_index": 77, "damage": 0, "hp_percent": 100}])
	check(str(game.damage_numbers[-1].value) == "Miss", "Native zero damage must show Miss")
	game.started = false
	game.queue_free()
	await process_frame
	if not failed: print("NETWORK REGRESSIONS PASS: committed-tile release, visual/server alignment, deferred loot intent")
	quit(1 if failed else 0)
