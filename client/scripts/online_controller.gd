extends Node
## Owns online UI/session state. No passwords, server position, or items enter the offline save.
const OnlineSession = preload("res://scripts/online_session.gd")
var game: Node
var session: OnlineSession
var panel: Control
var status_label: Label
var server_label: Label
var host_field: LineEdit
var port_field: SpinBox
var username_field: LineEdit
var password_field: LineEdit
var character_name_field: LineEdit
var character_list: ItemList
var auth_box: Control
var character_box: Control
var selected_characters: Array[Dictionary] = []
var active: bool = false
var waiting_for_walk: bool = false
const MOVE_SECONDS: float = 0.42
const MAX_PREDICTIONS: int = 4
var streaming: bool = false
var recovering: bool = false
var defeated: bool = false
var npc_attack_until: Dictionary = {}
var transition_pending: bool = false
var next_input_seq: int = 0
var confirmed_input_seq: int = 0
var pending_inputs: Array[Dictionary] = []
var remote_motion: Dictionary = {}
var refresh_clock: float = 0.0
var walk_clock: float = 0.0
var desired_auth: String = "login"
var offline_state: Dictionary = {}
var offline_map_id: int = 5
var player: Dictionary = {}
var players: Array[Dictionary] = []
var npcs: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var last_error: String = ""
var diagonal_toggle: bool = false
var warp_notice_clock: float = 0.0
var catalog: Dictionary = {}
var request_operations: Dictionary = {}
var interaction: Dictionary = {}
var collect_pending: bool = false
var loot_attempt_after: Dictionary = {}

func _ready() -> void:
	session = OnlineSession.new()
	add_child(session)
	session.transport_connected.connect(func() -> void:
		_set_status("Contacting the world server…")
		session.request("connect")
	)
	session.message_received.connect(_on_message)
	session.transport_closed.connect(_on_closed)
	if FileAccess.file_exists("res://content/catalog.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/catalog.json"))
		if parsed is Dictionary: catalog = parsed as Dictionary

func build_ui(parent: Control) -> void:
	panel = game._modal(parent, Vector2(760, 606))
	var card: Control = panel.get_child(0) as Control
	game._label(card, "YOUR OWN ONLINE WORLD", Vector2(30, 20), 13, game.GOLD)
	game._label(card, "Play online", Vector2(28, 49), 34)
	game._button(card, "×", Vector2(674, 20), Vector2(56, 52), _close_panel)
	game._label(card, "Server address", Vector2(30, 105), 15, game.MUTED)
	host_field = _field(card, "wss://eo.kcpd.top/ws", Vector2(30, 130), Vector2(530, 48))
	host_field.placeholder_text = "Server hostname or wss://…/ws"
	host_field.text_changed.connect(func(value: String) -> void:
		if port_field != null: port_field.editable = not (value.begins_with("ws://") or value.begins_with("wss://"))
	)
	port_field = SpinBox.new()
	port_field.position = Vector2(574, 130)
	port_field.size = Vector2(156, 48)
	port_field.min_value = 1
	port_field.max_value = 65535
	port_field.value = 8079
	port_field.editable = false
	card.add_child(port_field)
	auth_box = Control.new()
	auth_box.position = Vector2(30, 200)
	card.add_child(auth_box)
	game._label(auth_box, "Account", Vector2.ZERO, 15, game.MUTED)
	username_field = _field(auth_box, "", Vector2(0, 28), Vector2(700, 48))
	username_field.placeholder_text = "Account name"
	username_field.max_length = 16
	game._label(auth_box, "Password", Vector2(0, 89), 15, game.MUTED)
	password_field = _field(auth_box, "", Vector2(0, 117), Vector2(700, 48))
	password_field.placeholder_text = "Password — never saved on this device"
	password_field.secret = true
	password_field.max_length = 64
	game._button(auth_box, "Log in", Vector2(0, 188), Vector2(340, 56), func() -> void: _authenticate("login"), true)
	game._button(auth_box, "Create account", Vector2(356, 188), Vector2(344, 56), func() -> void: _authenticate("register"))
	character_box = Control.new()
	character_box.position = Vector2(30, 200)
	card.add_child(character_box)
	character_list = ItemList.new()
	character_list.size = Vector2(700, 118)
	character_list.add_theme_font_size_override("font_size", 22)
	character_list.fixed_icon_size = Vector2i(32, 32)
	character_box.add_child(character_list)
	game._button(character_box, "Enter selected character", Vector2(0, 132), Vector2(700, 52), _enter_selected, true)
	character_name_field = _field(character_box, "", Vector2(0, 199), Vector2(410, 48))
	character_name_field.placeholder_text = "New character name"
	character_name_field.max_length = 12
	game._button(character_box, "Create character", Vector2(426, 199), Vector2(274, 48), _create_character)
	character_box.hide()
	status_label = game._label(card, "Connect to your world or create a new account.", Vector2(30, 479), 17, game.TEXT)
	status_label.size = Vector2(700, 61)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._label(card, "Offline progress stays separate from your online characters.", Vector2(30, 553), 14, game.MUTED)
	panel.hide()
	server_label = game._label(parent, "", Vector2(390, 67), 15, game.MUTED)
	server_label.hide()

func _field(parent: Node, value: String, at: Vector2, dimensions: Vector2) -> LineEdit:
	var field: LineEdit = LineEdit.new()
	field.text = value
	field.position = at
	field.size = dimensions
	field.add_theme_font_size_override("font_size", 20)
	parent.add_child(field)
	return field

func show_login() -> void:
	if active:
		game.welcome.hide()
		panel.hide()
		game.started = true
		return
	game._cancel_controls()
	game.welcome.hide()
	if not session.connected:
		auth_box.show()
		character_box.hide()
		selected_characters.clear()
		character_list.clear()
		password_field.text = ""
		_set_status("Connect to your world or create a new account.")
	panel.show()

func _close_panel() -> void:
	panel.hide()
	if not active: game._show_welcome()

func _authenticate(operation: String) -> void:
	if username_field.text.strip_edges().is_empty() or password_field.text.is_empty():
		_set_status("Enter an account name and password.")
		return
	desired_auth = operation
	active = false
	character_box.hide()
	auth_box.show()
	_set_status("Connecting…")
	var error: Error = session.open(host_field.text.strip_edges(), int(port_field.value))
	if error != OK: _set_status("Could not open this server address.")

func _set_status(value: String) -> void:
	last_error = value
	if status_label != null: status_label.text = value

func _on_message(message: Dictionary) -> void:
	var operation: String = str(message.get("op", message.get("event", "")))
	if not bool(message.get("ok", true)):
		waiting_for_walk = false
		var reason: String = str(message.get("error", "The server refused this request."))
		_set_status(reason)
		game._toast(reason)
		if operation == "shop_open": interaction.clear()
		if game.shop_ui != null: game.shop_ui.refresh()
		if operation in ["walk", "move"]:
			# A transport rejection is not an authoritative position; recover from the world.
			pending_inputs.clear()
			transition_pending = false
			game._cancel_controls()
			if not defeated: session.request("refresh")
		return
	var data: Dictionary = message.get("data", {}) as Dictionary
	match operation:
		"connect":
			_set_status("Server handshake accepted. Signing in…")
			session.request(desired_auth, {"username": username_field.text.strip_edges(), "password": password_field.text})
		"register":
			_set_status("Account created. Signing in…")
			session.request("login", {"username": username_field.text.strip_edges(), "password": password_field.text})
		"login", "create_character":
			password_field.text = ""
			_show_characters(data.get("characters", []) as Array)
		"enter":
			_enter_world(data)
		"stream":
			streaming = bool(data.get("enabled", false))
		"move", "strike":
			pass # Receipt only. The subsequent native Walk_Reply confirms acceptance.
		"world", "refresh", "snapshot", "attack", "pickup", "equip", "unequip", "spend_stat", "shop_buy", "shop_sell", "shop_craft":
			_apply_snapshot(data)
		"shop_open":
			_apply_snapshot(data)
			game.shop_ui.open(data.get("shop", {}) as Dictionary)
		"disconnect":
			_on_closed("Disconnected from the world.")

func _show_characters(characters: Array) -> void:
	selected_characters.clear()
	character_list.clear()
	for raw: Variant in characters:
		var character: Dictionary = raw as Dictionary
		selected_characters.append(character)
		character_list.add_item("%s   ·   Level %d" % [str(character.get("name", "Character")), int(character.get("level", 1))])
	if not selected_characters.is_empty(): character_list.select(0)
	auth_box.hide()
	character_box.show()
	_set_status("Choose a character or create your first one.")

func _enter_selected() -> void:
	var selection: PackedInt32Array = character_list.get_selected_items()
	if selection.is_empty():
		_set_status("Create or select a character first.")
		return
	var character: Dictionary = selected_characters[selection[0]]
	_set_status("Entering the world…")
	session.request("enter", {"character_id": int(character.get("id", 0))})

func _create_character() -> void:
	var name: String = character_name_field.text.strip_edges().to_lower()
	if name.is_empty():
		_set_status("Choose a name for your character.")
		return
	_set_status("Creating your character…")
	session.request("create_character", {"name": name, "gender": 1, "hairstyle": 1, "haircolor": 0, "race": 0})

func _enter_world(data: Dictionary) -> void:
	if not game.online_mode:
		offline_state = {}
		offline_map_id = int(game.world.get("id", 5))
		for key: String in ["player_tile", "player_world", "coins", "kills", "dagger_count", "has_blade", "equipped", "armor_equipped", "boots_equipped"]:
			offline_state[key] = game.get(key)
	game.online_mode = true
	active = true
	game._cancel_controls()
	panel.hide()
	game.welcome.hide()
	game.started = true
	game.enemy_health = 0
	game.loot_visible = false
	_reset_movement()
	_apply_snapshot(data, true)
	if not active: return
	session.request("stream", {"enabled": true})
	server_label.show()
	_set_status("Connected to your world.")
	game._toast("You have entered your online world.")

func _apply_snapshot(data: Dictionary, entering: bool = false) -> void:
	for raw: Variant in data.get("events", []):
		if raw is Dictionary and str(raw.get("kind", "")) == "map_transition": entering = true
	if data.has("player"):
		player = data.player as Dictionary
		defeated = bool((player.get("stats", {}) as Dictionary).get("dead", false))
		var map_id: int = int(player.get("map_id", player.get("map", 5)))
		if map_id != int(game.world.get("id", 5)):
			if not game.load_map(map_id):
				active = false
				game._cancel_controls()
				game.started = false
				panel.show()
				session.close()
				server_label.hide()
				auth_box.show()
				character_box.hide()
				_set_status("The content for map %d could not be loaded. Reconnect after installing its content pack." % map_id)
				return
			entering = true
			players.clear()
			npcs.clear()
			drops.clear()

		var tile: Vector2i = Vector2i(int(player.get("x", 40)), int(player.get("y", 40)))
		if entering:
			interaction.clear()
			collect_pending = false
			game.shop_ui.close()
			pending_inputs.clear()
			recovering = false
			confirmed_input_seq = int(data.get("position_seq", confirmed_input_seq))
			remote_motion.clear()
			npc_attack_until.clear()
			waiting_for_walk = false
			transition_pending = false
			game.facing = _facing(player.get("direction", 0))
			game.player_tile = tile
			game.player_world = game.tile_position(tile)
			game.moving = false
			game.camera.position = game.player_world
			game.camera.reset_smoothing()
		elif bool(data.get("position_update", false)):
			var confirmed: int = int(data.get("position_seq", 0))
			confirmed_input_seq = confirmed
			while not pending_inputs.is_empty() and int(pending_inputs[0].seq) <= confirmed:
				pending_inputs.pop_front()
			var correction: bool = bool(data.get("correction", false))
			if correction: recovering = true
			if not recovering and not defeated:
				for input: Dictionary in pending_inputs: tile += input.direction as Vector2i
			else:
				game._cancel_controls()
				game.player_tile = tile
				game.player_world = game.tile_position(tile)
			if pending_inputs.is_empty(): recovering = false
			waiting_for_walk = not pending_inputs.is_empty()
			if not waiting_for_walk: transition_pending = false
			if tile != game.player_tile:
				game.route.clear()
				_start_step(tile, _facing(player.get("direction", 0)))
		_sync_inventory()
	if data.has("players"): players = _dict_array(data.players)
	else: players = _merge_updates(players, data.get("players_upsert", []), data.get("players_remove", []), "player_id")
	if data.has("npcs"): npcs = _dict_array(data.npcs)
	else: npcs = _merge_updates(npcs, data.get("npcs_upsert", []), data.get("npcs_remove", []), "index")
	if data.has("items"): drops = _dict_array(data.items)
	else: drops = _merge_updates(drops, data.get("items_upsert", []), data.get("items_remove", []), "uid")
	_track_entities("player", players, "player_id")
	_track_entities("npc", npcs, "index")
	_process_events(data.get("events", []) as Array)
	game._refresh_ui()
	game.shop_ui.refresh()
	server_label.text = "● Connected  ·  %d nearby" % nearby_count()

func _merge_updates(rows: Array[Dictionary], changed: Array, removed: Array, key: String) -> Array[Dictionary]:
	var merged: Dictionary = {}
	for row: Dictionary in rows:
		if not removed.has(row.get(key)): merged[row.get(key)] = row
	for row: Dictionary in _dict_array(changed): merged[row.get(key)] = row
	return _dict_array(merged.values())

func _dict_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary: result.append(entry as Dictionary)
	return result

func _sync_inventory() -> void:
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	game.equipped = int(equipment.get("weapon", 0)) > 0
	game.armor_equipped = int(equipment.get("armor", 0)) > 0
	game.boots_equipped = int(equipment.get("boots", 0)) > 0
	game.has_blade = int(equipment.get("weapon", 0)) == 21
	game.dagger_count = 1 if int(equipment.get("weapon", 0)) == 21 else 0
	game.coins = int(player.get("gold", player.get("coins", 0)))
	for entry: Dictionary in _dict_array(player.get("inventory", [])):
		if int(entry.get("id", 0)) == 21:
			game.has_blade = true
			game.dagger_count += int(entry.get("amount", 0))
		if int(entry.get("id", 0)) == 1: game.coins = int(entry.get("amount", 0))

func _process(delta: float) -> void:
	if server_label != null:
		server_label.visible = active and game.started and not game._modal_open() and not game.welcome.visible
	if not active: return
	_process_interaction()
	warp_notice_clock = maxf(0.0, warp_notice_clock - delta)
	walk_clock = maxf(0.0, walk_clock - delta)
	refresh_clock += delta
	# World packets drive updates. An idle-only safety refresh never competes with walking.
	if refresh_clock >= 10.0 and session.connected and session.is_idle() and pending_inputs.is_empty() and not game.moving and game.stick == Vector2.ZERO and game.route.is_empty() and game.attack_touch_id == -1 and game.attack_clock <= 0.0 and not defeated and not recovering:
		refresh_clock = 0.0
		session.request("refresh")
	if not pending_inputs.is_empty() and Time.get_ticks_msec() - int(pending_inputs[0].sent_at) > 15000:
		session._fail("Movement confirmation timed out. Please reconnect.")

func request_step(direction: Vector2i) -> void:
	if not can_issue_walk(): return
	var single: Vector2i = direction
	if direction.x != 0 and direction.y != 0:
		diagonal_toggle = not diagonal_toggle
		single = Vector2i(direction.x, 0) if diagonal_toggle else Vector2i(0, direction.y)
	var target: Vector2i = game.player_tile + single
	var fields: Dictionary = {"direction": _direction(game._direction_name(single))}
	var passage: bool = false
	for warp: Dictionary in game.world.get("warps", []):
		if Vector2i(int(warp.x), int(warp.y)) != target: continue
		var destination: Array = warp.get("destination", []) as Array
		var map_info: Dictionary = (catalog.get("maps", {}) as Dictionary).get(str(int(warp.get("map", 0))), {}) as Dictionary
		if destination.size() != 2 or map_info.is_empty() or int(destination[0]) < 0 or int(destination[1]) < 0 or int(destination[0]) >= int(map_info.get("width", 0)) or int(destination[1]) >= int(map_info.get("height", 0)):
			game.route.clear()
			if warp_notice_clock <= 0.0:
				game._toast("This passage is unavailable.")
				warp_notice_clock = 3.0
			return
		passage = true
		if int(warp.get("door", 0)) > 0: fields["open_door"] = true
		break
	if not game._can_step(game.player_tile, single):
		game.route.clear()
		return
	next_input_seq += 1
	fields.merge({"input_seq": next_input_seq, "map_id": int(game.world.id), "x": target.x, "y": target.y})
	if session.request("move", fields) < 0: return
	pending_inputs.append({"seq": next_input_seq, "direction": single, "sent_at": Time.get_ticks_msec()})
	waiting_for_walk = true
	transition_pending = passage
	walk_clock = MOVE_SECONDS
	refresh_clock = 0.0
	_start_step(target, game._direction_name(single))

func _start_step(tile: Vector2i, direction: String) -> void:
	game.step_origin_tile = game.player_tile
	game.step_from = game.player_world
	game.step_to = game.tile_position(tile)
	game.player_tile = tile
	game.step_progress = 0.0
	game.step_duration = 0.40
	game.facing = direction
	game.animation_clock = 0.0
	game.moving = true

func _reset_movement() -> void:
	streaming = false
	recovering = false
	defeated = false
	npc_attack_until.clear()
	waiting_for_walk = false
	transition_pending = false
	next_input_seq = 0
	confirmed_input_seq = 0
	pending_inputs.clear()
	remote_motion.clear()
	walk_clock = 0.0
	refresh_clock = 0.0

func _action_ready() -> bool:
	return active and not defeated and not recovering and pending_inputs.is_empty() and not transition_pending and session.is_idle()

func request_attack() -> bool:
	if not active or defeated or recovering or game.moving or not pending_inputs.is_empty() or transition_pending or session.has_blocking_requests() or session.pending.size() >= MAX_PREDICTIONS: return false
	# Aim at the faced adjacent hostile; otherwise select an adjacent attackable NPC.
	var target_direction: int = _direction(game.facing)
	var adjacent: Array[Dictionary] = []
	for npc: Dictionary in npcs:
		var tile: Vector2i = Vector2i(int(npc.x), int(npc.y))
		var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(npc.id)), {}) as Dictionary
		if game._distance(game.player_tile, tile) == 1 and int(info.get("type", -1)) in [1, 2, 3]: adjacent.append(npc)
	var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
	var faced: bool = false
	for npc: Dictionary in adjacent:
		if Vector2i(int(npc.x), int(npc.y)) == game.player_tile + offsets[target_direction]: faced = true
	if not faced and not adjacent.is_empty(): game.facing = game._direction_name(Vector2i(int(adjacent[0].x), int(adjacent[0].y)) - game.player_tile)
	return session.request("strike", {"direction": _direction(game.facing)}) >= 0

func spend_stat(stat_id: int) -> void:
	if _action_ready():
		session.request("spend_stat", {"stat_id": stat_id})
		game.stats_ui.refresh()

func npc_occupies(tile: Vector2i) -> bool:
	for npc: Dictionary in npcs:
		if Vector2i(int(npc.get("x", -1)), int(npc.get("y", -1))) == tile: return true
	return false

func _direction(value: String) -> int:
	return int({"south": 0, "west": 1, "north": 2, "east": 3}.get(value, 0))

func _facing(value: Variant) -> String:
	if value is String: return value as String
	return ["south", "west", "north", "east"][clampi(int(value), 0, 3)]

func _on_closed(reason: String) -> void:
	active = false
	_reset_movement()
	game._cancel_controls()
	if game.online_mode:
		game.started = false
		game._show_welcome()
	server_label.hide()
	panel.hide()
	game.inventory.hide()
	game.character_panel.hide()
	game.stats_ui.hide()
	game.menu.hide()
	_set_status(reason)
	game._toast(reason)

func leave_for_offline() -> void:
	active = false
	session.close()
	_reset_movement()
	game._cancel_controls()
	game.load_map(offline_map_id)
	for raw: Variant in offline_state:
		game.set(str(raw), offline_state[raw])
	offline_state.clear()
	game.online_mode = false
	server_label.hide()
	game._place_enemy()
	game.enemy_health = 3
	game.loot_visible = false
	game._refresh_ui()

func _track_entities(kind: String, rows: Array[Dictionary], id_field: String) -> void:
	var seen: Dictionary = {}
	var now: float = Time.get_ticks_msec() / 1000.0
	for record: Dictionary in rows:
		var key: String = kind + ":" + str(record.get(id_field, -1))
		seen[key] = true
		var target: Vector2 = game.tile_position(Vector2i(int(record.get("x", 0)), int(record.get("y", 0))))
		if not remote_motion.has(key):
			remote_motion[key] = {"from": target, "to": target, "start": now - MOVE_SECONDS}
		elif remote_motion[key].to != target:
			remote_motion[key] = {"from": _remote_position(key, target), "to": target, "start": now}
	for key: Variant in remote_motion.keys():
		if str(key).begins_with(kind + ":") and not seen.has(key): remote_motion.erase(key)

func _remote_position(key: String, fallback: Vector2) -> Vector2:
	if not remote_motion.has(key): return fallback
	var motion: Dictionary = remote_motion[key]
	var fraction: float = clampf((Time.get_ticks_msec() / 1000.0 - float(motion.start)) / MOVE_SECONDS, 0.0, 1.0)
	return (motion.from as Vector2).lerp(motion.to as Vector2, fraction)

func entities() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not active: return result
	for record: Dictionary in players:
		if int(record.get("id", record.get("player_id", -1))) == int(player.get("id", player.get("player_id", -2))): continue
		var tile: Vector2i = Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
		result.append({"kind": "online_player", "data": record, "sort": game.depth(tile) * 100 + 55})
	for record: Dictionary in npcs:
		var tile: Vector2i = Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
		result.append({"kind": "online_npc", "data": record, "sort": game.depth(tile) * 100 + 70})
	for record: Dictionary in drops:
		var tile: Vector2i = Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
		result.append({"kind": "online_item", "data": record, "sort": game.depth(tile) * 100})
	return result

func draw_entity(entity: Dictionary) -> void:
	var record: Dictionary = entity.data as Dictionary
	var tile: Vector2i = Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
	var at: Vector2 = game.tile_position(tile)
	var key: String = ("npc:" + str(record.get("index", -1))) if str(entity.kind) == "online_npc" else ("player:" + str(record.get("player_id", -1)))
	var motion: Dictionary = remote_motion.get(key, {}) as Dictionary
	var phase: float = Time.get_ticks_msec() / 1000.0 - float(motion.get("start", 0.0))
	var state: String = "frames" if not motion.is_empty() and phase < MOVE_SECONDS and motion.from != motion.to else "idle"
	if str(entity.kind) == "online_npc" and float(npc_attack_until.get(int(record.get("index", -1)), 0.0)) > Time.get_ticks_msec() / 1000.0:
		state = "attack"
		phase = 0.36 - (float(npc_attack_until[int(record.index)]) - Time.get_ticks_msec() / 1000.0)
	if str(entity.kind) == "online_player" and float(npc_attack_until.get(key, 0.0)) > Time.get_ticks_msec() / 1000.0:
		state = "attack"
		phase = 0.36 - (float(npc_attack_until[key]) - Time.get_ticks_msec() / 1000.0)
		record.direction = _direction(_facing(record.get("direction", 0)))
	at = _remote_position(key, at)
	var direction: String = _facing(record.get("direction", 0))
	var half_view: Vector2 = game.get_viewport_rect().size / game.camera.zoom / 2.0 + Vector2(160, 240)
	if not Rect2(game.camera.position - half_view, half_view * 2.0).has_point(at): return
	if str(entity.kind) == "online_npc":
		var npc_id: String = str(int(record.get("id", 0)))
		var definitions: Dictionary = catalog.get("npcs", {}) as Dictionary
		var info: Dictionary = definitions.get(npc_id, {}) as Dictionary
		var characters: Dictionary = game.manifest.get("characters", {}) as Dictionary
		var npc_graphics: Dictionary = characters.get("npcs", {}) as Dictionary
		var graphic: Dictionary = npc_graphics.get(str(int(info.get("graphic", 0))), {}) as Dictionary
		if not graphic.is_empty(): game._draw_character_frame(graphic, at, direction, state, Color.WHITE, phase if state in ["frames", "attack"] else -1.0)
		else: game.draw_circle(at + Vector2(0, -12), 5.0, Color("e7bd70"))
		game.draw_string(ThemeDB.fallback_font, at + Vector2(-32, -32 - int((graphic.get("render_metadata", {}) as Dictionary).get("name_label_offset", 34))), str(info.get("name", "NPC %s" % npc_id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, game.TEXT)
	elif str(entity.kind) == "online_player":
		var graphic: Dictionary = character_graphic(record)
		if not graphic.is_empty(): game._draw_character_frame(graphic, at, direction, state, Color.WHITE, phase if state in ["frames", "attack"] else -1.0)
		else:
			game.draw_circle(at + Vector2(0, -12), 7.0, Color("a6cec0"))
			game.draw_string(ThemeDB.fallback_font, at + Vector2(-32, -42), "Appearance pending", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, game.MUTED)
		game.draw_string(ThemeDB.fallback_font, at + Vector2(-28, -66), str(record.get("name", "Player")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b9e2c5"))
	elif str(entity.kind) == "online_item":
		var definitions: Dictionary = catalog.get("items", {}) as Dictionary
		var info: Dictionary = definitions.get(str(int(record.get("id", 0))), {}) as Dictionary
		var ground_key: String = str(info.get("ground", ""))
		if int(info.get("type", -1)) == 2:
			for threshold: Dictionary in catalog.get("money_graphics", []):
				if int(record.get("amount", 0)) >= int(threshold.get("minimum_amount", 0)): ground_key = str(threshold.get("ground", ground_key))
		var texture: Texture2D = _catalog_texture(ground_key)
		if texture != null: game.draw_texture(texture, at - texture.get_size() / 2.0)

func _catalog_texture(key: String) -> Texture2D:
	var graphics: Dictionary = game.graphics as Dictionary
	if not graphics.has(key): return null
	return game._texture(str((graphics[key] as Dictionary).get("path", "")))

func inventory_items() -> Array[Dictionary]:
	# Gold always occupies the first bag slot, even if the real balance is zero.
	var totals: Dictionary = {}
	var order: Array[int] = []
	for item: Dictionary in _dict_array(player.get("inventory", [])):
		var id: int = int(item.get("id", 0))
		if id <= 0: continue
		if not totals.has(id): order.append(id)
		totals[id] = int(totals.get(id, 0)) + maxi(0, int(item.get("amount", 0)))
	var result: Array[Dictionary] = [{"id": 1, "amount": int(totals.get(1, game.coins))}]
	for id: int in order:
		if id != 1 and int(totals[id]) > 0: result.append({"id": id, "amount": int(totals[id])})
	return result

func item_id(kind: String) -> int:
	if kind.begins_with("item:"): return int(kind.get_slice(":", 1))
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	return int(equipment.get(_slot_name(kind), 0))

func item_info(kind: String) -> Dictionary:
	var definitions: Dictionary = catalog.get("items", {}) as Dictionary
	return definitions.get(str(item_id(kind)), {}) as Dictionary

func is_equipped(kind: String) -> bool:
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	if not kind.begins_with("item:"): return int(equipment.get(_slot_name(kind), 0)) > 0
	var id: int = item_id(kind)
	if id <= 0: return false
	for value: Variant in equipment.values():
		if int(value) == id: return true
	return false

func owns_item(kind: String) -> bool:
	var id: int = item_id(kind)
	if id <= 0: return false
	if id == 1: return true
	if is_equipped(kind): return true
	for item: Dictionary in inventory_items():
		if int(item.get("id", 0)) == id: return true
	return false

func select_bag_item(index: int) -> void:
	var items: Array[Dictionary] = inventory_items()
	if index >= items.size():
		game._select_item("")
		return
	game._select_item("item:%d" % int(items[index].get("id", 0)))

func equipment_request(kind: String) -> void:
	if not _action_ready() or not owns_item(kind): return
	if is_equipped(kind):
		var slot: String = kind
		if kind.begins_with("item:"):
			var equipment: Dictionary = player.get("equipment", {}) as Dictionary
			for key: Variant in equipment:
				if int(equipment[key]) == item_id(kind): slot = str(key)
		session.request("unequip", {"item_id": item_id(kind)})
	else:
		session.request("equip", {"item_id": item_id(kind)})

func map_target(point: Vector2, fallback: Vector2i) -> Vector2i:
	# The original client tests sprite rectangles. A tap on Bob's head must talk
	# to Bob, rather than pathfinding to the tile behind his feet.
	var ordered: Array[Dictionary] = npcs.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return game.depth(Vector2i(int(a.x), int(a.y))) > game.depth(Vector2i(int(b.x), int(b.y))))
	for npc: Dictionary in ordered:
		var tile: Vector2i = Vector2i(int(npc.x), int(npc.y))
		var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(npc.id)), {}) as Dictionary
		var character: Dictionary = ((game.manifest.get("characters", {}) as Dictionary).get("npcs", {}) as Dictionary).get(str(int(info.get("graphic", 0))), {}) as Dictionary
		var frame: Dictionary = game._frame(character, _facing(npc.get("direction", 0)), "idle")
		var region: Array = frame.get("region", [0, 0, 30, 54]) as Array
		var offset: Array = frame.get("offset", [0, 0]) as Array
		var dimensions: Vector2 = Vector2(float(region[2]), float(region[3]))
		var at: Vector2 = _remote_position("npc:%d" % int(npc.index), game.tile_position(tile))
		var rectangle: Rect2 = Rect2(at + Vector2(float(offset[0]), float(offset[1])) - Vector2(dimensions.x / 2.0, dimensions.y), dimensions)
		if rectangle.grow(5.0).has_point(point): return tile
	return fallback

func map_click(tile: Vector2i) -> void:
	if not active or defeated or recovering or transition_pending: return
	interaction.clear()
	for drop: Dictionary in drops:
		if Vector2i(int(drop.x), int(drop.y)) == tile:
			interaction = {"kind": "drop", "id": int(drop.uid)}
			_approach(tile, 2)
			return
	for npc: Dictionary in npcs:
		if Vector2i(int(npc.x), int(npc.y)) != tile: continue
		var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(npc.id)), {}) as Dictionary
		var type: int = int(info.get("type", -1))
		if type == 6:
			interaction = {"kind": "shop", "id": int(npc.index)}
			_approach(tile, 2)
		elif type in [1, 2, 3]:
			if game._distance(game.player_tile, tile) == 1:
				game.facing = game._direction_name(tile - game.player_tile)
				game._attack()
			else: _approach(tile, 1)
		else: game._toast("%s: this NPC service is not available yet." % str(info.get("name", "NPC")))
		return
	game._request_path(tile)

func _approach(tile: Vector2i, distance: int) -> void:
	game.route.clear()
	if game._distance(game.player_tile, tile) <= distance: return
	var choices: Array[Vector2i] = []
	for dx: int in range(-distance, distance + 1):
		for dy: int in range(-distance, distance + 1):
			var candidate: Vector2i = tile + Vector2i(dx, dy)
			if absi(dx) + absi(dy) > 0 and absi(dx) + absi(dy) <= distance and game._walkable(candidate): choices.append(candidate)
	choices.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return game._distance(game.player_tile, a) < game._distance(game.player_tile, b))
	for choice: Vector2i in choices:
		game._request_path(choice)
		if not game.route.is_empty(): return
	interaction.clear()

func _process_interaction() -> void:
	if game.stick != Vector2.ZERO or defeated:
		interaction.clear()
		collect_pending = false
		return
	if game.moving or not game.route.is_empty() or not _action_ready() or game._modal_open(): return
	if not interaction.is_empty():
		var target: Dictionary = {}
		for row: Dictionary in (drops if str(interaction.kind) == "drop" else npcs):
			if int(row.get("uid" if str(interaction.kind) == "drop" else "index", -1)) == int(interaction.id): target = row
		if not target.is_empty():
			var tile: Vector2i = Vector2i(int(target.x), int(target.y))
			if game._distance(game.player_tile, tile) > 2:
				_approach(tile, 2)
				return
			if str(interaction.kind) == "drop": _pickup(int(interaction.id))
			else: session.request("shop_open", {"npc_index": int(interaction.id)})
		interaction.clear()
		collect_pending = false
	elif collect_pending:
		collect_pending = false
		for drop: Dictionary in drops:
			var tile: Vector2i = Vector2i(int(drop.x), int(drop.y))
			if game._distance(game.player_tile, tile) <= 1 and Time.get_ticks_msec() >= int(loot_attempt_after.get(int(drop.uid), 0)):
				_pickup(int(drop.uid))
				return

func _pickup(uid: int) -> void:
	loot_attempt_after[uid] = Time.get_ticks_msec() + 5000
	session.request("pickup", {"uid": uid})

func collect_nearby() -> void:
	# Movement animation may finish before Walk_Reply. Keep this intent until confirmed.
	collect_pending = true

func refresh_game_ui() -> void:
	game.quest_label.text = "%s\n%d nearby players  ·  %d NPCs" % [str(game.world.get("name", "Area %s" % str(player.get("map_id", "")))), nearby_count(), npcs.size()]
	game.quest_hint.text = "Progress is saved by your server."
	game.coin_label.text = "◈  %d coins" % game.coins
	game.location_label.text = "%s  /  %d, %d" % [str(player.get("name", "Player")), game.player_tile.x, game.player_tile.y]
	game.health_label.visible = false
	game.health_label.text = "HP %d / %d" % [int(player.get("hp", 0)), int(player.get("max_hp", player.get("maxhp", 0)))]
	var items: Array[Dictionary] = inventory_items()
	game.inventory_summary.text = "%d coins  ·  %d items" % [game.coins, items.size()]
	for index: int in range(game.bag_slots.size()):
		var slot: Button = game.bag_slots[index] as Button
		slot.icon = null
		slot.text = ""
		(slot.get_node("Quantity") as Label).text = ""
		slot.tooltip_text = "Empty slot"
		if index < items.size():
			var item: Dictionary = items[index]
			var kind: String = "item:%d" % int(item.get("id", 0))
			var info: Dictionary = item_info(kind)
			slot.icon = _catalog_texture(str(info.get("icon", "")))
			slot.tooltip_text = str(info.get("name", "Item"))
			if int(item.get("id", 0)) == 1 or int(item.get("amount", 1)) > 1: (slot.get_node("Quantity") as Label).text = str(int(item.amount))
	var selected: String = str(game.selected_item)
	var info: Dictionary = item_info(selected)
	var worn: bool = is_equipped(selected)
	var owned: bool = owns_item(selected)
	game.item_title.text = str(info.get("name", "Your inventory"))
	var details: Array[String] = ["Equipped" if worn else "In your bag"]
	if int(info.get("max_damage", 0)) > 0:
		details.append("Damage %d–%d" % [int(info.get("min_damage", 0)), int(info.get("max_damage", 0))])
	for field: String in ["armor", "accuracy", "evade", "hp", "tp", "strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]:
		if int(info.get(field, 0)) != 0: details.append("%s +%d" % [field.capitalize(), int(info[field])])
	if owned: details.append("Weight %d" % int(info.get("weight", 0)))
	if int(info.get("level_requirement", 0)) > 0: details.append("Requires level %d" % int(info.level_requirement))
	for attribute: String in ["strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]:
		if int(info.get(attribute + "_requirement", 0)) > 0: details.append("Requires %s %d" % [attribute, int(info[attribute + "_requirement"])])
	game.inventory_detail.text = "  ·  ".join(details) if owned else "Select an item to inspect it."
	game.equip_button.disabled = not owned or worn or int(info.get("type", 0)) not in range(10, 22)
	game.equip_button.text = "Equip " + str(info.get("name", "item")) if owned and not worn else "Select an unequipped item"
	game.paperdoll.refresh(selected)
	if game.paperdoll.information_labels.size() >= 2:
		game.paperdoll.information_labels[0].text = str(player.get("name", "Player"))
		game.paperdoll.information_labels[1].text = str(game.world.get("name", ""))
	game.equipment_detail.text = str(info.get("name", "Empty " + selected + " slot"))
	if worn:
		game.equipment_detail.text += "  ·  Damage %d–%d  ·  Armor %d" % [int(info.get("min_damage", 0)), int(info.get("max_damage", 0)), int(info.get("armor", 0))]
	game.remove_button.disabled = not worn
	game.remove_button.text = "Remove " + str(info.get("name", "item")) if worn else "Empty slot"
	game.attack_button.weapon = game._item_texture("weapon") if game.equipped else null
	game.attack_button.collecting = false
	game.attack_button.queue_redraw()

func nearby_count() -> int:
	var count: int = 0
	for record: Dictionary in players:
		if int(record.get("id", record.get("player_id", -1))) != int(player.get("id", player.get("player_id", -2))): count += 1
	return count

func character_graphic(record: Dictionary) -> Dictionary:
	var equipment_graphics: Array = record.get("equipment_graphics", []) as Array
	if equipment_graphics.size() != 9: return {}
	if int(record.get("gender", 1)) != 1 or int(record.get("race", 0)) != 0 or int(record.get("hairstyle", 1)) != 1 or int(record.get("haircolor", 0)) != 0: return {}
	if int(equipment_graphics[6]) != 0 or int(equipment_graphics[7]) != 0: return {}
	if int(equipment_graphics[0]) not in [0, 1] or int(equipment_graphics[4]) not in [0, 1] or int(equipment_graphics[8]) not in [0, 4]: return {}
	var key: String = "a%d_b%d_w%d" % [int(int(equipment_graphics[4]) == 1), int(int(equipment_graphics[0]) == 1), int(int(equipment_graphics[8]) == 4)]
	var characters: Dictionary = game.manifest.get("characters", {}) as Dictionary
	var variants: Dictionary = characters.get("hero_variants", {}) as Dictionary
	return variants.get(key, {}) as Dictionary

func _process_events(events: Array) -> void:
	for raw: Variant in events:
		if not raw is Dictionary: continue
		var event: Dictionary = raw as Dictionary
		var kind: String = str(event.get("kind", event.get("type", event.get("event", ""))))
		if kind in ["player_damage", "npc_attack"]:
			npc_attack_until[int(event.get("npc_index", -1))] = Time.get_ticks_msec() / 1000.0 + 0.36
			for npc: Dictionary in npcs:
				if int(npc.index) == int(event.get("npc_index", -1)): npc.direction = int(event.get("direction", 0))
		if kind == "peer_attack": npc_attack_until["player:" + str(int(event.get("player_id", -1)))] = Time.get_ticks_msec() / 1000.0 + 0.36
		if kind == "player_damage":
			game.player_hit_flash = 0.22
			game.damage_numbers.append({"position": game.player_world + Vector2(0, -62), "value": "-%d" % int(event.get("damage", 0)) if int(event.get("damage", 0)) > 0 else "Miss", "time": 0.85, "player_hit": true})
			if bool(event.get("dead", false)):
				defeated = true
				pending_inputs.clear()
				waiting_for_walk = false
				game._cancel_controls()
				game._toast("You were defeated. Returning to your respawn point…")
		if kind == "map_transition" and str(event.get("reason", "")) == "death_respawn": game._toast("You have returned to your respawn point.")
		if kind == "door_locked": game._toast("This door needs a key.")
		if kind in ["npc_damage", "npc_killed"]:
			for npc: Dictionary in npcs:
				if int(npc.get("index", -1)) == int(event.get("npc_index", -2)):
					var tile: Vector2i = Vector2i(int(npc.get("x", 0)), int(npc.get("y", 0)))
					game.damage_numbers.append({"position": game.tile_position(tile) + Vector2(0, -44), "value": str(int(event.get("damage", 0))), "time": 0.8})
			if kind == "npc_killed":
				game._toast("Level %d reached! Stat points are available in Character Stats." % int(event.level_up) if event.has("level_up") else "Enemy defeated. Its drops belong to the online world.")

func _slot_name(kind: String) -> String:
	return str({"hat": "head", "shield": "offhand"}.get(kind, kind))

func can_issue_walk() -> bool:
	return active and streaming and not defeated and not recovering and not transition_pending and walk_clock <= 0.0 and game.attack_clock <= 0.0 and pending_inputs.size() < MAX_PREDICTIONS and not session.has_blocking_requests()
