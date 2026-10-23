extends Node
## Owns online UI/session state. No passwords, server position, or items enter the offline save.
const OnlineSession = preload("res://scripts/online_session.gd")
var shortcuts: RefCounted = preload("res://scripts/shortcut_sync.gd").new()
var drop_ui: RefCounted
var game: Node
var session: OnlineSession
var panel: Control
var status_label: Label
var chat_bubbles: Dictionary = {}
var spell_labels: Dictionary = {}
var trade: Dictionary = {}
var server_label: Label
var host_field: LineEdit
var port_field: SpinBox
var username_field: LineEdit
var password_field: LineEdit
var creation_panel: Control
var body_choice: OptionButton
var skin_choice: OptionButton
var hair_choice: OptionButton
var color_choice: OptionButton
var creation_status: Label
var character_preview: Control
var character_name_field: LineEdit
var character_flow: RefCounted = preload("res://scripts/character_flow.gd").new()
var creating_character: bool = false
var entering_character: bool = false
var last_created_name: String = ""
var character_cards: HBoxContainer
var selection_previews: Array[Control] = []
var character_list: ItemList
var auth_box: Control
var character_box: Control
var selected_characters: Array[Dictionary] = []
var active: bool = false
var waiting_for_walk: bool = false
const NPC_SERVICE_DISTANCE: int = 11
# Native Walk is 400 ms plus a 20 ms auto-queue dispatch stage.
const MOVE_SECONDS: float = 0.42
# Buffer only remote presentation; local input remains immediately predicted.
const REMOTE_BUFFER_SECONDS: float = 0.10
const MAX_PREDICTIONS: int = 4
var streaming: bool = false
var recovering: bool = false
var defeated: bool = false
var npc_attack_until: Dictionary = {}
var peer_attacks: Dictionary = {}
var npc_health: Dictionary = {}
var npc_hit_until: Dictionary = {}
var previous_npc_tiles: Dictionary = {}
var last_face_at: int = -125
var pending_face: String = ""
var transition_pending: bool = false
var next_input_seq: int = 0
var confirmed_input_seq: int = 0
var pending_inputs: Array[Dictionary] = []
var remote_motion: Dictionary = {}
var refresh_clock: float = 0.0
var desired_auth: String = "login"
var player: Dictionary = {}
var players: Array[Dictionary] = []
var npcs: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var last_error: String = ""
var warp_notice_clock: float = 0.0
var catalog: Dictionary = {}
var request_operations: Dictionary = {}
var interaction: Dictionary = {}
var collect_pending: bool = false
var loot_attempt_after: Dictionary = {}
var pickup_pending: Dictionary = {}
var pending_equip: Dictionary = {}
var pending_item_use: bool = false
var pending_potion_requests: Dictionary = {}
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
	character_flow.build(self,parent)
	server_label = game._label(parent, "", Vector2(390, 67), 15, game.MUTED)
	server_label.hide()
	loot_button = preload("res://scripts/hud_icon_button.gd").new()
	loot_button.set("kind", "hand")
	loot_button.position = Vector2(-94, -406) + game.COMBAT_HUD_SHIFT
	loot_button.size = Vector2(68, 68)
	loot_button.pressed.connect(request_collect)
	parent.add_child(loot_button)
	loot_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	loot_button.clip_text = true
	loot_button.add_theme_font_size_override("font_size", 17)
	loot_button.hide()

func creation_appearance() -> Dictionary:
	return {"gender": body_choice.get_selected_id(), "hairstyle": hair_choice.get_selected_id(), "haircolor": color_choice.get_selected_id(), "race": skin_choice.get_selected_id()}

func _update_creation_preview() -> void:
	if character_preview == null: return
	character_preview.appearance = creation_appearance()
	character_preview.queue_redraw()
	character_flow.refresh_creation()

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
	creation_panel.hide()
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
	if creation_status != null: creation_status.text = value
	last_error = value
	if status_label != null: status_label.text = value

func _on_message(message: Dictionary) -> void:
	if str(message.get("op", "")) == "shortcuts_set":
		shortcuts.response(message)
		return
	game.chat_ui.response(message)
	game.redeem_ui.response(message)
	game.guild_ui.response(message)
	game.quest_journal.response(message)
	var operation: String = str(message.get("op", message.get("event", "")))
	if not bool(message.get("ok", true)):
		if operation == "create_character": creating_character = false; last_created_name = ""
		if operation == "enter": entering_character = false
		character_flow.refresh()
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
		if operation == "spell_cast": game.skills_ui.cancel_cast()
		if operation in ["item_drop", "item_junk"]:
			drop_ui.submitting = false
			drop_ui.refresh()
		if operation == "spend_stat": game.stats_ui.stop_repeat()
		if operation in ["item_use", "potion_use"]:
			if operation == "potion_use": pending_potion_requests.erase(int(message.get("id", -1)))
			else: pending_item_use = false
			game._refresh_ui()
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
		"move", "face", "strike", "collect", "spell_cast", "spell_cancel", "online_players", "potion_use":
			pass # Receipt only. The subsequent native Walk_Reply confirms acceptance.
		"unequip":
			_apply_snapshot(data)
			if not pending_equip.is_empty():
				var replacement: Dictionary = pending_equip.duplicate()
				pending_equip.clear()
				if int((player.get("equipment", {}) as Dictionary).get(str(replacement.slot), 0)) == 0:
					session.request("equip", {"item_id": int(replacement.item_id), "subloc": int(replacement.subloc)})
				else: game._toast("The worn item could not be removed. Your replacement remains in the bag.")
		"party_invite", "party_join", "party_accept", "party_decline", "party_leave", "party_kick", "party_refresh", "bard_note", "guild_open", "guild_info", "guild_members", "guild_close", "guild_refresh", "guild_begin", "guild_found", "guild_support", "guild_join", "guild_recruit", "guild_deposit", "guild_description", "guild_ranks", "guild_rank", "guild_kick", "guild_leave", "guild_disband", "guild_chat", "inn_open", "inn_quote", "inn_sleep", "inn_close", "quest_open", "quest_reply", "quest_close", "quest_list", "sit", "world", "refresh", "snapshot", "attack", "pickup", "equip", "spend_stat", "shop_buy", "shop_sell", "shop_craft", "bank_deposit", "bank_withdraw", "bank_upgrade", "locker_deposit", "locker_withdraw", "chest_deposit", "chest_take", "chest_close", "trade_request", "trade_accept", "trade_decline", "trade_add", "trade_remove", "trade_agree", "trade_cancel", "chat_send", "item_use", "skill_learn", "skill_forget", "skill_level":
			_apply_snapshot(data)
		"redeem_code":
			_apply_snapshot(data)
			game._toast("Rewards claimed — check your bag!")
		"item_drop", "item_junk":
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
		"bank_open", "locker_open", "chest_open":
			_apply_snapshot(data)
			var kind: String = "bank" if operation == "bank_open" else "chest" if operation == "chest_open" else "locker"
			game.services_ui.open(kind, data.get(kind, {}) as Dictionary)
		"shop_open":
			_apply_snapshot(data)
			game.shop_ui.open(data.get("shop", {}) as Dictionary)
		"disconnect":
			_on_closed("Disconnected from the world.")

func _show_characters(characters: Array) -> void:
	creation_panel.hide()
	selected_characters.clear()
	character_list.clear()
	creating_character = false
	entering_character = false
	var selected: int = 0
	for raw: Variant in characters:
		var character: Dictionary = raw as Dictionary
		selected_characters.append(character)
		character_list.add_item(str(character.get("name","Character")))
		if str(character.get("name","")) == last_created_name: selected = selected_characters.size()-1
	last_created_name = ""
	character_flow.show_characters()
	if not selected_characters.is_empty(): character_list.select(selected); _select_character_card(selected)
	auth_box.hide()
	character_box.show()
	_set_status("Choose a character to enter the world." if not selected_characters.is_empty() else "No characters yet. Tap an empty slot to create your first one.")

func _enter_selected() -> void:
	if entering_character or creating_character: return
	var selection: PackedInt32Array = character_list.get_selected_items()
	if selection.is_empty():
		_set_status("Create or select a character first.")
		return
	var character: Dictionary = selected_characters[selection[0]]
	_set_status("Entering the world…")
	entering_character = session.request("enter", {"character_id": int(character.get("id", 0))}) >= 0
	character_flow.refresh()

func _character_letters(value: String) -> bool:
	for index: int in range(value.length()):
		if value.unicode_at(index) < 97 or value.unicode_at(index) > 122: return false
	return true

func _create_character() -> void:
	if creating_character or entering_character: return
	if selected_characters.size() >= character_flow.MAX_CHARACTERS:
		_set_status("This account already has all three character slots filled.")
		return
	var name: String = character_name_field.text.strip_edges().to_lower()
	if name.length() < 4 or name.length() > 12 or not _character_letters(name):
		_set_status("Choose a name with 4–12 letters.")
		return
	_set_status("Creating your character…")
	var fields: Dictionary = creation_appearance()
	fields.name = name
	last_created_name = name
	creating_character = session.request("create_character", fields) >= 0
	character_flow.refresh()

func _enter_world(data: Dictionary) -> void:
	entering_character = false
	creation_panel.hide()
	game.drink_effects.clear()
	game.chat_ui.clear()
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
	game._toast("Arena · stand on a marked gate tile. Rounds every %ds." % int((game.world.arena as Dictionary).get("interval_seconds", 90)) if game.world.has("arena") else "You have entered your online world.")

func _apply_snapshot(data: Dictionary, entering: bool = false) -> void:
	for raw: Variant in data.get("events", []):
		if raw is Dictionary and str(raw.get("kind", "")) == "map_transition": entering = true
	if data.has("player"):
		var previous_sitting: int = int(player.get("sitting", 0))
		player = data.player as Dictionary
		if data.has("shortcuts"):
			shortcuts.begin(self, data.shortcuts as Dictionary)
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
			game.music.enter_map(game.world)
			if game.sfx != null: game.sfx.enter_map(game.world)
			game.quest_ui.panel.hide()
			game.guild_ui.panel.hide()
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
			spell_labels.clear()
			npc_health.clear()
			waiting_for_walk = false
			transition_pending = false
			game.facing = _facing(player.get("direction", 0))
			game.player_tile = tile
			game.player_world = game.tile_position(tile)
			game.moving = false
			game.camera.position = game.player_world
			game.camera.reset_smoothing()
		elif previous_sitting != int(player.get("sitting", 0)):
			game._cancel_controls(true)
			pending_inputs.clear()
			waiting_for_walk = false
			game.player_tile = tile
			game.player_world = game.tile_position(tile)
			game.facing = _facing(player.get("direction", 0))
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
	previous_npc_tiles.clear()
	for npc: Dictionary in npcs: previous_npc_tiles[int(npc.index)] = Vector2i(int(npc.x), int(npc.y))
	if data.has("npcs"): npcs = _dict_array(data.npcs)
	else: npcs = _merge_updates(npcs, data.get("npcs_upsert", []), data.get("npcs_remove", []), "index")
	if data.has("items"): drops = _dict_array(data.items)
	else: drops = _merge_updates(drops, data.get("items_upsert", []), data.get("items_remove", []), "uid")
	for raw: Variant in data.get("events", []):
		if raw is Dictionary and str(raw.get("kind", "")) == "seating": remote_motion.erase("player:%d" % int(raw.player_id))
	_track_entities("player", players, "player_id")
	_track_entities("npc", npcs, "index")
	_process_events(data.get("events", []) as Array)
	game._refresh_ui()
	game.shop_ui.refresh()
	if data.has("trade"): trade = data.trade as Dictionary if data.trade is Dictionary else {}
	game.drink_effects.receive(player)
	game.skills_ui.receive(data)
	game.quest_ui.receive(data)
	game.quest_journal.receive(data)
	game.inn_ui.receive(data)
	game.guild_ui.receive(data)
	game.party_ui.receive(data)
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
	for collection: Dictionary in [chat_bubbles, spell_labels]:
		for key: Variant in collection.keys():
			if Time.get_ticks_msec() >= int((collection[key] as Dictionary).until): collection.erase(key)
	_flush_face()
	_process_interaction()
	warp_notice_clock = maxf(0.0, warp_notice_clock - delta)
	refresh_clock += delta
	# Original EO updates are event driven; no periodic full-world Refresh.
	_update_loot_control()
	if not pending_inputs.is_empty() and Time.get_ticks_msec() - int(pending_inputs[0].sent_at) > 15000:
		session._fail("Movement confirmation timed out. Please reconnect.")

func seated() -> bool:
	return int(player.get("sitting", 0)) != 0

func toggle_sit(tile: Vector2i = Vector2i(-1, -1)) -> void:
	if not _action_ready() or game.moving: return
	game._cancel_controls()
	pending_face = ""
	var fields: Dictionary = {} if seated() or tile.x < 0 else {"x": tile.x, "y": tile.y}
	session.request("sit", fields)

func request_step(direction: Vector2i) -> void:
	if seated():
		toggle_sit()
		return
	if not active or defeated or recovering or transition_pending or game.moving: return
	if direction not in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]: return
	var single: Vector2i = direction
	var target: Vector2i = game.player_tile + single
	if not game._can_step(game.player_tile, single):
		request_face(game._direction_name(single))
		return
	if not can_issue_walk(): return
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
	next_input_seq += 1
	network_metrics.moves = int(network_metrics.moves) + 1
	fields.merge({"input_seq": next_input_seq, "map_id": int(game.world.id), "x": target.x, "y": target.y})
	pending_face = ""
	if session.request("move", fields) < 0: return
	pending_inputs.append({"seq": next_input_seq, "direction": single, "sent_at": Time.get_ticks_msec()})
	waiting_for_walk = true
	transition_pending = passage
	refresh_clock = 0.0
	_start_step(target, game._direction_name(single))

func _start_step(tile: Vector2i, direction: String) -> void:
	game.step_origin_tile = game.player_tile
	game.step_from = game.player_world
	game.step_to = game.tile_position(tile)
	game.player_tile = tile
	game.step_progress = 0.0
	game.step_duration = MOVE_SECONDS
	game.facing = direction
	game.animation_clock = 0.0
	game.moving = true

func _reset_movement() -> void:
	game.timed_spikes_until = 0
	pending_item_use = false
	pending_potion_requests.clear()
	pending_face = ""
	npc_hit_until.clear()
	previous_npc_tiles.clear()
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
	refresh_clock = 0.0

func mobile_action_ready() -> bool:
	return active and not defeated and not recovering and not transition_pending and not session.has_blocking_requests() and trade.is_empty()

func _action_ready() -> bool:
	return active and not defeated and not recovering and pending_inputs.is_empty() and not transition_pending and session.is_idle()

func is_combat_npc(npc: Dictionary) -> bool:
	var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(npc.get("id", 0))), {}) as Dictionary
	return int(info.get("type", -1)) in [1, 2] # Original ENF Passive/Aggressive only.

func request_attack() -> bool:
	game.skills_ui.armed = 0
	if not game.skills_ui.casting.is_empty(): return false
	if not active or seated() or defeated or recovering or game.moving or transition_pending or session.has_blocking_requests() or session.pending.size() >= MAX_PREDICTIONS: return false
	# Original attacks follow the chosen facing; do not redirect to another NPC.
	var adjacent: Array[Dictionary] = []
	for npc: Dictionary in npcs:
		if game._distance(game.player_tile, Vector2i(int(npc.x), int(npc.y))) == 1: adjacent.append(npc)
	var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
	pending_face = ""
	var sent: bool = session.request("strike", {"direction": _direction(game.facing)}) >= 0
	if sent:
		var target_tile: Vector2i = game.player_tile + offsets[_direction(game.facing)]
		for npc: Dictionary in adjacent:
			if Vector2i(int(npc.x), int(npc.y)) != target_tile or not is_combat_npc(npc): continue
			var index: int = int(npc.index)
			var health: Dictionary = npc_health.get(index, {"percent": 100}) as Dictionary
			health["until"] = Time.get_ticks_msec() + 8000
			npc_health[index] = health
	return sent

func request_face(direction: String) -> void:
	if not active or seated() or defeated or recovering or game.moving or transition_pending or not game.skills_ui.casting.is_empty(): return
	if game.facing != direction:
		game.facing = direction
		player["direction"] = _direction(direction)
		pending_face = direction
	for collection: Dictionary in [chat_bubbles, spell_labels]:
		for key: Variant in collection.keys():
			if Time.get_ticks_msec() >= int((collection[key] as Dictionary).until): collection.erase(key)
	_flush_face()

func _flush_face() -> void:
	if pending_face.is_empty() or Time.get_ticks_msec() - last_face_at < 125 or session.pending.size() >= MAX_PREDICTIONS: return
	if not active or defeated or recovering or transition_pending or game.moving or not game.skills_ui.casting.is_empty(): pending_face = ""; return
	last_face_at = Time.get_ticks_msec()
	session.request("face", {"direction": _direction(pending_face)})
	pending_face = ""

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
	creating_character = false; entering_character = false; last_created_name = ""
	shortcuts.disconnected()
	game.party_ui.disconnected()
	game.skills_ui.target_panel.hide(); game.skills_ui.bard_panel.hide()
	game.drink_effects.clear()
	creation_panel.hide()
	game.inn_ui.panel.hide()
	game.guild_ui.disconnected()
	game.quest_journal.disconnected()
	game.movement_ui.disconnected()
	game.music.leave_world()
	if game.sfx != null: game.sfx.stop()
	game.quest_ui.panel.hide()
	game.redeem_ui.disconnected()
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
	game.stats_ui.dismiss()
	game.menu.hide()
	_set_status(reason)
	game._toast(reason)

func _track_entities(kind: String, rows: Array[Dictionary], id_field: String, at: float = -1.0) -> void:
	var seen: Dictionary = {}
	var now: float = Time.get_ticks_msec() / 1000.0 if at < 0.0 else at
	for record: Dictionary in rows:
		# JSON IDs arrive as floats; all sprite, bubble and hit-test keys use ints.
		var key: String = kind + ":" + str(int(record.get(id_field, -1)))
		seen[key] = true
		var tile: Vector2i = Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
		var target: Vector2 = game.tile_position(tile)
		if kind == "player" and int(record.get("sitting", 0)) > 0:
			remote_motion[key] = {"to":target,"tile":tile,"steps":[],"walk_start":now}
			continue
		if remote_motion.has(key) and remote_motion[key].to == target: continue
		var motion: Dictionary = remote_motion.get(key, {}) as Dictionary
		var distance: int = 0 if motion.is_empty() else absi(tile.x - int(motion.tile.x)) + absi(tile.y - int(motion.tile.y))
		# Spawns, warps and missed multi-tile updates establish a new baseline.
		# Never invent a route through walls to interpolate an unknown path.
		if motion.is_empty() or distance != 1:
			remote_motion[key] = {"to":target,"tile":tile,"steps":[],"walk_start":now}
			continue
		_remote_sample(key, target, now)
		var steps: Array = motion.steps
		if steps.size() >= MAX_PREDICTIONS:
			remote_motion[key] = {"to":target,"tile":tile,"steps":[],"walk_start":now}
			continue
		var end: float = float(steps.back().start) + MOVE_SECONDS if not steps.is_empty() else now - 1.0
		var start: float = end if end >= now else now + REMOTE_BUFFER_SECONDS
		if end < now: motion.walk_start = start
		# Original EO queues/replays adjacent steps instead of restarting the
		# current interpolation from a fractional position on every packet.
		steps.append({"from":motion.to,"to":target,"start":start,"direction":_facing(record.get("direction", 0))})
		motion.to = target
		motion.tile = tile
	for key: Variant in remote_motion.keys():
		if str(key).begins_with(kind + ":") and not seen.has(key): remote_motion.erase(key)

func _remote_sample(key: String, fallback: Vector2, now: float) -> Dictionary:
	var motion: Dictionary = remote_motion.get(key, {}) as Dictionary
	if motion.is_empty(): return {"position":fallback,"state":"idle","phase":0.0}
	var steps: Array = motion.steps
	while steps.size() > 1 and now >= float(steps[0].start) + MOVE_SECONDS:
		steps.pop_front()
	if steps.is_empty(): return {"position":motion.to,"state":"idle","phase":0.0}
	var step: Dictionary = steps[0]
	var elapsed: float = now - float(step.start)
	var fraction: float = clampf(elapsed / MOVE_SECONDS, 0.0, 1.0)
	return {"position":(step.from as Vector2).lerp(step.to as Vector2, fraction),"state":"frames" if elapsed >= 0.0 and elapsed < MOVE_SECONDS else "idle","phase":maxf(0.0, now - float(motion.walk_start)),"direction":step.direction}

func _remote_position(key: String, fallback: Vector2) -> Vector2:
	return _remote_sample(key, fallback, Time.get_ticks_msec() / 1000.0).position

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
	var key: String = ("npc:" + str(int(record.get("index", -1)))) if kind == "online_npc" else ("player:" + str(int(record.get("player_id", -1))))
	var now: float = Time.get_ticks_msec() / 1000.0
	var sample: Dictionary = _remote_sample(key, Vector2.ZERO, now)
	var phase: float = float(sample.phase)
	var state: String = str(sample.state)
	var direction: String = str(sample.get("direction", _facing(record.get("direction", 0)))) if state == "frames" else _facing(record.get("direction", 0))
	if kind == "online_npc" and float(npc_attack_until.get(int(record.get("index", -1)), 0.0)) > now:
		state = "attack"
		phase = (0.36 - (float(npc_attack_until[int(record.index)]) - now)) * game.ONLINE_ATTACK_SWING_DURATION / 0.36
	var attack: Dictionary = peer_attacks.get(int(record.get("player_id", -1)), {}) as Dictionary
	if kind == "online_player" and float(attack.get("until", 0.0)) > now:
		state = "attack"
		phase = game.ONLINE_ATTACK_SWING_DURATION - (float(attack.until) - now)
		direction = _facing(attack.direction)
	if kind == "online_player" and state == "idle" and game.skills_ui.is_chanting(int(record.get("player_id", -1))): state = "cast"
	if kind == "online_player" and int(record.get("sitting", 0)) > 0:
		state = "sit_chair" if int(record.sitting) == 1 else "sit_floor"
		direction = _facing(record.get("direction", 0))
	return {"key": key, "state": state, "phase": phase, "direction": direction}

func player_name_offset(name: String) -> Vector2:
	# Original CharacterRenderer centers the measured label on the 18px body,
	# never on asymmetric equipment bounds. Keep this stable through animations.
	var width: float = ThemeDB.fallback_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	return Vector2(-width / 2.0, -66)

func npc_name_layout(graphic: Dictionary, direction: String, _fighting: bool) -> Dictionary:
	# Use the original visible standing art, including its render offset. This
	# keeps names close to heads and stable while a walking/attack pose changes.
	var frame: Dictionary = game._frame(graphic, direction, "idle", 0.0)
	var region: Array = frame.get("region", [0, 0, 20, 24]) as Array
	var offset: Array = frame.get("offset", [0, 0]) as Array
	var visible: Array = frame.get("visible_bounds", [0, 0, region[2], region[3]]) as Array
	var head: Vector2 = Vector2(float(offset[0]) - float(region[2]) / 2.0 + float(visible[0]) + float(visible[2]) / 2.0, float(offset[1]) - float(region[3]) + float(visible[1]))
	# NPCRenderer.HorizontalCenter cancels the sprite's asymmetric X offset.
	# Keep the name at its idle height; combat adds a strip above the name.
	return {"head": head, "name": Vector2(0, head.y - 5), "health": Rect2(Vector2(-36 if float(region[2]) > 100 else -17, head.y - 25), Vector2(72 if float(region[2]) > 100 else 34, 5))}

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
		if not graphic.is_empty(): game._draw_character_frame(graphic, at, direction, state, Color("ffb8a0") if Time.get_ticks_msec() < int(npc_hit_until.get(int(record.index), 0)) else Color.WHITE, phase if state in ["frames", "attack"] else -1.0)
		else: game.draw_circle(at + Vector2(0, -12), 5.0, Color("e7bd70"))
		var health: float = npc_health_fraction(int(record.get("index", -1)))
		var layout: Dictionary = npc_name_layout(graphic, direction, health >= 0.0)
		var name: String = str(info.get("name", "NPC %s" % npc_id))
		var text_width: float = ThemeDB.fallback_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if health < 0.0: game.draw_string(ThemeDB.fallback_font, at + (layout.name as Vector2) - Vector2(text_width / 2.0, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, game.TEXT)
	elif str(entity.kind) == "online_player":
		var graphic: Dictionary = character_graphic(record)
		if not graphic.is_empty(): game._draw_character_frame(graphic, at, direction, state, Color.WHITE, phase if state in ["frames", "attack"] else -1.0)
		else:
			game.draw_circle(at + Vector2(0, -12), 7.0, Color("a6cec0"))
			game.draw_string(ThemeDB.fallback_font, at + Vector2(-32, -42), "Appearance pending", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, game.MUTED)
		var name: String = str(record.get("name", "Player"))
		game.draw_string(ThemeDB.fallback_font, at + player_name_offset(name), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b9e2c5"))
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

func chat_bubble_position(pid: int) -> Vector2:
	if pid == int(player.get("player_id", 0)): return game.player_world
	for peer: Dictionary in players:
		if int(peer.get("player_id", 0)) == pid:
			return _remote_position("player:%d" % pid, game.tile_position(Vector2i(int(peer.x), int(peer.y))))
	return Vector2.INF

func show_speech(event: Dictionary) -> void:
	if str(event.get("channel", "")) != "local": return
	var pid: int = int(player.get("player_id", -1)) if bool(event.get("outgoing", false)) else int(event.get("player_id", -1))
	if pid < 0 or str(event.get("message", "")).strip_edges().is_empty(): return
	chat_bubbles[pid] = {"text": str(event.message), "until": Time.get_ticks_msec() + 5500, "drunk": bool(event.get("drunk", false))}
	if game.speech_layer != null: game.speech_layer.sync()

func draw_chat_bubbles() -> void:
	# Speech lives in a real HUD overlay; spell labels retain original blinking text.
	if not active: return
	for key: Variant in spell_labels.keys():
		var at: Vector2 = chat_bubble_position(int(key))
		if at.is_finite(): draw_chat_bubble(int(key), at)

func draw_chat_bubble(pid: int, at: Vector2) -> void:
	var bubble: Dictionary = spell_labels.get(pid, {}) as Dictionary
	var now: int = Time.get_ticks_msec()
	if bubble.is_empty() or now >= int(bubble.until): return
	if int((now - int(bubble.get("start", now))) / 250.0) % 2 == 1: return
	var text: String = str(bubble.text)
	var font: Font = ThemeDB.fallback_font
	var origin: Vector2 = at + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x / 2.0, -82)
	game.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
	game.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, game.TEXT)

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

func profile_identity() -> String:
	if not active or not game.online_mode: return ""
	var name: String = str(player.get("name", "")).strip_edges().to_lower()
	if name.is_empty(): return ""
	var host: String = host_field.text.strip_edges().to_lower().trim_suffix("/")
	if not host.begins_with("ws://") and not host.begins_with("wss://"): host += ":%d" % int(port_field.value)
	return "%s/character/%s" % [host, name]

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
	var potion: bool = int(item_info(kind).get("type", -1)) == 3
	if not owns_item(kind) or pending_item_use: return
	if potion:
		if not mobile_action_ready(): return
	else:
		if not _action_ready(): return
		game._cancel_controls()
	if potion:
		if pending_potion_requests.size() >= 4: return
		var request_id: int = session.request("potion_use", {"item_id": item_id(kind)})
		if request_id >= 0: pending_potion_requests[request_id] = item_id(kind)
	else:
		pending_item_use = true
		if session.request("item_use", {"item_id": item_id(kind)}) < 0: pending_item_use = false

	if int(item_info(kind).get("type", -1)) == 4: game.inventory.hide()
	game.equip_button.disabled = true

func equipment_request(kind: String) -> void:
	if not _action_ready() or not pending_equip.is_empty() or not owns_item(kind): return
	var info: Dictionary = item_info(kind)
	# Bag item IDs can also be worn. Only a paperdoll slot means Unequip;
	# another copy in the bag must equip into an available paired slot.
	if not kind.begins_with("item:") and is_equipped(kind):
		if int(info.get("special", 0)) == 5:
			game._toast("This item is cursed and cannot be removed.")
			return
		var subloc: int = 1 if _slot_name(kind).ends_with("2") else 0
		session.request("unequip", {"item_id": item_id(kind), "subloc": subloc})
	else:
		if bag_amount(item_id(kind)) <= 0: return
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
	var friendly: bool = game.skills_ui.armed > 0 and int(game.skills_ui.info(game.skills_ui.armed).get("restrict",0)) == 1
	if friendly:
		var candidates: Array = [player] + players
		for peer: Dictionary in candidates:
			var pid: int = int(peer.get("player_id",0))
			var tile: Vector2i = Vector2i(int(peer.get("x",0)),int(peer.get("y",0)))
			var at: Vector2 = game.player_world if pid == int(player.get("player_id",-1)) else _remote_position("player:%d" % pid,game.tile_position(tile))
			if Rect2(at-Vector2(24,76),Vector2(48,82)).has_point(point): return {"tile":tile,"kind":"player"}
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
	# Match chest/locker artwork, including its front above the blocked tile.
	for spec: Dictionary in ([] if game.skills_ui.armed > 0 else game.world.get("tile_specs", [])):
		if int(spec.get("spec", -1)) not in [1, 2, 3, 4, 5, 6, 7, 9, 16]: continue
		var tile: Vector2i = Vector2i(int(spec.x), int(spec.y))
		for decoration: Dictionary in game.decorations:
			if decoration.tile != tile or str(decoration.layer) != "objects": continue
			var texture: Texture2D = game._graphic(int(decoration.gfx), int(decoration.id))
			if texture == null: continue
			var size: Vector2 = texture.get_size()
			if int(decoration.gfx) == 3 and size.x >= 128: size.x /= 4.0
			if Rect2(game.tile_position(tile) + Vector2(-2.0 - size.x / 2.0, 14.0 - size.y), size).grow(4.0).has_point(point): return {"tile": tile, "kind": "chair" if int(spec.spec) in range(1, 8) else "chest" if int(spec.spec) == 9 else "locker"}
	for peer: Dictionary in players:
		if int(peer.get("player_id", 0)) == int(player.get("player_id", 0)): continue
		var tile: Vector2i = Vector2i(int(peer.x), int(peer.y))
		var at: Vector2 = _remote_position("player:%d" % int(peer.player_id), game.tile_position(tile))
		if Rect2(at - Vector2(24, 66), Vector2(48, 72)).has_point(point): return {"tile": tile, "kind": "player"}
	return {}

func map_click(tile: Vector2i, preferred_kind: String = "") -> void:
	if not active or defeated or recovering or transition_pending: return
	if seated():
		toggle_sit()
		return
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
	for spec: Dictionary in (game.world.get("tile_specs", []) if preferred_kind in ["", "locker", "chest", "chair"] else []):
		if int(spec.get("spec", -1)) in [1, 2, 3, 4, 5, 6, 7, 9, 16] and Vector2i(int(spec.x), int(spec.y)) == tile:
			interaction = {"kind": "chair" if int(spec.spec) in range(1, 8) else "chest" if int(spec.spec) == 9 else "locker", "id": 0, "x": tile.x, "y": tile.y, "spec": int(spec.spec)}
			if str(interaction.kind) == "chair": _approach_chair(tile, int(spec.spec))
			else: _approach(tile, 1)
			return
	for npc: Dictionary in npcs:
		if Vector2i(int(npc.x), int(npc.y)) != tile: continue
		var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(npc.id)), {}) as Dictionary
		var type: int = int(info.get("type", -1))
		if type in [6, 7, 9, 11, 14, 15]:
			# Original EO dispatches a visible service NPC directly, including
			# shopkeepers behind sealed counters. Never path onto their side.
			game._cancel_controls()
			interaction = {"kind": "guild" if type == 11 else "inn" if type == 7 else "quest" if type == 15 else "skillmaster" if type == 14 else "bank" if type == 9 else "shop", "id": int(npc.index)}
		elif is_combat_npc(npc):
			if game._distance(game.player_tile, tile) == 1:
				var direction: String = game._direction_name(tile - game.player_tile)
				if game.attack_clock > 0.0: request_face(direction)
				else: game.facing = direction
				game._attack()
			else: _approach(tile, 1)
		else: game._toast("%s is not a combat target." % str(info.get("name", "NPC")))
		return
	game._request_path(tile)

func chair_sides(spec: int) -> Array[Vector2i]:
	match spec:
		1: return [Vector2i.DOWN]
		2: return [Vector2i.LEFT]
		3: return [Vector2i.RIGHT]
		4: return [Vector2i.UP]
		5: return [Vector2i.DOWN, Vector2i.RIGHT]
		6: return [Vector2i.UP, Vector2i.LEFT]
		7: return [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
	return []

func _approach_chair(tile: Vector2i, spec: int) -> void:
	game.route.clear()
	for peer: Dictionary in players:
		if Vector2i(int(peer.x), int(peer.y)) == tile:
			interaction.clear()
			game._toast("This chair is occupied.")
			return
	var choices: Array[Vector2i] = []
	for side: Vector2i in chair_sides(spec):
		var candidate: Vector2i = tile + side
		if candidate == game.player_tile: return
		if game._walkable(candidate): choices.append(candidate)
	choices.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return game._distance(game.player_tile, a) < game._distance(game.player_tile, b))
	for choice: Vector2i in choices:
		game._request_path(choice)
		if not game.route.is_empty(): return
	interaction.clear()
	game._toast("Reach the open side of the chair.")

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
	if game._input_direction() != Vector2i.ZERO:
		interaction.clear()
		return
	if game.moving or not game.route.is_empty() or not _action_ready() or game._modal_open(): return
	if not interaction.is_empty():
		if str(interaction.kind) == "player":
			session.request("inspect_player", {"player_id": int(interaction.id)})
			interaction.clear()
			return
		var target: Dictionary = interaction if str(interaction.kind) in ["locker", "chest", "chair"] else {}
		for row: Dictionary in ([] if str(interaction.kind) in ["locker", "chest", "chair"] else (drops if str(interaction.kind) == "drop" else npcs)):
			if int(row.get("uid" if str(interaction.kind) == "drop" else "index", -1)) == int(interaction.id): target = row
		if not target.is_empty():
			var tile: Vector2i = Vector2i(int(target.x), int(target.y))
			var distance: int = 1 if str(interaction.kind) in ["locker", "chest", "chair"] else 2 if str(interaction.kind) == "drop" else NPC_SERVICE_DISTANCE
			if game._distance(game.player_tile, tile) > distance:
				if str(interaction.kind) in ["shop", "bank", "skillmaster", "quest", "inn", "guild"]:
					interaction.clear()
					game._toast("This NPC has left your view.")
					return
				_approach(tile, distance)
				return
			if str(interaction.kind) == "chair": toggle_sit(tile)
			elif str(interaction.kind) == "drop": _pickup(int(interaction.id))
			elif str(interaction.kind) in ["locker", "chest", "chair"]: session.request("chest_open" if str(interaction.kind) == "chest" else "locker_open", {"x": int(target.x), "y": int(target.y)})
			else: session.request("guild_open" if str(interaction.kind) == "guild" else "inn_open" if str(interaction.kind) == "inn" else "quest_open" if str(interaction.kind) == "quest" else "skillmaster_open" if str(interaction.kind) == "skillmaster" else "bank_open" if str(interaction.kind) == "bank" else "shop_open", {"npc_index": int(interaction.id)})
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
	loot_button.text = ""
	if not pickup_pending.is_empty(): loot_button.tooltip_text = "Picking up…"
	elif not drop.is_empty():
		loot_button.tooltip_text = "Pick up %s ×%d" % [str(item_info("item:%d" % int(drop.id)).get("name", "item")), int(drop.amount)]


func collect_nearby() -> void:
	# Movement animation may finish before Walk_Reply. Keep this intent until confirmed.
	collect_pending = true

func refresh_game_ui() -> void:
	if game.quick_items != null: game.quick_items.refresh()
	game.quest_label.text = "%s\n%d nearby players  ·  %d NPCs" % [str(game.world.get("name", "Area %s" % str(player.get("map_id", "")))), nearby_count(), npcs.size()]
	game.quest_hint.text = "Progress is saved by your server."
	game.coin_label.text = "%d Gold" % game.coins
	game.location_label.text = "%s  /  %d, %d" % [str(player.get("name", "Player")), game.player_tile.x, game.player_tile.y]
	game.health_label.visible = false
	game.health_label.text = "HP %d / %d" % [int(player.get("hp", 0)), int(player.get("max_hp", player.get("maxhp", 0)))]
	var items: Array[Dictionary] = inventory_items()
	var stats: Dictionary = player.get("stats", {}) as Dictionary
	var weight: int = int(stats.get("weight", 0))
	var capacity: int = int(stats.get("max_weight", 0))
	game.inventory_summary.text = "%d belongings   ·   Weight %d / %d%s" % [items.size(), weight, capacity, "  ·  Overweight" if capacity > 0 and weight >= capacity else ""]
	game.inventory_summary.modulate = Color("f29b81") if capacity > 0 and weight >= capacity else Color.WHITE
	game.offline_bag_panel.hide()
	game.bag_scroll.show()
	game.bag_grid.refresh()
	var selected: String = str(game.selected_item)
	var info: Dictionary = item_info(selected)
	var owned: bool = owns_item(selected)
	game.item_title.text = str(info.get("name", "Your inventory"))
	var usable: bool = consumable(selected)
	game.equip_button.disabled = not owned or bag_amount(item_id(selected)) <= 0 or (not usable and int(info.get("type", 0)) not in range(10, 22)) or not _action_ready()
	game.equip_button.text = "Use" if usable else "Equip"
	game.drop_button.disabled = not _action_ready() or bag_amount(item_id(selected)) <= 0 or int(info.get("special", 0)) == 4
	game.junk_button.disabled = not _action_ready() or bag_amount(item_id(selected)) <= 0
	drop_ui.refresh()
	game.paperdoll.refresh(selected)
	if game.paperdoll.information_labels.size() >= 2:
		game.paperdoll.information_labels[0].text = str(player.get("name", "Player"))
		game.paperdoll.information_labels[1].text = str(game.world.get("name", ""))
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
	var characters: Dictionary = game.manifest.get("characters", {}) as Dictionary
	var layered: Dictionary = characters.get("equipment_layers", {}) as Dictionary
	if int(layered.get("version", 0)) >= 2:
		var definitions: Dictionary = layered.get("layers", {}) as Dictionary
		var ranged: bool = false
		for graphic_id: Variant in layered.get("ranged_weapon_graphics", []):
			if int(graphic_id) == int(equipment_graphics[8]): ranged = true; break
		var female: String = "f:" if int(record.get("gender", 1)) == 0 else ""
		var race: int = clampi(int(record.get("race", 0)), 0, 6)
		var hairstyle: int = clampi(int(record.get("hairstyle", 1)), 0, 20)
		var color: int = clampi(int(record.get("haircolor", 0)), 0, 9)
		var skin_key: String = "skin:%s0" % female + (":%d" % race if race > 0 else "")
		var hair_key: String = "hair:%s0" % female + (":%d:%d" % [maxi(1, hairstyle), color] if [maxi(1, hairstyle), color] != [1, 0] else "")
		var head: Dictionary = definitions.get("head:%s%d" % [female, int(equipment_graphics[6])], {}) as Dictionary
		var hair: Dictionary = definitions.get(hair_key, {}) as Dictionary if hairstyle > 0 and str(head.get("mask_mode", "")) != "hide" else {}
		var head_parts: Array[Dictionary] = []
		if str(head.get("mask_mode", "")) == "face":
			if not head.is_empty(): head_parts.append(head)
			if not hair.is_empty(): head_parts.append(hair)
		else:
			if not hair.is_empty(): head_parts.append(hair)
			if not head.is_empty(): head_parts.append(head)
		var offhand: Dictionary = definitions.get("offhand:%s%d" % [female, int(equipment_graphics[7])], {}) as Dictionary
		var parts: Array[Dictionary] = []
		if not offhand.is_empty(): parts.append({"directional_offhand": offhand, "behind": true})
		for name: String in ["weapon_back", "skin", "boots", "armor"]:
			var graphic: int = int(equipment_graphics[8]) if name == "weapon_back" else int(equipment_graphics[4]) if name == "armor" else int(equipment_graphics[0]) if name == "boots" else 0
			if graphic == 0 and name != "skin": continue
			var key: String = skin_key if name == "skin" else "%s:%s%d" % [name, female, graphic]
			var part: Dictionary = definitions.get(key, {}) as Dictionary
			if not part.is_empty(): parts.append(part)
		if not head_parts.is_empty(): parts.append({"head_layers": head_parts, "clip_black": str(head.get("mask_mode", "")) == "standard"})
		var front: Dictionary = definitions.get("weapon_front:%s%d" % [female, int(equipment_graphics[8])], {}) as Dictionary
		if not front.is_empty(): parts.append(front)
		if not offhand.is_empty(): parts.append({"directional_offhand": offhand, "behind": false})
		if not parts.is_empty(): return {"layers": parts, "ranged": ranged, "appearance": {"armor_graphic": int(equipment_graphics[4]), "boots_graphic": int(equipment_graphics[0]), "weapon_graphic": int(equipment_graphics[8]), "head_graphic": int(equipment_graphics[6]), "offhand_graphic": int(equipment_graphics[7])}}
	if int(equipment_graphics[6]) != 0 or int(equipment_graphics[7]) != 0: return {}
	if int(equipment_graphics[0]) not in [0, 1] or int(equipment_graphics[4]) not in [0, 1]: return {}
	if int(equipment_graphics[8]) not in [0, 4]:
		var weapon_variants: Dictionary = characters.get("weapon_variants", {}) as Dictionary
		return weapon_variants.get("a%d_b%d_g%d" % [int(equipment_graphics[4]), int(equipment_graphics[0]), int(equipment_graphics[8])], {}) as Dictionary
	var key: String = "a%d_b%d_w%d" % [int(int(equipment_graphics[4]) == 1), int(int(equipment_graphics[0]) == 1), int(int(equipment_graphics[8]) == 4)]
	var variants: Dictionary = characters.get("hero_variants", {}) as Dictionary
	return variants.get(key, {}) as Dictionary

func _finish_potion(item: int) -> void:
	for request_id: Variant in pending_potion_requests:
		if int(pending_potion_requests[request_id]) == item:
			pending_potion_requests.erase(request_id)
			return

func npc_graphic(record: Dictionary) -> Dictionary:
	var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(record.get("id", 0))), {}) as Dictionary
	return (((game.manifest.get("characters", {}) as Dictionary).get("npcs", {}) as Dictionary).get(str(int(info.get("graphic", 0))), {})) as Dictionary

func npc_feedback_anchor(record: Dictionary, fallback: Vector2i) -> Vector2:
	var index: int = int(record.get("index", -1))
	var at: Vector2 = _remote_position("npc:%d" % index, game.tile_position(fallback))
	var layout: Dictionary = npc_name_layout(npc_graphic(record), _facing(record.get("direction", 0)), true)
	return at + (layout.head as Vector2) + Vector2(0, -28)

func draw_npc_combat_overlays() -> void:
	for record: Dictionary in npcs:
		var health: float = npc_health_fraction(int(record.index))
		if health < 0.0: continue
		var at: Vector2 = _remote_position("npc:%d" % int(record.index), game.tile_position(Vector2i(int(record.x), int(record.y))))
		var info: Dictionary = (catalog.get("npcs", {}) as Dictionary).get(str(int(record.id)), {}) as Dictionary
		var layout: Dictionary = npc_name_layout(npc_graphic(record), _facing(record.get("direction", 0)), true)
		var strip: Rect2 = layout.health as Rect2
		strip.position += at
		game.draw_rect(strip.grow(1), Color("121b18"))
		game.draw_rect(strip, Color("50322e"))
		game.draw_rect(Rect2(strip.position, Vector2(strip.size.x * health, strip.size.y)), Color("a6cb6f") if health > .3 else Color("dc6855"))
		var text: String = str(info.get("name", "NPC"))
		var font: Font = ThemeDB.fallback_font
		var origin: Vector2 = at + (layout.name as Vector2) - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x / 2, 0)
		game.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
		game.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, game.TEXT)

func npc_health_fraction(index: int) -> float:
	var health: Dictionary = npc_health.get(index, {}) as Dictionary
	if health.is_empty() or Time.get_ticks_msec() >= int(health.get("until", 0)): return -1.0
	return clampf(float(health.get("percent", 100)) / 100.0, 0.0, 1.0)

func _process_events(events: Array) -> void:
	for raw: Variant in events:
		if not raw is Dictionary: continue
		var event: Dictionary = raw as Dictionary
		game.skills_ui.event(event)
		game.party_ui.event(event)
		var kind: String = str(event.get("kind", event.get("type", event.get("event", ""))))
		game.map_effect_event(event)
		_action_sound(event, kind)
		if kind.begins_with("arena_"):
			game._toast(str(event.get("message", "")))
			game.chat_ui.receive({"channel":"system","name":"Arena","message":str(event.get("message", ""))})
		if kind == "inn_recovered": game._toast("Rested at the inn · HP and TP restored.")
		elif kind == "quest_hint": game._toast(str(event.get("message", "")))
		elif kind == "class_changed":
			var class_info: Dictionary = (catalog.get("classes", {}) as Dictionary).get(str(int(event.get("class_id", 0))), {}) as Dictionary
			game._toast("Your class is now %s." % str(class_info.get("name", "changed")))
		if kind in ["player_damage", "npc_attack"] and event.get("source", "") != "spike":
			npc_attack_until[int(event.get("npc_index", -1))] = Time.get_ticks_msec() / 1000.0 + 0.36
			for npc: Dictionary in npcs:
				if int(npc.index) == int(event.get("npc_index", -1)): npc.direction = int(event.get("direction", 0))
			if int(event.get("player_id", -1)) == int(player.get("player_id", -2)):
				var index: int = int(event.get("npc_index", -1))
				var health: Dictionary = npc_health.get(index, {"percent": 100}) as Dictionary
				health["until"] = Time.get_ticks_msec() + 8000
				npc_health[index] = health
		if kind == "peer_damage":
			var key: String = "player:" + str(int(event.get("player_id", -1)))
			var at: Vector2 = _remote_position(key, game.player_world)
			game.damage_numbers.append({"position":at + Vector2(0,-62),"value":"-%d" % int(event.get("damage",0)),"time":0.85})
		if kind == "peer_attack":
			var pid: int = int(event.get("player_id", -1))
			peer_attacks[pid] = {"until": Time.get_ticks_msec() / 1000.0 + game.ONLINE_ATTACK_SWING_DURATION, "direction": int(event.get("direction", 0))}
			for peer: Dictionary in players:
				if int(peer.get("player_id", -2)) == pid: peer.direction = int(event.get("direction", 0))
		if kind == "party_exp":
			game.damage_numbers.append({"position":game.player_world+Vector2(0,-106),"value":"+%d EXP" % int(event.get("exp_gain",0)),"time":1.2,"exp_gain":true})
			if event.has("level_up"): game._toast("Level %d reached!" % int(event.level_up))
		if kind == "player_damage":
			game.player_hit_flash = 0.22
			game.damage_numbers.append({"position": game.player_world + Vector2(0, -62), "value": "-%d" % int(event.get("damage", 0)) if int(event.get("damage", 0)) > 0 else "Miss", "time": 0.85, "player_hit": true})
			if bool(event.get("dead", false)):
				defeated = true
				game.skills_ui.cancel_cast()
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
			var tile: Vector2i = previous_npc_tiles.get(index, Vector2i(-1, -1)) as Vector2i
			for npc: Dictionary in npcs:
				if int(npc.index) == index: tile = Vector2i(int(npc.x), int(npc.y))
			if tile.x < 0 and event.has("x") and event.has("y"): tile = Vector2i(int(event.x), int(event.y))
			if tile.x < 0 and kind == "npc_killed":
				var dropped: Dictionary = event.get("drop", {}) as Dictionary
				if dropped.has("x") and dropped.has("y"): tile = Vector2i(int(dropped.x), int(dropped.y))
			var damage: int = int(event.get("damage", 0))
			if damage > 0: npc_hit_until[index] = Time.get_ticks_msec() + 150
			if tile.x >= 0:
				var record: Dictionary = {"id": int(event.get("npc_id", 0)), "index": index, "direction": int(event.get("npc_direction", 0))}
				for npc: Dictionary in npcs:
					if int(npc.index) == index: record = npc
				game.damage_numbers.append({"position": npc_feedback_anchor(record, tile), "value": str(damage) if damage > 0 else "Miss", "time": 0.8})
			if kind == "npc_killed":
				var drop: Dictionary = event.get("drop", {}) as Dictionary
				if int(drop.get("uid", 0)) > 0:
					drop_permissions[int(drop.uid)] = {"owner": int(event.get("player_id", 0)), "until": Time.get_ticks_msec() + 30000}
				if int(event.get("exp_gain", 0)) > 0:
					game.damage_numbers.append({"position": game.player_world + Vector2(0, -106), "value": "+%d EXP" % int(event.exp_gain), "time": 1.2, "exp_gain": true})
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
		if kind == "item_junk":
			game._toast("Junked %s ×%d." % [str(item_info("item:%d" % int(event.get("item_id", 0))).get("name", "Item")), int(event.get("amount", 0))])
		if kind == "item_use_failed":
			_finish_potion(int(event.get("item_id", 0)))
			game._toast(str(event.get("message", "The potion was not used.")))
		if kind == "npc_despawn":
			for index: Variant in event.get("indexes", []):
				npc_health.erase(int(index))
				npc_attack_until.erase(int(index))
				npc_hit_until.erase(int(index))
				if interaction.get("kind", "") == "npc" and int(interaction.get("id", -1)) == int(index): interaction.clear()
		game.drink_effects.event(event)
		if kind == "item_used":
			if int(event.get("item_type", 3)) == 3: _finish_potion(int(event.get("item_id", 0)))
			else: pending_item_use = false
			if int(event.get("consumed", 1)) > 0: game._toast("Used %s." % str(item_info("item:%d" % int(event.get("item_id", 0))).get("name", "item")))
			else: game._toast("HP/TP already restored. Potion kept.")
			if int(event.get("hp_gain", 0)) > 0: game.damage_numbers.append({"position": game.player_world + Vector2(0, -62), "value": "+%d" % int(event.hp_gain), "time": 0.85})
		if kind == "online_players": game.chat_ui.receive_roster(event)
		if kind == "chat":
			game.chat_ui.receive(event)
			show_speech(event)
		if kind in ["trade_sent", "trade_complete", "trade_cancelled"]: game._toast(str(event.get("message", "")))
		if kind == "pickup_failed":
			pickup_pending.erase(int(event.get("uid", 0)))
			game._toast(str(event.get("message", "The server refused this pickup.")))

func _action_sound(event: Dictionary, kind: String) -> void:
	if game.sfx == null: return
	if kind == "timed_spikes":
		for spec: Dictionary in game.world.get("tile_specs", []):
			if int(spec.spec) == 34 and game._distance(game.player_tile, Vector2i(int(spec.x), int(spec.y))) <= 6:
				game.sfx.play_named("Spikes", "map_spikes")
				break
		return
	if kind == "peer_attack":
		if int(event.get("player_id", -1)) == int(player.get("player_id", -2)): return
		for peer: Dictionary in players:
			if int(peer.get("player_id", -2)) == int(event.get("player_id", -1)):
				var graphics: Array = peer.get("equipment_graphics", []) as Array
				game.sfx.weapon(int(graphics[8]) if graphics.size() > 8 else 0)
	elif kind in ["player_damage", "npc_attack"]:
		game.sfx.play_named("Spikes" if event.get("source", "") == "spike" else "PunchAttack", "npc")
		if bool(event.get("dead", false)): game.sfx.play_named("Dead", "death")
	elif kind in ["equip", "unequip", "drop", "item_junk"]: game.sfx.play_named("InventoryPlace", "inventory")
	elif kind == "shop_transaction": game.sfx.play_named("Craft" if str(event.get("operation", "")) == "craft" else "BuySell", "shop")
	elif kind == "skill_changed" and event.get("action", "") in ["learned", "trained"]: game.sfx.play_named("LearnNewSpell" if event.get("action", "") == "learned" else "InventoryPickup", "training")
	elif kind == "seating" and int(event.get("sitting", 0)) != 0 and int(event.get("player_id", -1)) == int(player.get("player_id", -2)): game.sfx.play_named("Sit", "sit")
	elif kind == "door_open": game.sfx.play_named("DoorOpen", "door")
	elif kind == "door_locked": game.sfx.play_named("DoorOrChestLocked", "door")
	elif kind == "chat" and event.get("channel", "") == "private": game.sfx.play_named("PrivateMessageSent" if event.get("outgoing", false) else "PrivateMessageReceived", "whisper")
	elif kind == "arena_win": game.sfx.play_named("ArenaWin", "arena")
	elif kind == "arena_busy": game.sfx.play_named("ArenaTickSound", "arena")
	elif kind == "trade_complete": game.sfx.play_named("TradeAccepted", "trade")
	elif kind == "sound": game.sfx.play_id(int(event.get("sound_id", 0)), "server")
	elif kind == "potion_effect" or (kind == "item_used" and int(event.get("item_type", -1)) == 23): game.sfx.effect(int(event.get("effect_id", -1)) + 1)
	elif kind == "map_transition":
		var animation: int = int(event.get("animation", 0))
		if animation in [1, 2]: game.sfx.play_named("AdminWarp" if animation == 2 else "ScrollTeleport", "warp")
	var action: Variant = event.get("action", -1)
	var packet: Vector2i = Vector2i(int(event.get("family", -1)), int(action)) if action is int or action is float else Vector2i(-1, -1)
	if packet == Vector2i(33, 13): game.sfx.play_named("ChestOpen", "chest")
	elif packet == Vector2i(33, 14): game.sfx.play_named("DoorOrChestLocked", "chest")
	elif packet in [Vector2i(33, 27), Vector2i(37, 27)]: game.sfx.play_named("InventoryPickup", "storage")
	elif packet in [Vector2i(33, 3), Vector2i(37, 3)]: game.sfx.play_named("InventoryPlace", "storage")
	elif packet == Vector2i(36, 3): game.sfx.play_named("BuySell", "bank")
	if event.has("level_up"): game.sfx.play_named("LevelUp", "level")

func _slot_name(kind: String) -> String:
	return str({"hat": "head", "shield": "offhand"}.get(kind, kind))

func can_issue_walk() -> bool:
	return active and streaming and not defeated and not recovering and not transition_pending and not game.moving and game.attack_clock <= 0.0 and pending_inputs.size() < MAX_PREDICTIONS and not session.has_blocking_requests()

func _select_character_card(index: int) -> void:
	if index < 0 or index >= selected_characters.size(): return
	for i: int in range(character_cards.get_child_count()):
		var control: Button = character_cards.get_child(i) as Button
		var selected: bool = i == index
		var style: StyleBoxFlat = game._style(Color("173436") if selected else Color("0c2023"),game.GOLD if selected else Color("465e56"),16)
		style.set_border_width_all(3 if selected else 1)
		control.add_theme_stylebox_override("normal",style)
		control.add_theme_stylebox_override("hover",style)
		control.add_theme_stylebox_override("pressed",style)
		var label: Label = control.find_child("Selection",true,false) as Label
		if label != null: label.text = "Selected" if selected else "Tap to select"
	character_flow.refresh()

func log_out() -> void:
	session.close()
	_on_closed("Logged out.")
