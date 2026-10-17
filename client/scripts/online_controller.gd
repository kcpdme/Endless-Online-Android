extends Node
## Owns online UI/session state. No passwords, server position, or items enter the offline save.
const OnlineSession = preload("res://scripts/online_session.gd")
var drop_ui: RefCounted
var game: Node
var session: OnlineSession
var panel: Control
var status_label: Label
var chat_bubbles: Dictionary = {}
var trade: Dictionary = {}
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
const NPC_SERVICE_DISTANCE: int = 11
const MOVE_SECONDS: float = 0.42
const MAX_PREDICTIONS: int = 4
var streaming: bool = false
var recovering: bool = false
var defeated: bool = false
var npc_attack_until: Dictionary = {}
var peer_attacks: Dictionary = {}
var npc_health: Dictionary = {}
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
var pickup_pending: Dictionary = {}
var pending_equip: Dictionary = {}
var loot_button: Button
var drop_permissions: Dictionary = {}
var resume_username: String = ""
var resume_token: String = ""
var login_retries: int = 0
var login_retry_at: int = 0
var network_metrics: Dictionary = {"moves": 0, "corrections": 0, "pickups": 0}

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
	drop_ui = preload("res://scripts/drop_window.gd").new()
	drop_ui.build(game, parent)
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
	loot_button = game._button(parent, "Pick up", Vector2(-486, -224), Vector2(280, 58), request_collect, true)
	loot_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	loot_button.clip_text = true
	loot_button.add_theme_font_size_override("font_size", 17)
	loot_button.hide()

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
	login_retry_at = 0
	panel.hide()
	if not active: game._show_welcome()

func _authenticate(operation: String, retrying: bool = false) -> void:
	if not retrying: login_retries = 0
	login_retry_at = 0
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
		if operation == "login" and int(message.get("error_code", 0)) == 5 and login_retries < 3:
			var delays: Array[int] = [2500, 4000, 6000]
			login_retry_at = Time.get_ticks_msec() + delays[login_retries]
			login_retries += 1
			_set_status("Previous network session is closing. Reconnecting… (%d/3)" % login_retries)
		if operation == "shop_open": interaction.clear()
		if operation == "collect": pickup_pending.clear()
		if operation in ["equip", "unequip"]: pending_equip.clear()
		if operation == "spell_cast": game.skills_ui.casting.clear()
		if operation == "item_drop":
			drop_ui.submitting = false
			drop_ui.refresh()
		if operation == "item_use": game._refresh_ui()
		if game.shop_ui != null: game.shop_ui.refresh()
		if game.services_ui != null: game.services_ui.refresh()
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
			var credentials: Dictionary = {"username": username_field.text.strip_edges(), "password": password_field.text}
			if desired_auth == "login" and username_field.text.strip_edges().to_lower() == resume_username: credentials["resume_token"] = resume_token
			session.request(desired_auth, credentials)
		"register":
			_set_status("Account created. Signing in…")
			session.request("login", {"username": username_field.text.strip_edges(), "password": password_field.text})
		"login", "create_character":
			if operation == "login" and data.has("resume_token"):
				resume_username = username_field.text.strip_edges().to_lower()
				resume_token = str(data.resume_token)
			login_retry_at = 0
			password_field.text = ""
			_show_characters(data.get("characters", []) as Array)
		"enter":
			_enter_world(data)
		"stream":
			streaming = bool(data.get("enabled", false))
		"move", "strike", "collect", "spell_cast", "spell_cancel":
			pass # Receipt only. The subsequent native Walk_Reply confirms acceptance.
		"unequip":
			_apply_snapshot(data)
			if not pending_equip.is_empty():
				var replacement: Dictionary = pending_equip.duplicate()
				pending_equip.clear()
				if int((player.get("equipment", {}) as Dictionary).get(str(replacement.slot), 0)) == 0:
					session.request("equip", {"item_id": int(replacement.item_id), "subloc": int(replacement.subloc)})
				else: game._toast("The worn item could not be removed. Your replacement remains in the bag.")
		"world", "refresh", "snapshot", "attack", "pickup", "equip", "spend_stat", "shop_buy", "shop_sell", "shop_craft", "bank_deposit", "bank_withdraw", "bank_upgrade", "locker_deposit", "locker_withdraw", "trade_request", "trade_accept", "trade_decline", "trade_add", "trade_remove", "trade_agree", "trade_cancel", "chat_send", "item_use", "skill_learn", "skill_forget", "skill_level":
			_apply_snapshot(data)
		"item_drop":
			drop_ui.panel.hide()
			drop_ui.submitting = false
			_apply_snapshot(data)
		"skillmaster_open":
			_apply_snapshot(data)
			game._cancel_controls()
			game.skills_ui.panel.show()
			game.skills_ui.last_rows = ""
			game.skills_ui.refresh()
		"inspect_player":
			game.services_ui.open("inspect", data)
		"bank_open", "locker_open":
			_apply_snapshot(data)
			game.services_ui.open("bank" if operation == "bank_open" else "locker", data.get("bank" if operation == "bank_open" else "locker", {}) as Dictionary)
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
	game.chat_ui.clear()
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
	server_label.hide()
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
			pickup_pending.clear()
			drop_permissions.clear()
			game.shop_ui.close()
			game.services_ui.panel.hide()
			trade.clear()
			pending_inputs.clear()
			recovering = false
			confirmed_input_seq = int(data.get("position_seq", confirmed_input_seq))
			remote_motion.clear()
			npc_attack_until.clear()
			peer_attacks.clear()
			chat_bubbles.clear()
			npc_health.clear()
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
			if correction:
				network_metrics.corrections = int(network_metrics.corrections) + 1
				recovering = true
			if not recovering and not defeated:
				for input: Dictionary in pending_inputs: tile += input.direction as Vector2i
			else:
				game._cancel_controls(true)
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
	if data.has("trade"): trade = data.trade as Dictionary if data.trade is Dictionary else {}
	game.skills_ui.receive(data)
	game.services_ui.receive(data)
	game.services_ui.refresh()
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
		server_label.visible = false
	if login_retry_at > 0 and Time.get_ticks_msec() >= login_retry_at:
		login_retry_at = 0
		if panel.visible and not active: _authenticate("login", true)
	if not active: return
	_process_interaction()
	warp_notice_clock = maxf(0.0, warp_notice_clock - delta)
	walk_clock = maxf(0.0, walk_clock - delta)
	refresh_clock += delta
	# Original EO updates are event driven; no periodic full-world Refresh.
	_update_loot_control()
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
	network_metrics.moves = int(network_metrics.moves) + 1
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
	npc_health.clear()
	pending_equip.clear()
	if loot_button != null: loot_button.hide()
	pickup_pending.clear()
	drop_permissions.clear()
	interaction.clear()
	collect_pending = false
	streaming = false
	recovering = false
	defeated = false
	npc_attack_until.clear()
	peer_attacks.clear()
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
	game.skills_ui.armed = 0
	if not game.skills_ui.casting.is_empty(): return false
	if not active or defeated or recovering or game.moving or transition_pending or session.has_blocking_requests() or session.pending.size() >= MAX_PREDICTIONS: return false
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
	var sent: bool = session.request("strike", {"direction": _direction(game.facing)}) >= 0
	if sent:
		var target_tile: Vector2i = game.player_tile + offsets[_direction(game.facing)]
		for npc: Dictionary in adjacent:
			if Vector2i(int(npc.x), int(npc.y)) != target_tile: continue
			var index: int = int(npc.index)
			var health: Dictionary = npc_health.get(index, {"percent": 100}) as Dictionary
			health["until"] = Time.get_ticks_msec() + 8000
			npc_health[index] = health
	return sent

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
	if drop_ui != null: drop_ui.panel.hide()
	active = false
	_reset_movement()
	game._cancel_controls(true)
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
	game._cancel_controls(true)
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

func entity_animation(kind: String, record: Dictionary) -> Dictionary:
	var key: String = ("npc:" + str(record.get("index", -1))) if kind == "online_npc" else ("player:" + str(record.get("player_id", -1)))
	var motion: Dictionary = remote_motion.get(key, {}) as Dictionary
	var now: float = Time.get_ticks_msec() / 1000.0
	var phase: float = now - float(motion.get("start", 0.0))
	var state: String = "frames" if not motion.is_empty() and phase < MOVE_SECONDS and motion.from != motion.to else "idle"
	var direction: String = _facing(record.get("direction", 0))
	if kind == "online_npc" and float(npc_attack_until.get(int(record.get("index", -1)), 0.0)) > now:
		state = "attack"
		phase = 0.36 - (float(npc_attack_until[int(record.index)]) - now)
	var attack: Dictionary = peer_attacks.get(int(record.get("player_id", -1)), {}) as Dictionary
	if kind == "online_player" and float(attack.get("until", 0.0)) > now:
		state = "attack"
		phase = 0.36 - (float(attack.until) - now)
		direction = _facing(attack.direction)
	if kind == "online_player" and game.skills_ui.is_chanting(int(record.get("player_id", -1))): state = "cast"
	return {"key": key, "state": state, "phase": phase, "direction": direction}

func npc_name_layout(graphic: Dictionary, direction: String, fighting: bool) -> Dictionary:
	# Use the original visible standing art, including its render offset. This
	# keeps names close to heads and stable while a walking/attack pose changes.
	var frame: Dictionary = game._frame(graphic, direction, "idle", 0.0)
	var region: Array = frame.get("region", [0, 0, 20, 24]) as Array
	var offset: Array = frame.get("offset", [0, 0]) as Array
	var visible: Array = frame.get("visible_bounds", [0, 0, region[2], region[3]]) as Array
	var head: Vector2 = Vector2(float(offset[0]) - float(region[2]) / 2.0 + float(visible[0]) + float(visible[2]) / 2.0, float(offset[1]) - float(region[3]) + float(visible[1]))
	return {"head": head, "name": head + Vector2(0, -13 if fighting else -5), "health": Rect2(head + Vector2(-17, -8), Vector2(34, 5))}

func draw_entity(entity: Dictionary) -> void:
	var record: Dictionary = entity.data as Dictionary
	var tile: Vector2i = Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
	var animation: Dictionary = entity_animation(str(entity.kind), record)
	var at: Vector2 = _remote_position(str(animation.key), game.tile_position(tile))
	var direction: String = str(animation.direction)
	var state: String = str(animation.state)
	var phase: float = float(animation.phase)
	var half_view: Vector2 = game.get_viewport_rect().size / game.camera.zoom / 2.0 + Vector2(160, 240)
	if not Rect2(game.camera.position - half_view, half_view * 2.0).has_point(at): return
	var effect_kind: String = "npc" if str(entity.kind) == "online_npc" else "player"
	var effect_id: int = int(record.get("index" if effect_kind == "npc" else "player_id", 0))
	if str(entity.kind) != "online_item": game.skills_ui.draw_effect(effect_kind, effect_id, at, false)
	if str(entity.kind) == "online_npc":
		var npc_id: String = str(int(record.get("id", 0)))
		var definitions: Dictionary = catalog.get("npcs", {}) as Dictionary
		var info: Dictionary = definitions.get(npc_id, {}) as Dictionary
		var characters: Dictionary = game.manifest.get("characters", {}) as Dictionary
		var npc_graphics: Dictionary = characters.get("npcs", {}) as Dictionary
		var graphic: Dictionary = npc_graphics.get(str(int(info.get("graphic", 0))), {}) as Dictionary
		if not graphic.is_empty(): game._draw_character_frame(graphic, at, direction, state, Color.WHITE, phase if state in ["frames", "attack"] else -1.0)
		else: game.draw_circle(at + Vector2(0, -12), 5.0, Color("e7bd70"))
		var health: float = npc_health_fraction(int(record.get("index", -1)))
		var layout: Dictionary = npc_name_layout(graphic, direction, health >= 0.0)
		var name: String = str(info.get("name", "NPC %s" % npc_id))
		var text_width: float = ThemeDB.fallback_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		game.draw_string(ThemeDB.fallback_font, at + (layout.name as Vector2) - Vector2(text_width / 2.0, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, game.TEXT)
		if health >= 0.0:
			var strip: Rect2 = layout.health as Rect2
			strip.position += at
			game.draw_rect(strip.grow(1), Color("121b18"))
			game.draw_rect(strip, Color("50322e"))
			game.draw_rect(Rect2(strip.position, Vector2(strip.size.x * health, strip.size.y)), Color("a6cb6f") if health > 0.3 else Color("dc6855"))
	elif str(entity.kind) == "online_player":
		var graphic: Dictionary = character_graphic(record)
		if not graphic.is_empty(): game._draw_character_frame(graphic, at, direction, state, Color.WHITE, phase if state in ["frames", "attack"] else -1.0)
		else:
			game.draw_circle(at + Vector2(0, -12), 7.0, Color("a6cec0"))
			game.draw_string(ThemeDB.fallback_font, at + Vector2(-32, -42), "Appearance pending", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, game.MUTED)
		game.draw_string(ThemeDB.fallback_font, at + Vector2(-28, -66), str(record.get("name", "Player")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b9e2c5"))
		draw_chat_bubble(int(record.get("player_id", 0)), at)
	elif str(entity.kind) == "online_item":
		var definitions: Dictionary = catalog.get("items", {}) as Dictionary
		var info: Dictionary = definitions.get(str(int(record.get("id", 0))), {}) as Dictionary
		var ground_key: String = str(info.get("ground", ""))
		if int(info.get("type", -1)) == 2:
			for threshold: Dictionary in catalog.get("money_graphics", []):
				if int(record.get("amount", 0)) >= int(threshold.get("minimum_amount", 0)): ground_key = str(threshold.get("ground", ground_key))
		var texture: Texture2D = _catalog_texture(ground_key)
		if texture != null: game.draw_texture(texture, at - texture.get_size() / 2.0)

	if str(entity.kind) != "online_item": game.skills_ui.draw_effect(effect_kind, effect_id, at, true)

func draw_chat_bubble(pid: int, at: Vector2) -> void:
	var bubble: Dictionary = chat_bubbles.get(pid, {}) as Dictionary
	if bubble.is_empty() or Time.get_ticks_msec() >= int(bubble.until): return
	var lines: Array[String] = []
	var line: String = ""
	for word: String in str(bubble.text).split(" "):
		if line.length() + word.length() > 29 and not line.is_empty():
			lines.append(line)
			line = ""
		line += (" " if not line.is_empty() else "") + word
	if not line.is_empty(): lines.append(line)
	if lines.size() > 3: lines = lines.slice(0, 3); lines[2] += "…"
	var width: float = 50.0
	for text: String in lines: width = maxf(width, ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0)
	var rectangle: Rect2 = Rect2(at + Vector2(-width / 2.0, -86 - lines.size() * 13), Vector2(width, lines.size() * 13 + 8))
	var style: StyleBoxFlat = game._style(Color(0.06, 0.08, 0.10, 0.9), Color("d7cfae"), 5)
	game.draw_style_box(style, rectangle)
	for i: int in range(lines.size()): game.draw_string(ThemeDB.fallback_font, rectangle.position + Vector2(7, 13 + i * 13), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, game.TEXT)

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

func bag_amount(id: int) -> int:
	for item: Dictionary in inventory_items():
		if int(item.id) == id: return int(item.amount)
	return 0

func select_bag_item(index: int) -> void:
	var items: Array[Dictionary] = inventory_items()
	if index >= items.size():
		game._select_item("")
		return
	game._select_item("item:%d" % int(items[index].get("id", 0)))

func consumable(kind: String) -> bool:
	return kind.begins_with("item:") and int(item_info(kind).get("type", -1)) in [3, 4, 6, 22, 23, 24, 25]

func bag_action(kind: String) -> void:
	if not consumable(kind):
		equipment_request(kind)
		return
	if not _action_ready() or not owns_item(kind): return
	game._cancel_controls()
	session.request("item_use", {"item_id": item_id(kind)})
	if int(item_info(kind).get("type", -1)) == 4: game.inventory.hide()
	game.equip_button.disabled = true

func equipment_request(kind: String) -> void:
	if not _action_ready() or not pending_equip.is_empty() or not owns_item(kind): return
	var info: Dictionary = item_info(kind)
	if is_equipped(kind):
		if int(info.get("special", 0)) == 5:
			game._toast("This item is cursed and cannot be removed.")
			return
		var equipment: Dictionary = player.get("equipment", {}) as Dictionary
		var subloc: int = 1 if not kind.begins_with("item:") and _slot_name(kind).ends_with("2") else 0
		if kind.begins_with("item:"):
			for slot: Variant in equipment:
				if int(equipment[slot]) == item_id(kind):
					subloc = 1 if str(slot).ends_with("2") else 0
					break
		session.request("unequip", {"item_id": item_id(kind), "subloc": subloc})
	else:
		var slots: Dictionary = {10: "weapon", 11: "offhand", 12: "armor", 13: "head", 14: "boots", 15: "gloves", 16: "accessory", 17: "belt", 18: "necklace", 19: "ring1", 20: "armlet1", 21: "bracer1"}
		var slot: String = str(slots.get(int(info.get("type", 0)), ""))
		if slot.is_empty():
			game._toast("This item cannot be equipped.")
			return
		var equipment: Dictionary = player.get("equipment", {}) as Dictionary
		var subloc: int = 0
		if slot.ends_with("1") and int(equipment.get(slot, 0)) > 0:
			var second: String = slot.trim_suffix("1") + "2"
			if int(equipment.get(second, 0)) == 0:
				slot = second
				subloc = 1
		var previous: int = int(equipment.get(slot, 0))
		var problem: String = _equipment_problem(info, previous)
		if not problem.is_empty():
			game._toast(problem)
			return
		if previous > 0:
			pending_equip = {"slot": slot, "item_id": item_id(kind), "subloc": subloc}
			# EO has separate Remove/Add packets and silently refuses occupied slots.
			# Only the actual native Remove acknowledgement may trigger Add.
			session.request("unequip", {"item_id": previous, "subloc": subloc})
		else: session.request("equip", {"item_id": item_id(kind), "subloc": subloc})

func _equipment_problem(info: Dictionary, previous: int) -> String:
	var stats: Dictionary = player.get("stats", {}) as Dictionary
	var worn: Dictionary = item_info("item:%d" % previous)
	if int(worn.get("special", 0)) == 5: return "The worn item is cursed and cannot be replaced."
	if int(player.get("level", stats.get("level", 0))) < int(info.get("level_requirement", 0)): return "This item requires level %d." % int(info.level_requirement)
	if int(info.get("type", 0)) == 12 and int(info.get("gender", 0)) != int(player.get("gender", 1)): return "This armor does not fit your character."
	var class_id: int = int(stats.get("class_id", 0))
	var classes: Dictionary = catalog.get("classes", {}) as Dictionary
	var base_class: int = int((classes.get(str(class_id), {}) as Dictionary).get("base", 0))
	var requirement: int = int(info.get("class_requirement", 0))
	if requirement != 0 and requirement not in [class_id, base_class]: return "This item requires a different character class."
	for attribute: String in ["strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]:
		if int(stats.get(attribute, 0)) - int(worn.get(attribute, 0)) < int(info.get(attribute + "_requirement", 0)): return "This item requires %s %d." % [attribute.capitalize(), int(info[attribute + "_requirement"])]
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	var shield: Dictionary = item_info("item:%d" % int(equipment.get("offhand", 0)))
	var weapon: Dictionary = item_info("item:%d" % int(equipment.get("weapon", 0)))
	if int(info.get("type", 0)) == 10 and int(info.get("subtype", 0)) == 4 and not shield.is_empty() and int(shield.get("subtype", 0)) not in [2, 3]: return "Remove your shield before wielding a two-handed weapon."
	if int(info.get("type", 0)) == 11 and int(weapon.get("subtype", 0)) == 4 and int(info.get("subtype", 0)) not in [2, 3]: return "Remove your two-handed weapon before equipping this shield."
	return ""

func map_target(point: Vector2, fallback: Vector2i) -> Vector2i:
	var hit: Dictionary = map_entity_target(point)
	return hit.get("tile", fallback) as Vector2i

func map_press(point: Vector2, entities_only: bool = false) -> bool:
	var hit: Dictionary = map_entity_target(point)
	if hit.is_empty() and entities_only and game.skills_ui.armed == 0: return false
	map_click(hit.get("tile", game._world_tile(point)) as Vector2i, str(hit.get("kind", "")))
	return true

func map_entity_target(point: Vector2) -> Dictionary:
	# Ground loot gets a touch target matching its visible art, including tall items.
	for drop: Dictionary in ([] if game.skills_ui.armed > 0 else drops):
		var tile: Vector2i = Vector2i(int(drop.x), int(drop.y))
		var info: Dictionary = item_info("item:%d" % int(drop.id))
		var texture: Texture2D = _catalog_texture(str(info.get("ground", "")))
		var dimensions: Vector2 = texture.get_size() if texture != null else Vector2(24, 20)
		if Rect2(game.tile_position(tile) - dimensions / 2.0, dimensions).grow(8.0).has_point(point): return {"tile": tile, "kind": "drop"}
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
		if rectangle.grow(5.0).has_point(point): return {"tile": tile, "kind": "npc"}
	# Match the visible locker object, including its tall front above its tile.
	for spec: Dictionary in ([] if game.skills_ui.armed > 0 else game.world.get("tile_specs", [])):
		if int(spec.get("spec", -1)) != 16: continue
		var tile: Vector2i = Vector2i(int(spec.x), int(spec.y))
		for decoration: Dictionary in game.decorations:
			if decoration.tile != tile or str(decoration.layer) != "objects": continue
			var texture: Texture2D = game._graphic(int(decoration.gfx), int(decoration.id))
			if texture == null: continue
			var size: Vector2 = texture.get_size()
			if Rect2(game.tile_position(tile) + Vector2(-2.0 - size.x / 2.0, 14.0 - size.y), size).grow(4.0).has_point(point): return {"tile": tile, "kind": "locker"}
	for peer: Dictionary in players:
		if int(peer.get("player_id", 0)) == int(player.get("player_id", 0)): continue
		var tile: Vector2i = Vector2i(int(peer.x), int(peer.y))
		var at: Vector2 = _remote_position("player:%d" % int(peer.player_id), game.tile_position(tile))
		if Rect2(at - Vector2(24, 66), Vector2(48, 72)).has_point(point): return {"tile": tile, "kind": "player"}
	return {}

func map_click(tile: Vector2i, preferred_kind: String = "") -> void:
	if not active or defeated or recovering or transition_pending: return
	if game.skills_ui.target(tile): return
	interaction.clear()
	for drop: Dictionary in (drops if preferred_kind in ["", "drop"] else []):
		if Vector2i(int(drop.x), int(drop.y)) == tile:
			interaction = {"kind": "drop", "id": int(drop.uid)}
			_approach(tile, 2)
			return
	for peer: Dictionary in (players if preferred_kind in ["", "player"] else []):
		if int(peer.get("player_id", 0)) == int(player.get("player_id", 0)): continue
		if Vector2i(int(peer.x), int(peer.y)) == tile:
			game._cancel_controls()
			interaction = {"kind": "player", "id": int(peer.player_id)}
			return
	for spec: Dictionary in (game.world.get("tile_specs", []) if preferred_kind in ["", "locker"] else []):
		if int(spec.get("spec", -1)) == 16 and Vector2i(int(spec.x), int(spec.y)) == tile:
			interaction = {"kind": "locker", "id": 0, "x": tile.x, "y": tile.y}
			_approach(tile, 1)
			return
	for npc: Dictionary in npcs:
		if Vector2i(int(npc.x), int(npc.y)) != tile: continue
		var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(npc.id)), {}) as Dictionary
		var type: int = int(info.get("type", -1))
		if type in [6, 9, 14]:
			# Original EO dispatches a visible service NPC directly, including
			# shopkeepers behind sealed counters. Never path onto their side.
			game._cancel_controls()
			interaction = {"kind": "skillmaster" if type == 14 else "bank" if type == 9 else "shop", "id": int(npc.index)}
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
	if defeated:
		interaction.clear()
		collect_pending = false
		return
	if game.stick != Vector2.ZERO:
		interaction.clear()
		return
	if game.moving or not game.route.is_empty() or not _action_ready() or game._modal_open(): return
	if not interaction.is_empty():
		if str(interaction.kind) == "player":
			session.request("inspect_player", {"player_id": int(interaction.id)})
			interaction.clear()
			return
		var target: Dictionary = interaction if str(interaction.kind) == "locker" else {}
		for row: Dictionary in ([] if str(interaction.kind) == "locker" else (drops if str(interaction.kind) == "drop" else npcs)):
			if int(row.get("uid" if str(interaction.kind) == "drop" else "index", -1)) == int(interaction.id): target = row
		if not target.is_empty():
			var tile: Vector2i = Vector2i(int(target.x), int(target.y))
			var distance: int = 1 if str(interaction.kind) == "locker" else 2 if str(interaction.kind) == "drop" else NPC_SERVICE_DISTANCE
			if game._distance(game.player_tile, tile) > distance:
				if str(interaction.kind) in ["shop", "bank", "skillmaster"]:
					interaction.clear()
					game._toast("This NPC has left your view.")
					return
				_approach(tile, distance)
				return
			if str(interaction.kind) == "drop": _pickup(int(interaction.id))
			elif str(interaction.kind) == "locker": session.request("locker_open", {"x": int(target.x), "y": int(target.y)})
			else: session.request("skillmaster_open" if str(interaction.kind) == "skillmaster" else "bank_open" if str(interaction.kind) == "bank" else "shop_open", {"npc_index": int(interaction.id)})
		interaction.clear()
		collect_pending = false
	elif collect_pending:
		collect_pending = false
		for drop: Dictionary in drops:
			var tile: Vector2i = Vector2i(int(drop.x), int(drop.y))
			if game._distance(game.player_tile, tile) == 0 and _drop_available(drop) and Time.get_ticks_msec() >= int(loot_attempt_after.get(int(drop.uid), 0)):
				_pickup(int(drop.uid))
				return

func _pickup(uid: int) -> void:
	if pickup_pending.has(uid): return
	loot_attempt_after[uid] = Time.get_ticks_msec() + 2500
	pickup_pending[uid] = Time.get_ticks_msec()
	if session.request("collect", {"uid": uid}) < 0: pickup_pending.erase(uid)

func _drop_available(drop: Dictionary) -> bool:
	var permission: Dictionary = drop_permissions.get(int(drop.uid), {}) as Dictionary
	return permission.is_empty() or int(permission.get("owner", 0)) == int(player.get("player_id", -1)) or Time.get_ticks_msec() >= int(permission.get("until", 0))

func nearest_drop() -> Dictionary:
	var nearest: Dictionary = {}
	var distance: int = 999
	for drop: Dictionary in drops:
		var steps: int = game._distance(game.player_tile, Vector2i(int(drop.x), int(drop.y)))
		if steps <= 2 and steps < distance and _drop_available(drop):
			nearest = drop
			distance = steps
	return nearest

func request_collect() -> void:
	if not active or defeated: return
	game._cancel_controls()
	var drop: Dictionary = nearest_drop()
	if drop.is_empty():
		game._toast("No available drop nearby. Tap ground loot to walk closer.")
		return
	interaction = {"kind": "drop", "id": int(drop.uid)}
	collect_pending = true

func _update_loot_control() -> void:
	if loot_button == null: return
	var drop: Dictionary = nearest_drop()
	loot_button.visible = active and game.started and not game._modal_open() and (not drop.is_empty() or not pickup_pending.is_empty())
	loot_button.disabled = not pickup_pending.is_empty() or defeated
	if not pickup_pending.is_empty(): loot_button.text = "Picking up…"
	elif not drop.is_empty():
		loot_button.text = "Pick up %s ×%d" % [str(item_info("item:%d" % int(drop.id)).get("name", "item")), int(drop.amount)]


func collect_nearby() -> void:
	# Movement animation may finish before Walk_Reply. Keep this intent until confirmed.
	collect_pending = true

func refresh_game_ui() -> void:
	game.quest_label.text = "%s\n%d nearby players  ·  %d NPCs" % [str(game.world.get("name", "Area %s" % str(player.get("map_id", "")))), nearby_count(), npcs.size()]
	game.quest_hint.text = "Progress is saved by your server."
	game.coin_label.text = "%d Gold" % game.coins
	game.location_label.text = "%s  /  %d, %d" % [str(player.get("name", "Player")), game.player_tile.x, game.player_tile.y]
	game.health_label.visible = false
	game.health_label.text = "HP %d / %d" % [int(player.get("hp", 0)), int(player.get("max_hp", player.get("maxhp", 0)))]
	var items: Array[Dictionary] = inventory_items()
	game.inventory_summary.text = "%d belongings" % items.size()
	game.offline_bag_panel.hide()
	game.bag_scroll.show()
	game.bag_grid.refresh()
	var selected: String = str(game.selected_item)
	var info: Dictionary = item_info(selected)
	var worn: bool = is_equipped(selected)
	var owned: bool = owns_item(selected)
	game.item_title.text = str(info.get("name", "Your inventory"))
	var usable: bool = consumable(selected)
	game.equip_button.disabled = not owned or worn or (not usable and int(info.get("type", 0)) not in range(10, 22)) or not _action_ready()
	game.equip_button.text = "Use" if usable else "Equip"
	game.drop_button.disabled = not _action_ready() or bag_amount(item_id(selected)) <= 0 or int(info.get("special", 0)) == 4
	drop_ui.refresh()
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
	var characters: Dictionary = game.manifest.get("characters", {}) as Dictionary
	var layered: Dictionary = characters.get("equipment_layers", {}) as Dictionary
	if not layered.is_empty():
		var definitions: Dictionary = layered.get("layers", {}) as Dictionary
		var parts: Array[Dictionary] = []
		for name: String in ["weapon_back", "skin", "boots", "armor", "hair", "weapon_front"]:
			var graphic: int = int(equipment_graphics[8]) if name.begins_with("weapon") else int(equipment_graphics[4]) if name == "armor" else int(equipment_graphics[0]) if name == "boots" else 0
			if graphic == 0 and name not in ["skin", "hair"]: continue
			var part: Dictionary = definitions.get("%s:%d" % [name, graphic], {}) as Dictionary
			if not part.is_empty(): parts.append(part)
		if not parts.is_empty(): return {"layers": parts, "appearance": {"armor_graphic": int(equipment_graphics[4]), "boots_graphic": int(equipment_graphics[0]), "weapon_graphic": int(equipment_graphics[8])}}
	if int(equipment_graphics[6]) != 0 or int(equipment_graphics[7]) != 0: return {}
	if int(equipment_graphics[0]) not in [0, 1] or int(equipment_graphics[4]) not in [0, 1]: return {}
	if int(equipment_graphics[8]) not in [0, 4]:
		var weapon_variants: Dictionary = characters.get("weapon_variants", {}) as Dictionary
		return weapon_variants.get("a%d_b%d_g%d" % [int(equipment_graphics[4]), int(equipment_graphics[0]), int(equipment_graphics[8])], {}) as Dictionary
	var key: String = "a%d_b%d_w%d" % [int(int(equipment_graphics[4]) == 1), int(int(equipment_graphics[0]) == 1), int(int(equipment_graphics[8]) == 4)]
	var variants: Dictionary = characters.get("hero_variants", {}) as Dictionary
	return variants.get(key, {}) as Dictionary

func npc_health_fraction(index: int) -> float:
	var health: Dictionary = npc_health.get(index, {}) as Dictionary
	if health.is_empty() or Time.get_ticks_msec() >= int(health.get("until", 0)): return -1.0
	return clampf(float(health.get("percent", 100)) / 100.0, 0.0, 1.0)

func _process_events(events: Array) -> void:
	for raw: Variant in events:
		if not raw is Dictionary: continue
		var event: Dictionary = raw as Dictionary
		game.skills_ui.event(event)
		var kind: String = str(event.get("kind", event.get("type", event.get("event", ""))))
		if kind in ["player_damage", "npc_attack"]:
			npc_attack_until[int(event.get("npc_index", -1))] = Time.get_ticks_msec() / 1000.0 + 0.36
			for npc: Dictionary in npcs:
				if int(npc.index) == int(event.get("npc_index", -1)): npc.direction = int(event.get("direction", 0))
			if int(event.get("player_id", -1)) == int(player.get("player_id", -2)):
				var index: int = int(event.get("npc_index", -1))
				var health: Dictionary = npc_health.get(index, {"percent": 100}) as Dictionary
				health["until"] = Time.get_ticks_msec() + 8000
				npc_health[index] = health
		if kind == "peer_attack":
			var pid: int = int(event.get("player_id", -1))
			peer_attacks[pid] = {"until": Time.get_ticks_msec() / 1000.0 + 0.36, "direction": int(event.get("direction", 0))}
			for peer: Dictionary in players:
				if int(peer.get("player_id", -2)) == pid: peer.direction = int(event.get("direction", 0))
		if kind == "player_damage":
			game.player_hit_flash = 0.22
			game.damage_numbers.append({"position": game.player_world + Vector2(0, -62), "value": "-%d" % int(event.get("damage", 0)) if int(event.get("damage", 0)) > 0 else "Miss", "time": 0.85, "player_hit": true})
			if bool(event.get("dead", false)):
				defeated = true
				pending_inputs.clear()
				waiting_for_walk = false
				game._cancel_controls(true)
				game._toast("You were defeated. Returning to your respawn point…")
		if kind == "map_transition" and str(event.get("reason", "")) == "death_respawn": game._toast("You have returned to your respawn point.")
		if kind == "door_locked": game._toast("This door needs a key.")
		if kind in ["npc_damage", "npc_killed"]:
			var index: int = int(event.get("npc_index", -1))
			if kind == "npc_damage": npc_health[index] = {"percent": clampi(int(event.get("hp_percent", 100)), 0, 100), "until": Time.get_ticks_msec() + 8000}
			else: npc_health.erase(index)
			for npc: Dictionary in npcs:
				if int(npc.get("index", -1)) == int(event.get("npc_index", -2)):
					var tile: Vector2i = Vector2i(int(npc.get("x", 0)), int(npc.get("y", 0)))
					game.damage_numbers.append({"position": game.tile_position(tile) + Vector2(0, -44), "value": str(int(event.get("damage", 0))), "time": 0.8})
			if kind == "npc_killed":
				var drop: Dictionary = event.get("drop", {}) as Dictionary
				if int(drop.get("uid", 0)) > 0:
					drop_permissions[int(drop.uid)] = {"owner": int(event.get("player_id", 0)), "until": Time.get_ticks_msec() + 30000}
					game._toast(("%s ×%d dropped. Tap Pick up." if int(event.get("player_id", 0)) == int(player.get("player_id", -1)) else "%s ×%d is reserved for another player.") % [str(item_info("item:%d" % int(drop.id)).get("name", "Item")), int(drop.amount)])
				else: game._toast("Enemy defeated.")
				if event.has("level_up"): game._toast("Level %d reached! Stat points are available in Character Stats." % int(event.level_up))
		if kind == "pickup":
			network_metrics.pickups = int(network_metrics.pickups) + 1
			pickup_pending.erase(int(event.get("uid", 0)))
			game._play_sound("pickup")
			game._toast("Picked up %s ×%d." % [str(item_info("item:%d" % int(event.get("item_id", 0))).get("name", "Item")), int(event.get("amount", 0))])
		if kind == "shop_transaction":
			game.shop_ui.confirm_transaction(event)
		if kind == "drop":
			game._toast("Dropped %s ×%d." % [str(item_info("item:%d" % int(event.get("item_id", 0))).get("name", "Item")), int(event.get("amount", 0))])
		if kind == "item_used":
			game._toast("Used %s." % str(item_info("item:%d" % int(event.get("item_id", 0))).get("name", "item")))
			if int(event.get("hp_gain", 0)) > 0: game.damage_numbers.append({"position": game.player_world + Vector2(0, -62), "value": "+%d" % int(event.hp_gain), "time": 0.85})
		if kind == "chat":
			game.chat_ui.receive(event)
			if str(event.get("channel", "")) == "local" and int(event.get("player_id", 0)) > 0:
				chat_bubbles[int(event.player_id)] = {"text": str(event.get("message", "")), "until": Time.get_ticks_msec() + 5500}
		if kind in ["trade_sent", "trade_complete", "trade_cancelled"]: game._toast(str(event.get("message", "")))
		if kind == "pickup_failed":
			pickup_pending.erase(int(event.get("uid", 0)))
			game._toast(str(event.get("message", "The server refused this pickup.")))

func _slot_name(kind: String) -> String:
	return str({"hat": "head", "shield": "offhand"}.get(kind, kind))

func can_issue_walk() -> bool:
	return active and streaming and not defeated and not recovering and not transition_pending and walk_clock <= 0.0 and game.attack_clock <= 0.0 and pending_inputs.size() < MAX_PREDICTIONS and not session.has_blocking_requests()
