extends Control
## One continuous bag with original EIF footprints and character-local positions.
const COLUMNS: int = 15
const MIN_ROWS: int = 5
var rows: int = MIN_ROWS
const CELL: Vector2 = Vector2(70.4, 76.8)
const FILE: String = "user://bag_layouts_15x5.json"
var game: Node
var positions: Dictionary = {}
var items: Array[Dictionary] = []
var buttons: Dictionary = {}
var selection_styles:Dictionary={}
var profile: String = ""
var signature: String = ""
var drag_id: int = 0
var drag_touch: int = -1
var drag_start: Vector2
var drag_at: Vector2
var drag_offset: Vector2
var dragging: bool = false
var touch_until: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visibility_changed.connect(cancel_drag)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: cancel_drag()

func dimensions(id: int) -> Vector2i:
	if not str(game.online.item_info("item:%d" % id).get("egg_state", "")).is_empty():return Vector2i.ONE
	var code: int = clampi(int(game.online.item_info("item:%d" % id).get("size", 0)), 0, 7)
	return Vector2i(1 + code / 4, 1 + code % 4)

func rectangle(id: int) -> Rect2:
	var p: Array = positions.get(str(id), [0, 0]) as Array
	return Rect2(Vector2(int(p[0]), int(p[1])) * CELL, Vector2(dimensions(id)) * CELL)

func fits(id: int, tile: Vector2i) -> bool:
	var footprint: Vector2i = dimensions(id)
	if tile.x < 0 or tile.y < 0 or tile.x + footprint.x > COLUMNS or tile.y + footprint.y > rows: return false
	var rect: Rect2i = Rect2i(tile, footprint)
	for item: Dictionary in items:
		var other: int = int(item.id)
		if other == id or not positions.has(str(other)): continue
		var p: Array = positions[str(other)] as Array
		if rect.intersects(Rect2i(Vector2i(int(p[0]), int(p[1])), dimensions(other))): return false
	return true

func move_item(id: int, tile: Vector2i) -> bool:
	if not positions.has(str(id)) or not fits(id, tile): return false
	positions[str(id)] = [tile.x, tile.y]
	_save()
	_layout()
	return true

func refresh() -> void:
	if not game.online_mode:
		hide()
		return
	show()
	var next_profile: String = game.online.host_field.text.strip_edges().to_lower() + ":" + str(game.online.player.get("name", ""))
	var next_items: Array[Dictionary] = game.online.inventory_items()
	var next_signature: String = JSON.stringify([next_profile, next_items])
	if signature == next_signature:
		_style_selection()
		return
	cancel_drag()
	if profile != next_profile:
		profile = next_profile
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else {}
		var saved: Dictionary = data as Dictionary if data is Dictionary else {}
		if not saved.has(profile) and FileAccess.file_exists("user://bag_layouts_12x4.json"):
			var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://bag_layouts_12x4.json"))
			if legacy is Dictionary: saved[profile] = (legacy as Dictionary).get(profile, {})
		positions = (saved.get(profile, {}) as Dictionary).duplicate()
	items = next_items
	signature = next_signature
	# Validate saved positions, retaining valid slots before placing new items.
	rows = MIN_ROWS
	var pending: Dictionary = positions.duplicate()
	positions.clear()
	for item: Dictionary in items:
		var id: int = int(item.id)
		var p: Variant = pending.get(str(id))
		# Keep first-page positions; repack all former extra pages into this bag.
		if p is Array and p.size() == 3:
			p = [p[1], p[2]] if int(p[0]) == 0 else null
		if p is Array and p.size() == 2 and fits(id, Vector2i(int(p[0]), int(p[1]))): positions[str(id)] = [int(p[0]), int(p[1])]
	var placement_order: Array[Dictionary] = items.duplicate()
	placement_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.id) == 1 or int(b.id) == 1: return int(a.id) == 1
		var ad: Vector2i = dimensions(int(a.id))
		var bd: Vector2i = dimensions(int(b.id))
		return ad.y > bd.y if ad.y != bd.y else ad.x > bd.x
	)
	for item: Dictionary in placement_order:
		var id: int = int(item.id)
		if positions.has(str(id)): continue
		var placed: bool = false
		for y: int in range(rows):
			for x: int in range(COLUMNS):
				if fits(id, Vector2i(x, y)):
					positions[str(id)] = [x, y]
					placed = true
					break
			if placed: break
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	game.bag_slots.clear()
	for item: Dictionary in items:
		var id: int = int(item.id)
		var info: Dictionary = game.online.item_info("item:%d" % id)
		var button: Button = Button.new()
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
		button.icon = game.online._catalog_texture(str(info.get("icon", "")))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", dimensions(id).x * CELL.x - 10)
		button.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0))
		button.tooltip_text = str(info.get("name", "Item"))
		add_child(button)
		var artwork: TextureRect = TextureRect.new()
		artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		artwork.texture = button.icon
		var egg:bool=not str(info.get("egg_state", "")).is_empty()
		artwork.position = Vector2(11, 8) if egg else Vector2(5, 5)
		artwork.size = CELL-Vector2(26,20) if egg else Vector2(dimensions(id)) * CELL - Vector2(14, 14)
		artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(artwork)
		var quantity: Label = game._label(button, str(int(item.amount)) if id == 1 or int(item.amount) > 1 else "", Vector2(3, 0), 18, game.TEXT)
		quantity.name = "Quantity"
		quantity.size = Vector2(dimensions(id).x * CELL.x - 10, 25)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quantity.add_theme_color_override("font_shadow_color", Color.BLACK)
		quantity.add_theme_constant_override("shadow_offset_x", 2)
		quantity.add_theme_constant_override("shadow_offset_y", 2)
		buttons[str(id)] = button
		game.bag_slots.append(button)
	_save()
	_layout()

func _layout() -> void:
	rows = MIN_ROWS
	custom_minimum_size = Vector2(COLUMNS, rows) * CELL
	for key: String in buttons:
		var id: int = int(key)
		var button: Button = buttons[key] as Button
		button.visible = positions.has(key)
		if not button.visible: continue
		button.position = rectangle(id).position + Vector2(2, 2)
		button.size = rectangle(id).size - Vector2(4, 4)
	game.refresh_bag_overflow()
	_style_selection()

func _style_selection() -> void:
	for key: String in buttons:
		var chosen: bool = game.selected_item == "item:" + key
		if not selection_styles.has(chosen):selection_styles[chosen]=game._wood_style(Color("896232") if chosen else Color(0.18,0.10,0.035,0.35),Color("f4d089") if chosen else Color("9a7342"),2 if chosen else 1)
		var button:Button=buttons[key]
		if button.get_theme_stylebox("normal")!=selection_styles[chosen]:button.add_theme_stylebox_override("normal",selection_styles[chosen])
	queue_redraw()

func _save() -> void:
	if profile.is_empty(): return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else {}
	var data: Dictionary = raw as Dictionary if raw is Dictionary else {}
	data[profile] = positions
	var file: FileAccess = FileAccess.open(FILE, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data))

func _draw() -> void:
	for y: int in range(rows):
		for x: int in range(COLUMNS): draw_rect(Rect2(Vector2(x, y) * CELL, CELL).grow(-1), Color("a57e48"), false, 1)
	if dragging and drag_id > 0:
		var origin: Vector2 = drag_at - drag_offset
		var tile: Vector2i = Vector2i((origin / CELL).round())
		var footprint: Vector2 = Vector2(dimensions(drag_id)) * CELL
		draw_rect(Rect2(Vector2(tile) * CELL, footprint).grow(-2), Color(0.65, 0.85, 0.45, 0.45) if fits(drag_id, tile) else Color(1, 0.25, 0.15, 0.4))
		var texture: Texture2D = (buttons[str(drag_id)] as Button).icon
		if texture != null:
			var factor: float = minf((footprint.x - 8) / texture.get_width(), (footprint.y - 8) / texture.get_height())
			var drawn: Vector2 = texture.get_size() * factor
			draw_texture_rect(texture, Rect2(origin + (footprint - drawn) / 2, drawn), false, Color(1, 1, 1, 0.8))

func cancel_drag() -> void:
	drag_id = 0
	drag_touch = -1
	dragging = false
	queue_redraw()

func _begin(point: Vector2, finger: int) -> void:
	if drag_id > 0: return
	for key: String in buttons:
		if positions.has(key) and rectangle(int(key)).has_point(point):
			drag_id = int(key)
			drag_touch = finger
			drag_start = point
			drag_at = point
			drag_offset = point - rectangle(drag_id).position
			game._select_item("item:" + key)
			return

func _motion(point: Vector2) -> void:
	if drag_id == 0: return
	drag_at = point
	if point.distance_to(drag_start) > 12: dragging = true
	queue_redraw()

func _finish(point: Vector2) -> void:
	if dragging:
		if not (get_parent() as Control).get_global_rect().has_point(get_global_transform_with_canvas() * point):
			cancel_drag()
			return
		if not move_item(drag_id, Vector2i(((point - drag_offset) / CELL).round())): game._toast("That item needs a clear space in your bag.")
	cancel_drag()

func _input(event: InputEvent) -> void:
	if game.online.drop_ui != null and game.online.drop_ui.panel.visible:
		cancel_drag()
		return
	if not is_visible_in_tree():
		cancel_drag()
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * touch.position
		if touch.pressed and Rect2(Vector2.ZERO, size).has_point(point) and (get_parent() as Control).get_global_rect().has_point(touch.position):
			touch_until = Time.get_ticks_msec() + 500
			_begin(point, touch.index)
			if drag_id > 0: get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == drag_touch:
			_finish(point)
			touch_until = Time.get_ticks_msec() + 500
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == drag_touch:
		_motion(get_global_transform_with_canvas().affine_inverse() * (event as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed and drag_touch == -2:
		_finish(get_local_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_touch == -2:
		_motion(get_local_mouse_position())
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	# Android can synthesize the mouse press before the actual finger press.
	# The native touch owns that gesture, including its release outside the grid.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if Time.get_ticks_msec() < touch_until: return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
		_begin((event as InputEventMouseButton).position, -2)
		accept_event()
