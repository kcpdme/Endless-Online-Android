extends Node2D
## First playable local slice; EO networking is deliberately a separate milestone.

const OnlineController = preload("res://scripts/online_controller.gd")
const Joystick = preload("res://scripts/joystick.gd")
const ShopWindow = preload("res://scripts/shop_window.gd")
const ClassicPaperdoll = preload("res://scripts/classic_paperdoll.gd")
const HudIconButton = preload("res://scripts/hud_icon_button.gd")
const WeaponButton = preload("res://scripts/weapon_button.gd")
const WoodGrain = preload("res://scripts/wood_grain.gd")
const CharacterStats = preload("res://scripts/character_stats.gd")
const ONLINE_ATTACK_COOLDOWN: float = 0.52
const ATTACK_COOLDOWN: float = 0.90
const ATTACK_SWING_DURATION: float = 0.26
const ONLINE_ATTACK_SWING_DURATION: float = 0.48
const TURN_HOLD_SECONDS: float = 0.20 # Original InputHandlerBase's input interval.
const SAVE_PATH: String = "user://aster_vale_save.json"
const TILE: Vector2 = Vector2(64.0, 32.0)
const GOLD: Color = Color("e9bd71")
const INK: Color = Color("111e23")
const TEXT: Color = Color("eef1df")
const MUTED: Color = Color("aabbb2")
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

var online: OnlineController
var online_mode: bool = false
var hud_root: Control
var dagger_count: int = 0
var world: Dictionary = {}
var manifest: Dictionary = {}
var graphics: Dictionary = {}
var textures: Dictionary = {}
var ground: Dictionary = {}
var blocked: Dictionary = {}
var server_blocked: Dictionary = {}
var tile_specs: Dictionary = {}
var timed_spikes_until: int = 0
var decorations: Array[Dictionary] = []
var minimap: Control
var route: Array[Vector2i] = []
var hero: Dictionary = {}
var monster: Dictionary = {}
var joystick: Joystick
var shop_ui: ShopWindow
var paperdoll: ClassicPaperdoll
var stats_ui: CharacterStats
var player_hit_flash: float = 0.0
var character_panel: Control
var bag_button: HudIconButton
var character_button: HudIconButton
const AUTO_ATTACK_HOLD_MSEC: int = 600
const COMBAT_HUD_SHIFT: Vector2 = Vector2(-72, -36)
var auto_attack: bool = false
var attack_held_at: int = 0
var attack_hold_can_latch: bool = false
var attack_touch_id: int = -1
var owned_touches: Dictionary = {}
var hero_equipped: Dictionary = {}
var bag_slots: Array[Button] = []
var offline_bag_slots: Array[Button] = []
var bag_grid: Control
var bag_scroll: ScrollContainer
var offline_bag_panel: Control
var equipment_slots: Dictionary = {}
var selected_item: String = "weapon"
var item_title: Label
var inventory_summary: Label
var step_origin_tile: Vector2i = Vector2i.ZERO
var step_duration: float = 0.24
var touch_move_id: int = -1
var movement_keys: Array[int] = []
var turn_input: Vector2i = Vector2i.ZERO
var turn_wait: float = 0.0
var player_tile: Vector2i = Vector2i.ZERO
var player_world: Vector2 = Vector2.ZERO
var step_from: Vector2 = Vector2.ZERO
var step_to: Vector2 = Vector2.ZERO
var moving: bool = false
var step_progress: float = 0.0
var facing: String = "south"
var animation_clock: float = 0.0
var attack_clock: float = 0.0
var swing_clock: float = 0.0
var stick: Vector2 = Vector2.ZERO
var camera: Camera2D
var started: bool = false
var content_ready: bool = false
var kills: int = 0
var coins: int = 0
var has_blade: bool = false
var equipped: bool = false
var armor_equipped: bool = true
var boots_equipped: bool = true
var enemy_tile: Vector2i = Vector2i.ZERO
var enemy_health: int = 3
var enemy_respawn: float = 0.0
var loot_tile: Vector2i = Vector2i.ZERO
var loot_visible: bool = false
var time_alive: float = 0.0
var hit_flash: float = 0.0
var damage_numbers: Array[Dictionary] = []
var ui: CanvasLayer
var welcome: Control
var inventory: Control
var quest_hint: Label
var quest_label: Label
var chat_ui: RefCounted
var chat_button: Button
var drink_effects: RefCounted
var skills_ui: RefCounted
var services_ui: RefCounted
var coin_label: Label
var toast_label: Label
var location_label: Label
var health_label: Label
var junk_button: Button
var quick_items: RefCounted
var head_images: Dictionary = {}
var drop_button: Button
var bag_overflow: OptionButton
var equip_button: Button
var attack_button: WeaponButton
var toast_time: float = 0.0
var waypoint: Vector2i = Vector2i(-1, -1)
var modal_input_until: int = 0
var redeem_ui: RefCounted
var music: Node
var sfx: Node
var quest_journal: RefCounted
var quest_ui: RefCounted
var speech_layer: Control
var sit_button: Button
var movement_ui: RefCounted
var guild_ui: RefCounted
var party_ui: RefCounted
var inn_ui: RefCounted
var menu: Control
var started_from_save: bool = false
var debug_snapshot_time: float = -1.0

func _ready() -> void:
	# Android Back navigates within the game; desktop close requests retain normal quitting.
	get_tree().quit_on_go_back = false
	DisplayServer.window_set_min_size(Vector2i(960, 540))
	camera = Camera2D.new()
	camera.zoom = Vector2(1.65, 1.65)
	camera.position_smoothing_enabled = false
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	_load_content()
	music = preload("res://scripts/map_music.gd").new()
	add_child(music)
	music.configure(manifest.get("music", {}) as Dictionary)
	sfx = preload("res://scripts/game_sfx.gd").new()
	add_child(sfx)
	sfx.configure(self, manifest)
	online = OnlineController.new()
	online.game = self
	add_child(online)
	_build_ui()
	get_viewport().size_changed.connect(_layout_safe_area)
	_layout_safe_area()
	if content_ready:
		player_world = tile_position(player_tile)
		camera.position = player_world
		_place_enemy()
		_refresh_ui()
		_show_welcome()
	else:
		_show_content_error()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--play":
			_begin_play()
		if argument.begins_with("--screenshot-after="):
			debug_snapshot_time = float(argument.get_slice("=", 1))

func _load_content() -> void:
	if not FileAccess.file_exists("res://content/world.json") or not FileAccess.file_exists("res://content/manifest.json"):
		return
	var parsed_world: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/world.json"))
	var parsed_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/manifest.json"))
	if not parsed_world is Dictionary or not parsed_manifest is Dictionary:
		return
	manifest = parsed_manifest as Dictionary
	graphics = manifest.get("graphics", {}) as Dictionary
	var characters: Dictionary = manifest.get("characters", {}) as Dictionary
	hero = characters.get("hero", {}) as Dictionary
	monster = characters.get("monster", {}) as Dictionary
	hero_equipped = characters.get("hero_equipped", {}) as Dictionary
	_configure_world(parsed_world as Dictionary)
	var spawn: Array = world.get("spawn", [10, 10]) as Array
	player_tile = Vector2i(int(spawn[0]), int(spawn[1]))
	content_ready = not graphics.is_empty() and int(world.get("width", 0)) > 0

func map_path(map_id: int) -> String:
	if online != null:
		var maps: Dictionary = online.catalog.get("maps", {}) as Dictionary
		var info: Dictionary = maps.get(str(map_id), {}) as Dictionary
		if not str(info.get("path", "")).is_empty(): return str(info.path)
	var paths: Dictionary = manifest.get("map_paths", {}) as Dictionary
	if paths.has(str(map_id)): return str(paths[str(map_id)])
	if map_id == 5: return "res://content/world.json"
	return ""

func load_map(map_id: int) -> bool:
	if int(world.get("id", -1)) == map_id: return true
	var path: String = map_path(map_id)
	if path.is_empty() or not FileAccess.file_exists(path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return false
	var data: Dictionary = parsed as Dictionary
	if int(data.get("id", -1)) != map_id or int(data.get("width", 0)) <= 0: return false
	_cancel_controls()
	textures.clear()
	head_images.clear()
	_configure_world(data)
	if music != null: music.enter_map(world)
	if sfx != null: sfx.enter_map(world)
	damage_numbers.clear()
	queue_redraw()
	return true

func _configure_world(data: Dictionary) -> void:
	world = data
	ground.clear()
	blocked.clear()
	server_blocked.clear()
	tile_specs.clear()
	timed_spikes_until = 0
	decorations.clear()
	route.clear()
	waypoint = Vector2i(-1, -1)
	for cell: Array in world.get("blocked", []):
		blocked[Vector2i(int(cell[0]), int(cell[1]))] = true
	for cell: Array in world.get("server_blocked", world.get("blocked", [])):
		server_blocked[Vector2i(int(cell[0]), int(cell[1]))] = true
	for spec: Dictionary in world.get("tile_specs", []):
		var tile: Vector2i = Vector2i(int(spec.x), int(spec.y))
		tile_specs[tile] = int(spec.spec)
		# A chest's native tile spec is solid even if cached collision metadata
		# is incomplete. Artwork and touch bounds never define walkability.
		if int(spec.spec) == 9:
			blocked[tile] = true
			server_blocked[tile] = true
	var layers: Dictionary = world.get("layers", {}) as Dictionary
	for entry: Dictionary in layers.get("ground", []):
		ground[Vector2i(int(entry.x), int(entry.y))] = int(entry.id)
	var layer_gfx: Dictionary = manifest.get("layer_gfx", {"objects": 4, "overlay": 5, "walls_right": 6, "walls_down": 6, "wall_top": 3, "shadow": 22, "overlay2": 5, "roof": 7}) as Dictionary
	for layer: String in layer_gfx:
		if layer == "ground": continue
		for entry: Dictionary in layers.get(layer, []):
			if int(entry.id) <= 0: continue
			decorations.append({"tile": Vector2i(int(entry.x), int(entry.y)), "id": int(entry.id), "gfx": int(layer_gfx[layer]), "layer": layer})
	decorations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return depth(a.tile) < depth(b.tile))

func _texture(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var result: Texture2D = load(path) as Texture2D
	textures[path] = result
	return result

func _graphic(gfx: int, graphic_id: int) -> Texture2D:
	var key: String = "%d:%d" % [gfx, graphic_id]
	if not graphics.has(key):
		return null
	return _texture(str((graphics[key] as Dictionary).get("path", "")))

func tile_position(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0 + 16.0)

func depth(tile: Vector2i) -> int:
	return (tile.x + tile.y) * 1000 + tile.x

func _world_tile(point: Vector2) -> Vector2i:
	var p: Vector2 = point - Vector2(0, 16)
	return Vector2i(roundi(p.x / 64.0 + p.y / 32.0), roundi(p.y / 32.0 - p.x / 64.0))

func _walkable(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= int(world.get("width", 0)) or tile.y >= int(world.get("height", 0)): return false
	if online_mode: return not server_blocked.has(tile) and not online.npc_occupies(tile)
	return not blocked.has(tile) and int(ground.get(tile, int(world.get("fill_tile", 0)))) > 0

func _process(delta: float) -> void:
	if skills_ui != null: skills_ui.tick()
	if quick_items != null: quick_items.refresh()
	if online != null: online.shortcuts.tick()
	if chat_ui != null: chat_ui.tick()
	if guild_ui != null: guild_ui.tick()
	if party_ui != null: party_ui.tick()
	time_alive += delta
	animation_clock += delta
	var attack_previous: float = attack_clock
	var attack_remainder: float = maxf(0.0, delta - attack_clock)
	attack_clock = maxf(0.0, attack_clock - delta)
	swing_clock = maxf(0.0, swing_clock - delta)
	if attack_button != null: attack_button.cooldown_fraction = attack_clock / (ONLINE_ATTACK_COOLDOWN if online_mode else ATTACK_COOLDOWN)
	hit_flash = maxf(0.0, hit_flash - delta)
	player_hit_flash = maxf(0.0, player_hit_flash - delta)
	if stats_ui != null:
		stats_ui.vitals.visible = online_mode and online.active and started and not _modal_open() and not welcome.visible
	if debug_snapshot_time > 0.0 and time_alive > debug_snapshot_time:
		debug_snapshot_time = -1.0
		var snapshot: Image = get_viewport().get_texture().get_image()
		snapshot.save_png("user://prototype-screenshot.png")
		print("Screenshot saved: ", ProjectSettings.globalize_path("user://prototype-screenshot.png"))
	if stats_ui != null: stats_ui.process_repeat(delta)
	if toast_time > 0.0:
		toast_time = maxf(0.0, toast_time - delta)
		toast_label.visible = toast_time > 0.0
		toast_label.modulate.a = minf(1.0, toast_time / 0.2)
	if joystick != null: joystick.visible = started and not _modal_open() and not welcome.visible
	if sit_button != null: sit_button.visible = started and online_mode and online.active and not _modal_open() and not welcome.visible
	if not started:
		queue_redraw()
		return
	if not online_mode and enemy_health <= 0 and not loot_visible:
		enemy_respawn -= delta
		if enemy_respawn <= 0.0:
			enemy_health = 3
			_place_enemy()
	var walk_remainder: float = -1.0
	var walk_phase: float = animation_clock
	var was_walking: bool = moving
	turn_wait = maxf(0.0, turn_wait - delta)
	if _input_direction() == Vector2i.ZERO: _reset_turn_input()
	if moving:
		var remaining: float = (1.0 - step_progress) * step_duration
		_advance_walk(delta)
		if not moving: walk_remainder = maxf(0.0, delta - remaining)
	if not _modal_open():
		if attack_touch_id != -1 and attack_hold_can_latch and Time.get_ticks_msec() - attack_held_at >= AUTO_ATTACK_HOLD_MSEC:
			auto_attack = true
			attack_hold_can_latch = false
			attack_button.automatic = true
			_toast("Auto attack on · tap weapon for manual")
		if (attack_touch_id != -1 or auto_attack) and attack_clock <= 0.0 and (enemy_health > 0 or online_mode) and (not online_mode or (_input_direction() == Vector2i.ZERO and route.is_empty())):
			_attack()
			if attack_clock > 0.0 and attack_previous > 0.0: attack_clock = maxf(0.0, attack_clock - attack_remainder)
		if not moving:
			var direction: Vector2i = _input_direction()
			if direction != Vector2i.ZERO:
				route.clear()
				waypoint = Vector2i(-1, -1)
				_manual_step(direction, was_walking)
			elif not route.is_empty() and (not online_mode or online.can_issue_walk()):
				var next_tile: Vector2i = route.pop_front()
				_step(next_tile - player_tile)
	# Chain held/path movement on the same frame, carrying the unused time.
	# Discarding it inserts a stationary frame at every tile boundary.
	if moving and walk_remainder >= 0.0:
		animation_clock = walk_phase
		_advance_walk(minf(walk_remainder, step_duration))
	elif moving and not was_walking:
		# Respond on the first input frame, including a very short tap.
		animation_clock += delta
		_advance_walk(minf(delta, step_duration))
	camera.position = player_world
	for i: int in range(damage_numbers.size() - 1, -1, -1):
		var number: Dictionary = damage_numbers[i]
		number.time = float(number.time) - delta
		if float(number.time) <= 0.0:
			damage_numbers.remove_at(i)
	queue_redraw()

func _advance_walk(delta: float) -> void:
	step_progress = minf(1.0, step_progress + delta / step_duration)
	if step_progress >= 1.0 - 0.000001: step_progress = 1.0
	player_world = step_from.lerp(step_to, step_progress)
	if step_progress >= 1.0:
		moving = false
		_collect_loot()
		_save_progress()

func _movement_key(event: InputEventKey) -> int:
	for key: int in [int(event.physical_keycode), int(event.keycode)]:
		if key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]: return key
	return 0

func _editing_text() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func _input_direction() -> Vector2i:
	if _editing_text() or (chat_ui != null and chat_ui.typing()): return Vector2i.ZERO
	if not movement_keys.is_empty():
		match movement_keys.back():
			KEY_W, KEY_UP: return Vector2i.UP
			KEY_S, KEY_DOWN: return Vector2i.DOWN
			KEY_A, KEY_LEFT: return Vector2i.LEFT
			KEY_D, KEY_RIGHT: return Vector2i.RIGHT
	return _screen_direction(stick)

func _screen_direction(input: Vector2) -> Vector2i:
	if input.length_squared() < 0.035: return Vector2i.ZERO
	# Original EO moves on four tile axes. Never alternate two axes for a key.
	if absf(input.x) > absf(input.y): return Vector2i.RIGHT if input.x > 0 else Vector2i.LEFT
	return Vector2i.DOWN if input.y > 0 else Vector2i.UP

func _can_step(origin: Vector2i, direction: Vector2i) -> bool:
	if not _walkable(origin + direction): return false
	if direction.x != 0 and direction.y != 0:
		return _walkable(origin + Vector2i(direction.x, 0)) and _walkable(origin + Vector2i(0, direction.y))
	return true

func _reset_turn_input() -> void:
	turn_input = Vector2i.ZERO
	turn_wait = 0.0

func _manual_step(direction: Vector2i, continuing_walk: bool) -> void:
	if online_mode and online.seated():
		online.toggle_sit()
		return
	# Drag intent should issue its step on this frame. A separate desktop Face
	# would add both a client hold and another action to the native queue.
	if movement_keys.is_empty() and touch_move_id != -1:
		_reset_turn_input()
		_step(direction)
		return
	var desired: String = _direction_name(direction)
	# Original ArrowKeyController.FaceOrAttemptWalk: a stationary character
	# turns first. Changes at a walking tile boundary continue without a pause.
	if not continuing_walk and facing != desired:
		if online_mode: online.request_face(desired)
		else: facing = desired
		if facing == desired:
			turn_input = direction
			turn_wait = TURN_HOLD_SECONDS
		return
	if not continuing_walk and turn_input == direction and turn_wait > 0.000001: return
	_reset_turn_input()
	_step(direction)

func _step(direction: Vector2i) -> void:
	if online_mode:
		online.request_step(direction)
		return
	if direction == Vector2i.ZERO: return
	facing = _direction_name(direction)
	var target: Vector2i = player_tile + direction
	if not _can_step(player_tile, direction):
		route.clear()
		return
	step_origin_tile = player_tile
	step_from = player_world
	step_to = tile_position(target)
	step_duration = maxf(0.10, step_from.distance_to(step_to) / 150.0)
	player_tile = target
	step_progress = 0.0
	moving = true

func _cancel_movement(force_stop: bool = false) -> void:
	movement_keys.clear()
	stick = Vector2.ZERO
	_reset_turn_input()
	touch_move_id = -1
	route.clear()
	waypoint = Vector2i(-1, -1)
	if moving and (not online_mode or force_stop):
		# Stop at the exact rendered point. Only the logical/save tile selects the nearest endpoint.
		if step_progress < 0.5 and not online_mode: player_tile = step_origin_tile
		moving = false
		step_progress = 0.0
		if content_ready and started: _save_progress()
	if joystick != null: joystick.reset()

func _joystick_zone() -> Rect2:
	return joystick.activation_area()

func _joystick_begin(pointer: Vector2, pointer_id: int) -> void:
	_cancel_movement()
	touch_move_id = pointer_id
	joystick.begin(pointer)
	stick = Vector2(joystick.direction)

func _modal_open() -> bool:
	return (quest_journal != null and quest_journal.panel.visible) or (party_ui != null and party_ui.panel.visible) or (skills_ui != null and (skills_ui.target_panel.visible or skills_ui.bard_panel.visible)) or (movement_ui != null and movement_ui.panel.visible) or (guild_ui != null and guild_ui.panel.visible) or (inn_ui != null and inn_ui.panel.visible) or (quest_ui != null and quest_ui.panel.visible) or (redeem_ui != null and redeem_ui.panel.visible) or (online != null and online.panel != null and online.panel.visible) or (inventory != null and inventory.visible) or (menu != null and menu.visible) or (character_panel != null and character_panel.visible) or (stats_ui != null and stats_ui.is_open()) or (shop_ui != null and shop_ui.panel.visible) or (services_ui != null and services_ui.panel.visible) or (chat_ui != null and chat_ui.panel.visible) or (skills_ui != null and skills_ui.panel.visible) or (quick_items != null and quick_items.panel.visible)

func _begin_attack(pointer_id: int) -> void:
	if online_mode: route.clear()
	# A press while latched returns to manual and cannot immediately re-latch.
	attack_hold_can_latch = not auto_attack
	auto_attack = false
	attack_button.automatic = false
	attack_held_at = Time.get_ticks_msec()
	if enemy_health > 0 or online_mode:
		attack_touch_id = pointer_id
		attack_button.holding = true
	_attack()

func _end_attack_gesture() -> void:
	attack_touch_id = -1
	attack_hold_can_latch = false
	if attack_button != null: attack_button.holding = auto_attack

func _release_attack() -> void:
	auto_attack = false
	_end_attack_gesture()
	if attack_button != null: attack_button.automatic = false

func _cancel_controls(force_stop: bool = false) -> void:
	_release_attack()
	_cancel_movement(force_stop)


func _direction_name(direction: Vector2i) -> String:
	if direction.x > 0: return "east"
	if direction.x < 0: return "west"
	if direction.y < 0: return "north"
	return "south"

func _screen_to_world(point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * point

func _input(event: InputEvent) -> void:
	var dismissing_modal: bool = Time.get_ticks_msec() < modal_input_until
	if event is InputEventKey:
		if event.keycode == KEY_F11 and event.pressed and not event.echo and started and online_mode and not _modal_open() and not _editing_text():
			online.toggle_sit()
			get_viewport().set_input_as_handled()
			return
		var key: int = _movement_key(event)
		if key != 0:
			var gameplay_key: bool = started and not _modal_open() and not _editing_text() and not (chat_ui != null and chat_ui.typing())
			if not event.pressed:
				movement_keys.erase(key)
				if _input_direction() == Vector2i.ZERO: _reset_turn_input()
			elif not event.echo and gameplay_key:
				movement_keys.erase(key)
				movement_keys.append(key)
				route.clear()
				waypoint = Vector2i(-1, -1)
			# Held arrow repeats must not navigate or open a focused HUD widget.
			if gameplay_key: get_viewport().set_input_as_handled()
			return
	# The joystick activation area owns presses before chat/world/NPC hit tests.
	var pad_press: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if pad_press and started and not dismissing_modal and not _modal_open() and joystick.contains_point(event.position):
		if not (event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION):
			if chat_ui != null: chat_ui.blur_quick()
			var pointer: int = event.index if event is InputEventScreenTouch else -2
			if event is InputEventScreenTouch: owned_touches[pointer] = true
			if touch_move_id == -1: _joystick_begin(event.position, pointer)
		get_viewport().set_input_as_handled()
		return
	# Standard GUI owns the feed/composer outside the movement area.
	var owned_chat_release: bool = (event is InputEventScreenTouch and not event.pressed and owned_touches.has(event.index)) or (event is InputEventMouseButton and not event.pressed and (touch_move_id == -2 or attack_touch_id == -2))
	if chat_ui != null and not dismissing_modal and not _modal_open() and not owned_chat_release:
		if chat_ui.quick_channel.get_popup().visible: return
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if chat_ui.hud_contains(event.position): return
			if chat_ui.typing() and event.pressed:
				chat_ui.blur_quick()
				get_viewport().set_input_as_handled()
				return
	# Own native controls suppress their separately generated mouse events, including
	# HUD presses that open a modal. A release can never become a second action.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		if started and not _modal_open() and minimap != null and minimap.contains(event.position):
			get_viewport().set_input_as_handled()
			return
		var native_control: bool = started and not _modal_open() and ((skills_ui != null and skills_ui.contains(event.position) >= 0) or (quick_items != null and quick_items.contains(event.position) >= 0) or attack_button.contains_point(event.position) or bag_button.contains_point(event.position) or sit_button.contains_point(event.position) or chat_button.contains_point(event.position) or quest_journal.button.contains_point(event.position) or character_button.contains_point(event.position) or joystick.contains_point(event.position) or (online_mode and (skills_ui.armed > 0 or not online.map_entity_target(_screen_to_world(event.position)).is_empty())) or (online_mode and online.loot_button.visible and online.loot_button.get_global_rect().has_point(event.position)))
		# Godot may synthesize the mouse press before delivering its native touch.
		if dismissing_modal or native_control or not owned_touches.is_empty():
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch and not event.pressed:
		var owned: bool = owned_touches.has(event.index)
		if quick_items != null: quick_items.release(event.index)
		if event.index == attack_touch_id: _end_attack_gesture()
		if event.index == touch_move_id: _cancel_movement()
		if owned:
			owned_touches.erase(event.index)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if quick_items != null: quick_items.release(-2)
		if attack_touch_id == -2:
			_end_attack_gesture()
			get_viewport().set_input_as_handled()
			return
		if touch_move_id == -2:
			_cancel_movement()
			get_viewport().set_input_as_handled()
			return
	# A modal dismissal can precede the native half of the same Android tap.
	# Finish owned releases above, then absorb that leftover gesture.
	if dismissing_modal and (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
		return
	if not started or _modal_open(): return
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed and minimap != null and minimap.contains(event.position):
		if event is InputEventScreenTouch: owned_touches[event.index] = true
		minimap.press(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and event.pressed:
		var item_slot: int = quick_items.contains(event.position) if quick_items != null else -1
		if item_slot >= 0:
			owned_touches[event.index] = true
			quick_items.begin(item_slot, event.index)
			get_viewport().set_input_as_handled()
			return
		var skill_slot: int = skills_ui.contains(event.position) if skills_ui != null else -1
		if skill_slot >= 0:
			owned_touches[event.index] = true
			skills_ui.press(skill_slot)
			get_viewport().set_input_as_handled()
			return
		if online_mode and online.loot_button.visible and online.loot_button.get_global_rect().has_point(event.position):
			owned_touches[event.index] = true
			online.request_collect()
			get_viewport().set_input_as_handled()
			return
		if attack_button.contains_point(event.position):
			owned_touches[event.index] = true
			if attack_touch_id == -1: _begin_attack(event.index)
			get_viewport().set_input_as_handled()
			return
		if sit_button.visible and sit_button.contains_point(event.position):
			owned_touches[event.index] = true
			if online_mode: online.toggle_sit()
			get_viewport().set_input_as_handled()
			return
		if bag_button.contains_point(event.position):
			owned_touches[event.index] = true
			_toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		if quest_journal.button.contains_point(event.position):
			owned_touches[event.index] = true
			quest_journal.open()
			get_viewport().set_input_as_handled()
			return
		if chat_button.contains_point(event.position):
			owned_touches[event.index] = true
			chat_ui.open()
			get_viewport().set_input_as_handled()
			return
		if character_button.contains_point(event.position):
			owned_touches[event.index] = true
			_toggle_paperdoll()
			get_viewport().set_input_as_handled()
			return
		# Outside the movement area, an armed spell or visible NPC owns world targeting.
		if online_mode and (skills_ui.armed > 0 or touch_move_id == -1) and online.map_press(_screen_to_world(event.position), true):
			owned_touches[event.index] = true
			get_viewport().set_input_as_handled()
			return
		if touch_move_id != -1:
			owned_touches[event.index] = true
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenDrag:
		if event.index == attack_touch_id:
			if not attack_button.contains_point(event.position): _release_attack()
		elif event.index == touch_move_id:
			stick = joystick.update_pointer(event.position)
			if stick == Vector2.ZERO: _reset_turn_input()
		if owned_touches.has(event.index):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var item_slot: int = quick_items.contains(event.position) if quick_items != null else -1
		if item_slot >= 0:
			quick_items.begin(item_slot, -2)
			get_viewport().set_input_as_handled()
			return
		var skill_slot: int = skills_ui.contains(event.position) if skills_ui != null else -1
		if skill_slot >= 0:
			skills_ui.press(skill_slot)
			get_viewport().set_input_as_handled()
			return
		if sit_button.visible and sit_button.contains_point(event.position):
			if online_mode: online.toggle_sit()
			get_viewport().set_input_as_handled()
			return
		if attack_button.contains_point(event.position):
			_begin_attack(-2)
			get_viewport().set_input_as_handled()
			return
		if online_mode and (skills_ui.armed > 0 or touch_move_id == -1) and online.map_press(_screen_to_world(event.position), true):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if attack_touch_id == -2 and not attack_button.contains_point(event.position): _release_attack()
		if touch_move_id == -2:
			stick = joystick.update_pointer(event.position)
			if stick == Vector2.ZERO: _reset_turn_input()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if chat_ui != null and chat_ui.typing():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: chat_ui.blur_quick()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_handle_back()
		if not started: return
		if event.keycode == KEY_ENTER and online_mode and not _modal_open():
			chat_ui.quick_entry.grab_focus()
			return
		if event.keycode == KEY_SPACE: _attack()
		if event.keycode == KEY_I: _toggle_inventory()
		if event.keycode == KEY_C: _toggle_paperdoll()
		if event.keycode == KEY_E: _collect_loot(true)
	if not started or _modal_open() or touch_move_id != -1:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked: Vector2i = _world_tile(get_global_mouse_position())
		if online_mode:
			online.map_press(get_global_mouse_position())
			return
		if loot_visible and clicked == loot_tile:
			if _distance(player_tile, loot_tile) <= 1: _collect_loot(true)
			else: _request_path(loot_tile)
		elif enemy_health > 0 and _distance(clicked, enemy_tile) <= 1 and _distance(player_tile, enemy_tile) <= 1:
			_attack()
		else:
			_request_path(clicked)
	if event is InputEventMagnifyGesture:
		camera.zoom = (camera.zoom * event.factor).clamp(Vector2(1.0, 1.0), Vector2(2.5, 2.5))

func _request_path(target: Vector2i) -> void:
	if not _walkable(target):
		_toast("That way is blocked. Tap a clear tile.")
		return
	# Breadth-first search is bounded to this small imported map; no diagonal corner cutting.
	var frontier: Array[Vector2i] = [player_tile]
	var came_from: Dictionary = {player_tile: player_tile}
	var index: int = 0
	while index < frontier.size() and index < 15000:
		var current: Vector2i = frontier[index]
		index += 1
		if current == target: break
		for direction: Vector2i in DIRECTIONS:
			var next_tile: Vector2i = current + direction
			if _walkable(next_tile) and not came_from.has(next_tile):
				came_from[next_tile] = current
				frontier.append(next_tile)
	if not came_from.has(target):
		_toast("No clear path to that tile.")
		return
	route.clear()
	var cursor: Vector2i = target
	while cursor != player_tile:
		route.push_front(cursor)
		cursor = came_from[cursor] as Vector2i
	waypoint = target

func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _place_enemy() -> void:
	var candidates: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(1, 0), Vector2i(0, 1)]
	for offset: Vector2i in candidates:
		if _walkable(player_tile + offset):
			enemy_tile = player_tile + offset
			return
	enemy_tile = player_tile

func _attack() -> void:
	if online_mode:
		if online.active and started and not _modal_open() and attack_clock <= 0.0:
			if not online.request_attack(): return
			attack_clock = ONLINE_ATTACK_COOLDOWN
			swing_clock = ONLINE_ATTACK_SWING_DURATION
			animation_clock = 0.0
			_play_sound("attack")
		return
	if not started or _modal_open():
		return
	if enemy_health <= 0:
		_collect_loot(true)
		return
	if attack_clock > 0.0: return
	attack_clock = ATTACK_COOLDOWN
	swing_clock = ATTACK_SWING_DURATION
	animation_clock = 0.0
	_play_sound("attack")
	if _distance(player_tile, enemy_tile) > 1:
		_toast("Get closer to the training slime, then strike.")
		return
	facing = _direction_name(enemy_tile - player_tile)
	var damage: int = 2 if equipped else 1
	enemy_health = maxi(0, enemy_health - damage)
	hit_flash = 0.18
	damage_numbers.append({"position": tile_position(enemy_tile) + Vector2(0, -44), "value": str(damage), "time": 0.8})
	if enemy_health == 0:
		kills += 1
		loot_visible = true
		loot_tile = enemy_tile
		enemy_respawn = 6.0
	_refresh_ui()
	_save_progress()

func _collect_loot(force: bool = false) -> void:
	if online_mode:
		if force: online.request_collect()
		else: online.collect_nearby()
		return
	if not loot_visible or _distance(player_tile, loot_tile) > (1 if force else 0):
		return
	loot_visible = false
	_play_sound("pickup")
	coins += 5
	dagger_count = maxi(dagger_count, 1 if has_blade else 0) + 1
	has_blade = true
	_toast("Collected a Dagger + 5 coins. Daggers owned: %d." % dagger_count)
	_refresh_ui()
	_save_progress()

func _visible_tile_bounds(rect: Rect2, width: int, height: int) -> Rect2i:
	# Invert the four viewport corners, then conservatively pad for rounding.
	# Keep the final screen-space cull, so tile order and coverage are unchanged.
	var first: Vector2i = _world_tile(rect.position)
	var low: Vector2i = first
	var high: Vector2i = first
	for corner: Vector2 in [rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y)]:
		var tile: Vector2i = _world_tile(corner)
		low = Vector2i(mini(low.x, tile.x), mini(low.y, tile.y))
		high = Vector2i(maxi(high.x, tile.x), maxi(high.y, tile.y))
	var start: Vector2i = Vector2i(clampi(low.x - 1, 0, width), clampi(low.y - 1, 0, height))
	var finish: Vector2i = Vector2i(clampi(high.x + 2, 0, width), clampi(high.y + 2, 0, height))
	return Rect2i(start, finish - start)

func _draw() -> void:
	if not content_ready: return
	var half_view: Vector2 = get_viewport_rect().size / camera.zoom / 2.0 + Vector2(160, 240)
	var visible_rect: Rect2 = Rect2(camera.position - half_view, half_view * 2.0)
	var width: int = int(world.get("width", 0))
	var height: int = int(world.get("height", 0))
	var fill_id: int = int(world.get("fill_tile", 0))
	var tile_bounds: Rect2i = _visible_tile_bounds(visible_rect, width, height)
	for y: int in range(tile_bounds.position.y, tile_bounds.end.y):
		for x: int in range(tile_bounds.position.x, tile_bounds.end.x):
			var tile: Vector2i = Vector2i(x, y)
			var position: Vector2 = tile_position(tile)
			if not visible_rect.has_point(position): continue
			var graphic_id: int = int(ground.get(tile, fill_id))
			if graphic_id > 0:
				var texture: Texture2D = _graphic(3, graphic_id)
				if texture != null:
					var frame_width: float = float(texture.get_width()) / 4.0 if texture.get_width() >= 128 else float(texture.get_width())
					var frame_index: int = int(time_alive * 4.0) % 4 if texture.get_width() >= 128 else 0
					draw_texture_rect_region(texture, Rect2(position - Vector2(32, 16), Vector2(frame_width, texture.get_height())), Rect2(Vector2(frame_index * frame_width, 0), Vector2(frame_width, texture.get_height())))
	if started and waypoint.x >= 0 and not route.is_empty():
		_draw_diamond(tile_position(waypoint), Color(0.92, 0.75, 0.44, 0.6))
	if online_mode: skills_ui.draw_area()
	var entities: Array[Dictionary] = []
	for decoration: Dictionary in decorations:
		var at: Vector2 = tile_position(decoration.tile)
		if not visible_rect.has_point(at): continue
		if str(decoration.layer) == "overlay2": continue
		var sort_tile: Vector2i = decoration.tile as Vector2i
		if str(decoration.layer) == "roof" and sort_tile.y + 1 < height: sort_tile.y += 1
		entities.append({"kind": "decoration", "data": decoration, "sort": depth(sort_tile) * 100 + _layer_rank(str(decoration.layer))})
	entities.append({"kind": "player", "sort": depth(_world_tile(player_world)) * 100 + 30})
	if online_mode:
		entities.append_array(online.entities())
	if not online_mode and enemy_health > 0: entities.append({"kind": "enemy", "sort": depth(enemy_tile) * 100 + 70})
	if not online_mode and loot_visible: entities.append({"kind": "loot", "sort": depth(loot_tile) * 100 + 0})
	entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sort) < int(b.sort))
	for entity: Dictionary in entities:
		match str(entity.kind):
			"decoration": _draw_decoration(entity.data as Dictionary)
			"player": _draw_player()
			"enemy": _draw_enemy()
			"loot": _draw_loot()
			"online_player", "online_npc", "online_item": online.draw_entity(entity)
	if online_mode: skills_ui.draw_orphans()
	for decoration: Dictionary in decorations:
		if str(decoration.layer) == "overlay2" and visible_rect.has_point(tile_position(decoration.tile)): _draw_decoration(decoration)
	if online_mode: online.draw_npc_combat_overlays()
	for number: Dictionary in damage_numbers:
		var at: Vector2 = number.position as Vector2
		at.y -= (0.8 - float(number.time)) * 28.0
		var caption: String = str(number.value)
		var font: Font = ThemeDB.fallback_font
		var origin: Vector2 = at - Vector2(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x / 2.0, 0)
		var color: Color = Color("ffaaaa") if bool(number.get("player_hit", false)) else MUTED if caption == "Miss" else Color("a4edb0") if bool(number.get("exp_gain", false)) else GOLD
		draw_string_outline(font, origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, Color.BLACK)
		draw_string(font, origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
	# Spell shouts draw above world/combat; speech has its own HUD overlay.
	if online_mode:
		online.draw_chat_bubbles()
		drink_effects.draw()

func _draw_diamond(center: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([center + Vector2(0, -15), center + Vector2(30, 0), center + Vector2(0, 15), center + Vector2(-30, 0), center + Vector2(0, -15)])
	draw_polyline(points, color, 1.4, true)

func _draw_decoration(entry: Dictionary) -> void:
	if not _decoration_visible(entry): return
	var texture: Texture2D = _graphic(int(entry.gfx), int(entry.id))
	if texture == null: return
	var at: Vector2 = tile_position(entry.tile)
	var size: Vector2 = texture.get_size()
	var color: Color = Color.WHITE
	var layer: String = str(entry.layer)
	var animated: bool = (int(entry.gfx) == 3 and size.x >= 128) or (int(entry.gfx) == 6 and size.x > 68)
	var frame_index: int = int(time_alive * 4.0) % 4 if animated else 0
	if animated: size.x /= 4.0
	var offset: Vector2 = Vector2(-2.0 - size.x / 2.0, 14.0 - size.y)
	if layer == "walls_down": offset = Vector2(-32.0, 15.0 - size.y)
	if layer == "walls_right": offset = Vector2(0.0, 15.0 - size.y)
	if layer == "roof": offset = Vector2(-32.0, -80.0)
	if layer == "wall_top": offset = Vector2(-32.0, -48.0)
	if layer == "shadow":
		offset = Vector2(-56.0, -28.0)
		color.a = 0.20
	draw_texture_rect_region(texture, Rect2(at + offset, size), Rect2(Vector2(frame_index * size.x, 0), size), color)

func _decoration_visible(entry: Dictionary) -> bool:
	if str(entry.layer) != "objects": return true
	var tile: Vector2i = entry.tile as Vector2i
	match int(tile_specs.get(tile, -1)):
		34: # Original timed spikes are raised for one second after native Effect_Report.
			return Time.get_ticks_msec() < timed_spikes_until
		36: # Trap spikes follow the occupied tile, including a walking destination.
			if started and player_tile == tile: return true
			if online_mode:
				for peer: Dictionary in online.players:
					if Vector2i(int(peer.x), int(peer.y)) == tile: return true
			return false
	return true

func map_effect_event(event: Dictionary) -> void:
	var kind: String = str(event.get("kind", ""))
	if kind == "map_transition": timed_spikes_until = 0
	elif kind == "timed_spikes": timed_spikes_until = Time.get_ticks_msec() + 1000
	elif kind == "player_damage" and str(event.get("source", "")) == "spike":
		var tile: Vector2i = Vector2i(int(online.player.get("x", -1)), int(online.player.get("y", -1)))
		if int(tile_specs.get(tile, -1)) == 34: timed_spikes_until = Time.get_ticks_msec() + 1000

func _frame(character: Dictionary, direction: String, state: String, phase: float = -1.0) -> Dictionary:
	if state in ["sit_chair", "sit_floor"] and str(character.get("component", "")).begins_with("weapon"): return {}
	if state == "attack" and bool(character.get("ranged", false)): state = "ranged_attack"
	if character.has("directional_offhand"):
		var offhand: Dictionary = character.directional_offhand
		var behind: bool = bool(offhand.get("on_back", false)) and direction in ["south", "east"]
		return _frame(offhand, direction, state, phase) if behind == bool(character.behind) else {}
	if character.has("head_layers"):
		var frames: Array[Dictionary] = []
		for layer: Dictionary in character.head_layers:
			frames.append(_frame(layer, direction, state, phase))
		var key: String = "head://" + JSON.stringify(frames) + str(character.clip_black)
		if not textures.has(key):
			var result: Image = Image.create(192, 192, false, Image.FORMAT_RGBA8)
			for frame: Dictionary in frames:
				var path: String = str(frame.path)
				if not head_images.has(path): head_images[path] = _texture(path).get_image()
				var r: Array = frame.region
				result.blend_rect(head_images[path] as Image, Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])), Vector2i.ZERO)
			if bool(character.clip_black):
				var bytes: PackedByteArray = result.get_data()
				for index: int in range(0, bytes.size(), 4):
					if bytes[index] == 0 and bytes[index + 1] == 0 and bytes[index + 2] == 0: bytes[index + 3] = 0
				result = Image.create_from_data(192, 192, false, Image.FORMAT_RGBA8, bytes)
			textures[key] = ImageTexture.create_from_image(result)
		return {"path": key, "region": [0, 0, 192, 192], "offset": [0, 8]}
	if character.has("layers"):
		var layers: Array[Dictionary] = []
		for layer: Dictionary in character.layers:
			var part: Dictionary = _frame(layer, direction, state, phase)
			if not part.is_empty(): layers.append(part)
		if layers.is_empty(): return {}
		var composed: Dictionary = layers[0].duplicate()
		composed["layers"] = layers
		return composed
	var group: Dictionary = character.get(state, character.get("frames", {})) as Dictionary
	var raw: Variant = group.get(direction, group.get("south", []))
	if raw is Dictionary: return raw as Dictionary
	if raw is Array and not (raw as Array).is_empty():
		var frames: Array = raw as Array
		var frame_rate: float = frames.size() / online.MOVE_SECONDS if online_mode and state == "frames" else 9.0
		var frame_index: int = int((phase if phase >= 0.0 else animation_clock) * frame_rate) % frames.size() if phase >= 0.0 or (moving and state != "idle") or bool(character.get("animate_idle", false)) else 0
		if state in ["attack", "ranged_attack"]:
			if online_mode: frame_index = mini(int((phase if phase >= 0.0 else ONLINE_ATTACK_SWING_DURATION - swing_clock) / (0.24 if frames.size() == 2 else 0.12)), frames.size() - 1)
			else: frame_index = mini(int((phase / 0.36 if phase >= 0.0 else 1.0 - swing_clock / ATTACK_SWING_DURATION) * frames.size()), frames.size() - 1)
		return frames[frame_index] as Dictionary
	return {}

func _draw_character_frame(character: Dictionary, at: Vector2, direction: String, state: String, tint: Color = Color.WHITE, phase: float = -1.0) -> bool:
	var frame: Dictionary = _frame(character, direction, state, phase)
	if frame.is_empty(): return false
	if frame.has("layers"):
		for layer: Dictionary in frame.layers: _paint_character_frame(layer, at, tint)
		return true
	return _paint_character_frame(frame, at, tint)

func _paint_character_frame(frame: Dictionary, at: Vector2, tint: Color) -> bool:
	var texture: Texture2D = _texture(str(frame.get("path", "")))
	if texture == null: return false
	var dimensions: Array = frame.get("region", [0, 0, texture.get_width(), texture.get_height()]) as Array
	var region: Rect2 = Rect2(float(dimensions[0]), float(dimensions[1]), float(dimensions[2]), float(dimensions[3]))
	var raw_offset: Array = frame.get("offset", [0, 0]) as Array
	var offset: Vector2 = Vector2(float(raw_offset[0]), float(raw_offset[1]))
	draw_texture_rect_region(texture, Rect2(at + offset - Vector2(region.size.x / 2.0, region.size.y), region.size), region, tint)
	return true

func _draw_player() -> void:
	draw_set_transform(player_world, 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.30))
	draw_set_transform(Vector2.ZERO)
	if online_mode: skills_ui.draw_effect("player", int(online.player.get("player_id", 0)), player_world, false)
	var state: String = "frames" if moving else "cast" if online_mode and skills_ui.is_chanting(int(online.player.get("player_id", 0))) else "attack" if swing_clock > 0.0 else "idle"
	if online_mode and online.seated(): state = "sit_chair" if int(online.player.sitting) == 1 else "sit_floor"
	if not _draw_character_frame(_active_hero(), player_world, facing, state, Color("ff8888") if player_hit_flash > 0.0 else Color.WHITE):
		# Explicitly identified placeholder if the optional character conversion is unavailable.
		draw_circle(player_world + Vector2(0, -18), 9, Color("82bfa2"))
		draw_circle(player_world + Vector2(0, -32), 6, GOLD)
	if swing_clock > 0.0 and not bool(_active_hero().get("ranged", false)):
		var aim: Vector2 = (tile_position(enemy_tile) - player_world).normalized()
		if online_mode:
			var directions: Dictionary = {"south": Vector2i(0, 1), "west": Vector2i(-1, 0), "north": Vector2i(0, -1), "east": Vector2i(1, 0)}
			aim = (tile_position(player_tile + (directions.get(facing, Vector2i(0, 1)) as Vector2i)) - tile_position(player_tile)).normalized()
		draw_arc(player_world + Vector2(0, -15), 25.0, aim.angle() - 0.75, aim.angle() + 0.75, 12, Color(1.0, 0.86, 0.56, swing_clock / (ONLINE_ATTACK_SWING_DURATION if online_mode else ATTACK_SWING_DURATION)), 2.0, true)

	if online_mode: skills_ui.draw_effect("player", int(online.player.get("player_id", 0)), player_world, true)

func _draw_enemy() -> void:
	var at: Vector2 = tile_position(enemy_tile)
	_draw_diamond(at, Color(0.62, 0.82, 0.63, 0.45))
	var lift: float = sin(time_alive * 2.7) * 3.0
	var rendered: bool = _draw_character_frame(monster, at, "south", "idle", Color("ffd596") if hit_flash > 0 else Color.WHITE)
	if not rendered:
		draw_circle(at + Vector2(0, -20 + lift), 16, Color(0.47, 0.84, 0.64, 0.10))
		draw_circle(at + Vector2(0, -20 + lift), 10, Color("ffd596") if hit_flash > 0 else Color("98d7a0"))
		draw_circle(at + Vector2(-3, -22 + lift), 1.4, INK)
		draw_circle(at + Vector2(3, -22 + lift), 1.4, INK)
	draw_line(at + Vector2(-13, -40), at + Vector2(13, -40), Color("243631"), 3)
	draw_line(at + Vector2(-13, -40), at + Vector2(-13 + 26.0 * float(enemy_health) / 3.0, -40), Color("98d7a0"), 3)
	draw_string(ThemeDB.fallback_font, at + Vector2(-35, -47), "Training slime", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)

func _draw_loot() -> void:
	var at: Vector2 = tile_position(loot_tile)
	draw_circle(at + Vector2(0, -5), 12 + sin(time_alive * 4.0) * 2.0, Color(0.91, 0.74, 0.44, 0.15))
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -18), at + Vector2(6, -10), at + Vector2(0, -3), at + Vector2(-6, -10)]), GOLD)
	draw_line(at + Vector2(0, -22), at + Vector2(0, -32), Color(GOLD, 0.5), 1.0)
	var key: String = str(manifest.get("sample_item_graphic", ""))
	if graphics.has(key):
		var texture: Texture2D = _texture(str((graphics[key] as Dictionary).get("path", "")))
		if texture != null: draw_texture(texture, at - texture.get_size() / 2.0)

func _style(color: Color, border: Color = Color("344743"), radius: int = 16) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style

func _panel(parent: Node, position: Vector2, size: Vector2, color: Color = Color(0.055, 0.10, 0.11, 0.94)) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = position
	panel.size = size
	panel.add_theme_stylebox_override("panel", _style(color))
	parent.add_child(panel)
	return panel

func _label(parent: Node, value: String, position: Vector2, font_size: int = 18, color: Color = TEXT) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, position: Vector2, size: Vector2, callback: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.position = position
	button.size = size
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK if primary else TEXT)
	button.add_theme_color_override("font_pressed_color", INK if primary else TEXT)
	button.add_theme_stylebox_override("normal", _style(GOLD if primary else Color("1c3234"), Color("e2ba77") if primary else Color("47615b"), 14))
	button.add_theme_stylebox_override("hover", _style(Color("f5cc89") if primary else Color("294641"), GOLD, 14))
	button.add_theme_stylebox_override("pressed", _style(Color("c39a57") if primary else Color("405d4a"), GOLD, 14))
	button.pressed.connect(callback)
	button.pressed.connect(func() -> void:
		if sfx != null: sfx.play_named("DialogButtonClick" if value == "×" else "ButtonClick", "ui")
	)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root: Control = Control.new()
	hud_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.game = self
	root.add_child(minimap)
	var header: Panel = _panel(root, Vector2(24, 22), Vector2(340, 78))
	_label(header, "ASTER VALE", Vector2(20, 10), 25, GOLD)
	location_label = _label(header, "Aeven  /  The first steps", Vector2(20, 44), 16, MUTED)
	header.hide()
	var quest: Panel = _panel(root, Vector2(24, 114), Vector2(325, 127))
	_label(quest, "WAYFARER’S FIRST STEPS", Vector2(18, 15), 14, GOLD)
	quest_label = _label(quest, "", Vector2(18, 43), 18)
	quest_hint = _label(quest, "Practice safely. Your progress saves here.", Vector2(18, 95), 13, MUTED)
	quest.hide()
	var coin_icon: TextureRect = TextureRect.new()
	coin_icon.name = "GoldIcon"
	coin_icon.texture = _item_texture("coins")
	coin_icon.position = Vector2(389, 36)
	coin_icon.size = Vector2(34, 24)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(coin_icon)
	coin_icon.hide()
	coin_label = _label(root, "", Vector2(429, 34), 19, GOLD)
	coin_label.hide()
	var menu_button: Button = _button(root, "☰", Vector2(-80, 24), Vector2(56, 54), func() -> void: menu.visible = not menu.visible)
	menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	character_button = HudIconButton.new()
	character_button.kind = "person"
	character_button.position = Vector2(-176, 24)
	character_button.size = Vector2(68, 68)
	character_button.tooltip_text = "Character equipment"
	character_button.pressed.connect(_toggle_paperdoll)
	root.add_child(character_button)
	character_button.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	joystick = Joystick.new()
	root.add_child(joystick)
	joystick.resting_position = Vector2(24, -282)
	joystick.reset()
	var bottom_hint: Label = _label(root, "Drag to move  ·  Release to stop" if OS.has_feature("mobile") else "Tap ground to explore  ·  WASD / arrows to move", Vector2(228, -55), 16, TEXT)
	bottom_hint.hide()
	bottom_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	bag_button = HudIconButton.new()
	bag_button.kind = "bag"
	bag_button.position = Vector2(-262, -100) + COMBAT_HUD_SHIFT
	bag_button.size = Vector2(76, 76)
	bag_button.tooltip_text = "Inventory bag"
	bag_button.pressed.connect(_toggle_inventory)
	root.add_child(bag_button)
	bag_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	sit_button = HudIconButton.new()
	sit_button.kind = "sit"
	sit_button.position = Vector2(-174, -88) + COMBAT_HUD_SHIFT
	sit_button.size = Vector2(68, 68)
	sit_button.tooltip_text = "Sit / Stand"
	sit_button.pressed.connect(func() -> void:
		if online_mode: online.toggle_sit()
	)
	root.add_child(sit_button)
	sit_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	attack_button = WeaponButton.new()
	attack_button.position = Vector2(-188, -252) + COMBAT_HUD_SHIFT
	attack_button.size = Vector2(164, 164)
	root.add_child(attack_button)
	attack_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	# Native touch dispatch attacks immediately; synthesized mouse release must not attack again.
	attack_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	health_label = _label(root, "Training slime • no player damage", Vector2(-348, -220), 14, MUTED)
	health_label.hide()
	health_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	toast_label = _label(root, "", Vector2(-320, -200), 17, TEXT)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	toast_label.size = Vector2(640, 62)
	toast_label.z_index = 30
	toast_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast_label.add_theme_constant_override("shadow_outline_size", 6)
	toast_label.hide()
	_build_welcome(root)
	_build_inventory(root)
	shop_ui = ShopWindow.new()
	shop_ui.build(self, root)
	drink_effects = preload("res://scripts/drink_effects.gd").new()
	drink_effects.game = self
	skills_ui = preload("res://scripts/skills_controller.gd").new()
	skills_ui.build(self, root)
	quick_items = preload("res://scripts/quick_items.gd").new()
	quick_items.build(self, root)
	services_ui = preload("res://scripts/services_window.gd").new()
	services_ui.build(self, root)
	quest_ui = preload("res://scripts/quest_window.gd").new()
	quest_ui.build(self, root)
	inn_ui = preload("res://scripts/inn_window.gd").new()
	inn_ui.build(self, root)
	guild_ui = preload("res://scripts/guild_window.gd").new()
	guild_ui.build(self, root)
	party_ui = preload("res://scripts/party_window.gd").new()
	party_ui.build(self, root)
	movement_ui = preload("res://scripts/movement_settings.gd").new()
	movement_ui.build(self, root)
	_build_paperdoll(root)
	stats_ui = CharacterStats.new()
	stats_ui.build(self, root)
	redeem_ui = preload("res://scripts/redeem_window.gd").new()
	redeem_ui.build(self, root)
	_build_menu(root)
	online.build_ui(root)
	chat_ui = preload("res://scripts/chat_window.gd").new()
	chat_ui.build(self, root)
	quest_journal = preload("res://scripts/quest_journal.gd").new()
	quest_journal.build(self, root)
	speech_layer = preload("res://scripts/speech_bubbles.gd").new()
	speech_layer.game = self
	root.add_child(speech_layer)
	# Godot GUI hit testing follows tree order, even when z_index draws a
	# curtain above a later-created HUD button. Keep all modal roots last.
	for child: Node in root.get_children():
		if child.has_meta("game_modal"): root.move_child(child, -1)

func _modal(parent: Node, size: Vector2) -> Control:
	var curtain: ColorRect = ColorRect.new()
	# Modal cards must cover later-created HUD controls (chat/menu included).
	curtain.set_meta("game_modal", true)
	curtain.z_index = 10
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.02, 0.055, 0.065, 0.72)
	parent.add_child(curtain)
	var panel: Panel = _panel(curtain, -size / 2.0, size, Color("12272a"))
	panel.set_anchors_preset(Control.PRESET_CENTER, true)
	curtain.visibility_changed.connect(func() -> void:
		if curtain.visible: _cancel_controls()
	)
	return curtain

func _build_welcome(parent: Node) -> void:
	welcome = _modal(parent, Vector2(600, 436))
	var card: Control = welcome.get_child(0) as Control
	_label(card, "AN ENDLESS KIND OF ADVENTURE", Vector2(34, 30), 14, GOLD)
	_label(card, "Aster Vale", Vector2(30, 65), 48)
	var description: Label = _label(card, "Enter a shared online world.\nCreate your character, explore Aeven,\nand adventure with other players.", Vector2(34, 139), 21, MUTED)
	description.add_theme_constant_override("line_spacing", 7)
	_label(card, "YOUR ADVENTURE BEGINS HERE", Vector2(34, 255), 14, GOLD)
	_label(card, "Tap weapon to attack; hold for auto, tap to stop.\nBag for items; character icon for equipment." if OS.has_feature("mobile") else "WASD / arrows to move. Hold weapon for auto.\nI for your bag. C for your character.", Vector2(34, 283), 16, TEXT)
	_button(card, "Log in or create account", Vector2(34,354),Vector2(532,58),online.show_login,true)

func _show_welcome() -> void:
	welcome.show()
	if sfx != null: sfx.stop()
	if music != null: music.title_music()

func _begin_play() -> void:
	if content_ready: online.show_login()

func _item_info(kind: String) -> Dictionary:
	if online_mode: return online.item_info(kind)
	if kind == "coins": return {"name": "Gold", "icon": "23:70", "type": 2}
	var data: Dictionary = manifest.get("starter_equipment", {}) as Dictionary
	var fallback: Dictionary = {"weapon": {"name": "Wayfarer blade", "icon": str(manifest.get("sample_item_icon", ""))}, "armor": {"name": "Starter armor", "icon": ""}, "boots": {"name": "Starter boots", "icon": ""}}
	return data.get(kind, fallback.get(kind, {})) as Dictionary

func _item_name(kind: String) -> String:
	return str(_item_info(kind).get("name", "Equipment"))

func _item_texture(kind: String) -> Texture2D:
	var key: String = str(_item_info(kind).get("icon", ""))
	if graphics.has(key): return _texture(str((graphics[key] as Dictionary).get("path", "")))
	return null

func _is_equipped(kind: String) -> bool:
	if online_mode: return online.is_equipped(kind)
	match kind:
		"weapon": return equipped
		"armor": return armor_equipped
		"boots": return boots_equipped
	return false

func _owns_item(kind: String) -> bool:
	if online_mode: return online.owns_item(kind)
	if kind == "coins": return true
	return dagger_count > 0 or has_blade if kind == "weapon" else kind == "armor" or kind == "boots"

func _select_item(kind: String) -> void:
	selected_item = kind
	_refresh_ui()

func _build_inventory(parent: Node) -> void:
	inventory = _modal(parent, Vector2(1120, 640))
	var card: Control = inventory.get_child(0) as Control
	_wood_card(card)
	_label(card, "YOUR BELONGINGS", Vector2(28, 18), 13, GOLD)
	_label(card, "Wayfarer’s bag", Vector2(26, 42), 30)
	_button(card, "×", Vector2(1038, 18), Vector2(56, 52), func() -> void: inventory.hide())
	inventory_summary = _label(card, "", Vector2(28, 79), 15, MUTED)
	var bag: Panel = _panel(card, Vector2(28, 150), Vector2(672, 192), Color("51381f"))
	bag.add_theme_stylebox_override("panel", _wood_style(Color("51381f"), Color("bf9555"), 3))
	for index: int in range(24):
		var column: int = index % 6
		var row: int = index / 6
		var slot: Button = _button(bag, "", Vector2(4 + column * 112, 2 + row * 48), Vector2(104, 44), func() -> void:
			if online_mode:
				online.select_bag_item(index)
				return
			var kinds: Array[String] = ["coins", "weapon", "armor", "boots"]
			if index < kinds.size() and _offline_bag_amount(kinds[index]) > 0: _select_item(kinds[index])
			elif index == 0: _select_item("coins")
		)
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.expand_icon = true
		slot.add_theme_constant_override("icon_max_width", 46)
		slot.tooltip_text = "Empty slot"
		var badge: Label = _label(slot, "", Vector2(4, 0), 18)
		badge.name = "Quantity"
		badge.size = Vector2(104, 28)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_shadow_color", Color.BLACK)
		badge.add_theme_constant_override("shadow_offset_x", 2)
		badge.add_theme_constant_override("shadow_offset_y", 2)
		bag_slots.append(slot)
	offline_bag_panel = bag
	offline_bag_slots = bag_slots.duplicate()
	bag_scroll = ScrollContainer.new()
	bag_scroll.position = Vector2(28, 120)
	bag_scroll.size = Vector2(1068, 408)
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.scroll_deadzone = 12
	card.add_child(bag_scroll)
	bag_grid = preload("res://scripts/bag_grid.gd").new()
	bag_grid.game = self
	bag_grid.custom_minimum_size = Vector2(1056, 384)
	bag_scroll.add_child(bag_grid)
	bag_grid.hide()
	item_title = _label(card, "", Vector2(28, 548), 22)
	item_title.size = Vector2(540, 32)
	item_title.clip_text = true
	_label(card, "Drag items to rearrange your bag.", Vector2(28, 591), 17, MUTED)
	junk_button = _button(card, "Junk", Vector2(576, 558), Vector2(160, 52), func() -> void: online.drop_ui.open(selected_item, "junk"))
	drop_button = _button(card, "Drop", Vector2(754, 558), Vector2(160, 52), func() -> void: online.drop_ui.open(selected_item))
	bag_overflow = OptionButton.new()
	bag_overflow.position = Vector2(420, 583)
	bag_overflow.size = Vector2(310, 36)
	bag_overflow.item_selected.connect(func(index: int) -> void:
		if index > 0: _select_item("item:%d" % bag_overflow.get_item_id(index))
	)
	card.add_child(bag_overflow)
	bag_overflow.hide()
	equip_button = _button(card, "", Vector2(932, 558), Vector2(160, 52), func() -> void:
		if online_mode:
			# A worn item ID can have another copy in the bag (paired jewellery).
			if selected_item.begins_with("item:") and online.bag_amount(online.item_id(selected_item)) > 0: _toggle_equip()
		elif _owns_item(selected_item) and not _is_equipped(selected_item): _toggle_equip()
	, true)
	_inventory_theme(card)
	inventory.hide()

func refresh_bag_overflow() -> void:
	if bag_overflow == null: return
	bag_overflow.clear()
	var missing: Array[int] = []
	for item: Dictionary in bag_grid.items:
		if not bag_grid.positions.has(str(item.id)): missing.append(int(item.id))
	bag_overflow.visible = not missing.is_empty()
	bag_overflow.add_item("Items needing space (%d)" % missing.size(), 0)
	for id: int in missing: bag_overflow.add_item(str(online.item_info("item:%d" % id).get("name", "Item")), id)
	bag_overflow.select(0)

func _wood_card(card: Control) -> void:
	card.add_theme_stylebox_override("panel", _wood_style(Color("886034"), Color("39230f"), 5))
	var grain: Control = WoodGrain.new()
	card.add_child(grain)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_paperdoll(parent: Node) -> void:
	character_panel = _modal(parent, Vector2(840, 680))
	var card: Control = character_panel.get_child(0) as Control
	_wood_card(card)
	_label(card, "CHARACTER", Vector2(40, 20), 26, GOLD)
	_button(card, "Stats", Vector2(620, 14), Vector2(180, 48), func() -> void: stats_ui.show_stats())
	paperdoll = ClassicPaperdoll.new()
	paperdoll.game = self
	paperdoll.position = Vector2(40, 80)
	paperdoll.size = Vector2(380, 290)
	paperdoll.scale = Vector2(2, 2)
	paperdoll.equipment_selected.connect(func(kind: String) -> void:
		_select_item(kind)
		if _is_equipped(kind): stats_ui.show_item(kind, character_panel, true)
	)
	paperdoll.equipment_activated.connect(func(kind: String) -> void:
		_select_item(kind)
		if _owns_item(kind) and _is_equipped(kind): _toggle_equip()
	)
	paperdoll.close_requested.connect(func() -> void: character_panel.hide())
	card.add_child(paperdoll)
	equipment_slots = paperdoll.slots
	character_panel.hide()

func _wood_style(color: Color, border: Color = Color("a97d43"), width: int = 2) -> StyleBoxFlat:
	var style: StyleBoxFlat = _style(color, border, 5)
	style.set_border_width_all(width)
	return style

func _inventory_theme(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Label:
			var label: Label = child as Label
			label.add_theme_color_override("font_color", Color("f4e3bb"))
			label.add_theme_color_override("font_shadow_color", Color(0.15, 0.08, 0.02, 0.70))
			label.add_theme_constant_override("shadow_offset_y", 1)
		if child is Button:
			var button: Button = child as Button
			button.add_theme_stylebox_override("normal", _wood_style(Color("75512b")))
			button.add_theme_stylebox_override("hover", _wood_style(Color("936a37"), Color("e2bc73")))
			button.add_theme_stylebox_override("pressed", _wood_style(Color("493018"), Color("f1cf8c")))
			button.add_theme_stylebox_override("disabled", _wood_style(Color("51381f"), Color("87633c")))
			button.add_theme_color_override("font_color", Color("f4e3bb"))
			button.add_theme_color_override("font_hover_color", Color("fff0c9"))
			button.add_theme_color_override("font_pressed_color", Color("fff0c9"))
			button.add_theme_color_override("font_disabled_color", Color("ad8e5d"))
		_inventory_theme(child)
	if parent == inventory.get_child(0):
		equip_button.add_theme_stylebox_override("normal", _wood_style(Color("d5a35c"), Color("f2cf8a")))
		equip_button.add_theme_stylebox_override("hover", _wood_style(Color("e4b873"), Color("f2cf8a")))
		equip_button.add_theme_stylebox_override("pressed", _wood_style(Color("b07a3e"), Color("f2cf8a")))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			equip_button.add_theme_color_override(state, Color("31200e"))

func _toggle_inventory() -> void:
	if not started: return
	var opening: bool = not inventory.visible
	menu.hide()
	character_panel.hide()
	inventory.visible = opening
	_cancel_controls()
	if opening:
		selected_item = ""
		for kind: String in ["weapon", "armor", "boots"]:
			if _owns_item(kind) and not _is_equipped(kind):
				selected_item = kind
				break
	_refresh_ui()

func _toggle_paperdoll() -> void:
	if not started: return
	var opening: bool = not character_panel.visible
	menu.hide()
	inventory.hide()
	character_panel.visible = opening
	_cancel_controls()
	if opening:
		selected_item = ""
		for kind: String in ["weapon", "armor", "boots"]:
			if _is_equipped(kind):
				selected_item = kind
				break
	_refresh_ui()

func _toggle_equip() -> void:
	if selected_item == "coins": return
	if online_mode:
		online.bag_action(selected_item)
		return
	if not _owns_item(selected_item): return
	match selected_item:
		"weapon": equipped = not equipped
		"armor": armor_equipped = not armor_equipped
		"boots": boots_equipped = not boots_equipped
	_refresh_ui()
	_save_progress()
	_toast("%s %s." % [_item_name(selected_item), "equipped" if _is_equipped(selected_item) else "returned to your bag"])

func _build_menu(parent: Node) -> void:
	menu = _modal(parent, Vector2(540, 600))
	var card: Control = menu.get_child(0) as Control
	_label(card, "ASTER VALE", Vector2(30, 28), 14, GOLD)
	_label(card, "A moment’s rest", Vector2(28, 61), 32)
	_label(card, "Your journey is saved automatically.\nTake a breath, then return to explore.", Vector2(30, 120), 17, MUTED)
	var music_toggle: CheckBox = CheckBox.new()
	music_toggle.text = "Music"
	music_toggle.position = Vector2(28, 172)
	music_toggle.size = Vector2(122, 36)
	music_toggle.button_pressed = music.enabled
	music_toggle.add_theme_font_size_override("font_size", 18)
	music_toggle.toggled.connect(music.set_enabled)
	card.add_child(music_toggle)
	var music_volume: HSlider = HSlider.new()
	music_volume.position = Vector2(166, 175)
	music_volume.size = Vector2(340, 30)
	music_volume.min_value = 0.0
	music_volume.max_value = 1.0
	music_volume.step = .01
	music_volume.value = music.volume
	music_volume.value_changed.connect(music.set_volume)
	card.add_child(music_volume)
	var sound_toggle: CheckBox = CheckBox.new()
	sound_toggle.text = "Sound effects"
	sound_toggle.position = Vector2(28, 212)
	sound_toggle.size = Vector2(182, 36)
	sound_toggle.button_pressed = sfx.enabled
	sound_toggle.add_theme_font_size_override("font_size", 18)
	sound_toggle.toggled.connect(sfx.set_enabled)
	card.add_child(sound_toggle)
	var sound_volume: HSlider = HSlider.new()
	sound_volume.position = Vector2(218, 215)
	sound_volume.size = Vector2(288, 30)
	sound_volume.min_value = 0; sound_volume.max_value = 1; sound_volume.step = .01
	sound_volume.value = sfx.volume
	sound_volume.value_changed.connect(sfx.set_volume)
	card.add_child(sound_volume)
	_button(card, "Movement controls", Vector2(30, 258), Vector2(480, 54), func() -> void: movement_ui.open())
	_button(card, "Return to the vale", Vector2(30, 322), Vector2(480, 58), func() -> void: menu.hide(), true)
	_button(card, "Redeem Code", Vector2(30, 386), Vector2(480, 54), func() -> void: redeem_ui.open())
	_button(card, "Party", Vector2(30, 450), Vector2(480, 54), func() -> void: party_ui.open())
	_button(card, "Log out", Vector2(30,514),Vector2(480,48),func() -> void: menu.hide(); online.log_out())
	menu.hide()

func _confirm_reset() -> void:
	if online_mode:
		_toast("Online progress belongs to the server. This control only resets an offline journey.")
		return
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "Reset this journey?"
	dialog.dialog_text = "This removes the saved position, coins, blade, and training progress on this device."
	dialog.ok_button_text = "Reset progress"
	dialog.min_size = Vector2i(520, 160)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		_reset_progress()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _reset_progress() -> void:
	_cancel_controls()
	if quick_items != null: quick_items.cancel_hold()
	owned_touches.clear()
	attack_clock = 0.0
	swing_clock = 0.0
	kills = 0
	coins = 0
	dagger_count = 0
	has_blade = false
	equipped = false
	armor_equipped = true
	boots_equipped = true
	selected_item = "weapon"
	loot_visible = false
	enemy_health = 3
	var spawn: Array = world.get("spawn", [40, 40]) as Array
	player_tile = Vector2i(int(spawn[0]), int(spawn[1]))
	player_world = tile_position(player_tile)
	moving = false
	route.clear()
	stick = Vector2.ZERO
	_place_enemy()
	menu.hide()
	_refresh_ui()
	_save_progress()
	_toast("A fresh start. Your journey begins here.")

func _refresh_ui() -> void:
	if quest_label == null: return
	if online_mode:
		if stats_ui != null: stats_ui.refresh()
		online.refresh_game_ui()
		return
	health_label.visible = false
	health_label.text = "Training slime • no player damage"
	quest_hint.text = "Practice safely. Your progress saves here."
	if not has_blade:
		quest_label.text = "1. Defeat the training slime\n2. Collect its glowing drop" if kills == 0 else "1. Slime defeated  ✓\n2. Collect its glowing drop"
	elif not equipped:
		quest_label.text = "1. First blade found  ✓\n2. Open your bag and equip it"
	else:
		quest_label.text = "First steps complete  ✓\nExplore Aeven at your own pace"
	coin_label.text = "%d Gold" % coins
	location_label.text = "%s  /  %d, %d" % [str(world.get("name", "Aeven")), player_tile.x, player_tile.y]
	if item_title != null:
		var worn: bool = _is_equipped(selected_item)
		var owned: bool = _owns_item(selected_item)
		item_title.text = _item_name(selected_item) if owned else "Your bag"
		equip_button.disabled = not owned or worn or selected_item == "coins"
		equip_button.text = "Equip"
		drop_button.disabled = true
		junk_button.disabled = true
		bag_overflow.hide()
		bag_grid.hide()
		bag_scroll.hide()
		offline_bag_panel.show()
		bag_slots = offline_bag_slots.duplicate()
		inventory_summary.text = "%d coins  ·  24 bag slots" % coins
		var kinds: Array[String] = ["coins", "weapon", "armor", "boots"]
		for index: int in range(bag_slots.size()):
			var slot: Button = bag_slots[index]
			slot.icon = null
			slot.text = ""
			(slot.get_node("Quantity") as Label).text = ""
			slot.tooltip_text = "Empty slot"
			if index < kinds.size() and (index == 0 or _offline_bag_amount(kinds[index]) > 0):
				var kind: String = kinds[index]
				slot.icon = _item_texture(kind)
				slot.tooltip_text = _item_name(kind)
				if kind == "coins" or kind == "weapon": (slot.get_node("Quantity") as Label).text = str(_offline_bag_amount(kind))
				elif slot.icon == null: slot.text = kind.substr(0, 1).to_upper()
			var chosen: bool = index < kinds.size() and selected_item == kinds[index] and (index == 0 or _offline_bag_amount(kinds[index]) > 0)
			slot.add_theme_stylebox_override("normal", _wood_style(Color("936a37") if chosen else Color("6b4927"), Color("edce87") if chosen else Color("a97d43")))
	if paperdoll != null:
		paperdoll.refresh(selected_item)
	if attack_button != null:
		attack_button.weapon = _item_texture("weapon") if equipped else null
		attack_button.collecting = loot_visible
		attack_button.tooltip_text = "Collect loot" if loot_visible else ("Attack with " + _item_name("weapon") if equipped else "Unarmed attack")
		attack_button.queue_redraw()

func _toast(value: String) -> void:
	if toast_label == null: return
	toast_label.text = value
	toast_label.show()
	toast_time = 2.0
	toast_label.modulate.a = 1.0

func _save_progress() -> void:
	if online_mode: return
	var state: Dictionary = {"version": 1, "map_id": int(world.get("id", 5)), "position": [player_tile.x, player_tile.y], "kills": kills, "coins": coins, "has_blade": has_blade, "dagger_count": maxi(dagger_count, 1 if has_blade else 0), "equipped": equipped, "armor_equipped": armor_equipped, "boots_equipped": boots_equipped}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(state))
	_refresh_ui()

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not raw is Dictionary: return
	var state: Dictionary = raw as Dictionary
	if int(state.get("version", 0)) != 1 or int(state.get("map_id", -1)) != int(world.get("id", 5)): return
	var pos: Array = state.get("position", [player_tile.x, player_tile.y]) as Array
	if pos.size() == 2:
		var saved_tile: Vector2i = Vector2i(int(pos[0]), int(pos[1]))
		if _walkable(saved_tile): player_tile = saved_tile
	kills = maxi(0, int(state.get("kills", 0)))
	coins = maxi(0, int(state.get("coins", 0)))
	dagger_count = maxi(0, int(state.get("dagger_count", 1 if bool(state.get("has_blade", false)) else 0)))
	has_blade = dagger_count > 0
	equipped = bool(state.get("equipped", false)) and has_blade
	# Version1 saves predate outfit toggles: preserve their original worn appearance.
	armor_equipped = bool(state.get("armor_equipped", true))
	boots_equipped = bool(state.get("boots_equipped", true))
	started_from_save = true

func _show_content_error() -> void:
	welcome.show()
	var card: Control = welcome.get_child(0) as Control
	for child: Node in card.get_children(): child.queue_free()
	_label(card, "Content import required", Vector2(30, 45), 30, GOLD)
	_label(card, "The map or graphic manifest could not be loaded.\nRun the documented content importer, then reopen.\nExpected: content/world.json and manifest.json.", Vector2(30, 120), 19, TEXT)
	push_error("Aster Vale content unavailable. Run tools/import_content.py.")

func _handle_back() -> void:
	if party_ui != null and party_ui.panel.visible:
		party_ui.panel.hide()
		return
	if skills_ui != null and (skills_ui.target_panel.visible or skills_ui.bard_panel.visible):
		skills_ui.target_panel.hide(); skills_ui.bard_panel.hide(); skills_ui.armed = 0
		return
	if redeem_ui != null and redeem_ui.panel.visible:
		redeem_ui.close()
		return
	if online != null and online.drop_ui != null and online.drop_ui.panel.visible:
		online.drop_ui.panel.hide()
		return
	if not content_ready: return
	if chat_ui != null and chat_ui.typing():
		chat_ui.blur_quick()
		return
	_cancel_controls()
	if quick_items != null: quick_items.cancel_hold()
	owned_touches.clear()
	if online != null and online.creation_panel != null and online.creation_panel.visible:
		online.creation_panel.hide()
	elif online != null and online.panel != null and online.panel.visible:
		online._close_panel()
	elif stats_ui != null and stats_ui.is_open():
		stats_ui.hide()
	elif quick_items != null and quick_items.panel.visible:
		quick_items.panel.hide()
	elif skills_ui != null and skills_ui.panel.visible:
		skills_ui.panel.hide()
	elif chat_ui != null and chat_ui.panel.visible:
		chat_ui.close()
	elif movement_ui != null and movement_ui.panel.visible:
		movement_ui.close()
	elif guild_ui != null and guild_ui.panel.visible:
		guild_ui.close()
	elif inn_ui != null and inn_ui.panel.visible:
		inn_ui.close()
	elif quest_journal != null and quest_journal.panel.visible:
		quest_journal.dismiss()
	elif quest_ui != null and quest_ui.panel.visible:
		quest_ui.close()
	elif services_ui != null and services_ui.panel.visible:
		services_ui.close()
	elif shop_ui != null and shop_ui.panel.visible:
		shop_ui.close()
	elif inventory.visible:
		inventory.hide()
	elif character_panel.visible:
		character_panel.hide()
	elif menu.visible:
		menu.hide()
	elif started:
		menu.show()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if content_ready:
			_cancel_controls()
			if stats_ui != null: stats_ui.stop_repeat()
			if quick_items != null: quick_items.cancel_hold()
			if chat_ui != null: chat_ui.blur_quick()
			owned_touches.clear()
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if content_ready and started: _save_progress()

func _play_sound(sound_id: String) -> void:
	if sfx == null: return
	if sound_id == "attack":
		var graphic: int = 0
		if online_mode:
			var gear: Array = online.player.get("equipment_graphics", []) as Array
			if gear.size() == 9: graphic = int(gear[8])
		elif equipped: graphic = 4
		sfx.weapon(graphic)
	elif sound_id == "pickup": sfx.play_named("InventoryPickup")
	else: sfx.play_named(sound_id)

func _active_hero() -> Dictionary:
	if online_mode: return online.character_graphic(online.player)
	var characters: Dictionary = manifest.get("characters", {}) as Dictionary
	var variants: Dictionary = characters.get("hero_variants", {}) as Dictionary
	var key: String = "a%d_b%d_w%d" % [int(armor_equipped), int(boots_equipped), int(equipped)]
	if variants.has(key): return variants[key] as Dictionary
	return hero_equipped if equipped and not hero_equipped.is_empty() else hero

func _layer_rank(layer: String) -> int:
	return int({"shadow": 10, "objects": 20, "walls_down": 40, "walls_right": 50, "overlay": 60, "roof": 80, "wall_top": 90, "overlay2": 99}.get(layer, 20))

func _offline_bag_amount(kind: String) -> int:
	match kind:
		"coins": return coins
		"weapon": return maxi(0, maxi(dagger_count, 1 if has_blade else 0) - (1 if equipped else 0))
		"armor": return 0 if armor_equipped else 1
		"boots": return 0 if boots_equipped else 1
	return 0

func _hud_bounds() -> Rect2:
	return hud_root.get_global_rect() if hud_root != null else get_viewport_rect()

func _layout_safe_area() -> void:
	if hud_root == null: return
	hud_root.offset_left = 0.0
	hud_root.offset_top = 0.0
	hud_root.offset_right = 0.0
	hud_root.offset_bottom = 0.0
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var pixels: Vector2i = get_window().size
		if safe.size.x > 0 and safe.size.y > 0 and pixels.x > 0 and pixels.y > 0:
			var ratio: Vector2 = get_viewport_rect().size / Vector2(pixels)
			hud_root.offset_left = maxf(0.0, float(safe.position.x)) * ratio.x
			hud_root.offset_top = maxf(0.0, float(safe.position.y)) * ratio.y
			hud_root.offset_right = -maxf(0.0, float(pixels.x - safe.end.x)) * ratio.x
			hud_root.offset_bottom = -maxf(0.0, float(pixels.y - safe.end.y)) * ratio.y
	if joystick != null and not joystick.active: joystick.reset()
