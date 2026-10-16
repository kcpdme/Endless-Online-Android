extends Control
## Original 380 × 290 EO male paperdoll bitmap and exact equipment hit regions.
## The original silhouette stays visible; no live character is painted over the art.
signal equipment_selected(kind: String)
signal close_requested

var inspection: Dictionary = {}
var game: Node
var slots: Dictionary = {}
var selected_kind: String = ""
var background: Texture2D
var information_labels: Array[Label] = []

func _ready() -> void:
	custom_minimum_size = Vector2(380, 290)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	var data: Dictionary = _paperdoll_data()
	var path: String = str(data.get("background", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		background = load(path) as Texture2D
	else:
		push_error("Classic paperdoll background is missing from the content manifest.")
	var regions: Dictionary = data.get("slots", {}) as Dictionary
	for raw_kind: Variant in regions:
		var kind: String = str(raw_kind)
		var rectangle: Array = regions[kind] as Array
		if rectangle.size() != 4: continue
		var button: Button = Button.new()
		button.name = "Equipment_" + kind
		button.position = Vector2(float(rectangle[0]), float(rectangle[1]))
		button.size = Vector2(float(rectangle[2]), float(rectangle[3]))
		button.focus_mode = Control.FOCUS_NONE
		button.text = ""
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", maxi(1, int(rectangle[2]) - 6))
		button.add_theme_stylebox_override("normal", _outline(false))
		button.add_theme_stylebox_override("hover", _outline(true, Color(0.98, 0.88, 0.53, 0.80)))
		button.add_theme_stylebox_override("pressed", _outline(true, Color(1.0, 0.94, 0.70, 1.0)))
		button.pressed.connect(func() -> void: equipment_selected.emit(kind))
		add_child(button)
		slots[kind] = button
	var rows: Array[String] = ["Wayfarer", "Aeven", "-", "-", "-", "-", "-", "-"]
	for index: int in range(rows.size()):
		var label: Label = Label.new()
		label.text = rows[index]
		label.position = Vector2(228, 22 + index * 30)
		label.size = Vector2(131, 15)
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("d2d1c7"))
		label.add_theme_color_override("font_shadow_color", Color(0.05, 0.035, 0.01, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(label)
		information_labels.append(label)
	var close_button: Button = Button.new()
	close_button.name = "ClassicOk"
	close_button.position = Vector2(276, 253)
	close_button.size = Vector2(90, 25)
	close_button.text = ""
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_stylebox_override("normal", _outline(false))
	close_button.add_theme_stylebox_override("hover", _outline(true, Color(0.98, 0.88, 0.53, 0.80)))
	close_button.add_theme_stylebox_override("pressed", _outline(true, Color(1.0, 0.94, 0.70, 1.0)))
	close_button.pressed.connect(func() -> void: close_requested.emit())
	add_child(close_button)
	refresh(selected_kind)

func _paperdoll_data() -> Dictionary:
	if game == null: return {}
	var manifest: Dictionary = game.get("manifest") as Dictionary
	return manifest.get("paperdoll", {}) as Dictionary

func _outline(selected: bool, color: Color = Color(0.98, 0.88, 0.53, 0.95)) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = color
	style.set_border_width_all(1 if selected else 0)
	style.set_content_margin_all(2.0)
	return style

func _draw() -> void:
	if background != null:
		draw_texture(background, Vector2.ZERO)

func refresh(kind: String) -> void:
	selected_kind = kind
	if not is_node_ready(): return
	for raw_kind: Variant in slots:
		var slot_kind: String = str(raw_kind)
		var button: Button = slots[slot_kind] as Button
		var item_id: int = int((inspection.get("equipment", {}) as Dictionary).get(game.online._slot_name(slot_kind), 0)) if not inspection.is_empty() else 0
		var item_kind: String = "item:%d" % item_id if not inspection.is_empty() else slot_kind
		var worn: bool = item_id > 0 if not inspection.is_empty() else (game != null and bool(game.call("_is_equipped", slot_kind)))
		button.icon = game.call("_item_texture", item_kind) as Texture2D if worn else null
		button.text = ""
		button.tooltip_text = str(game.call("_item_name", item_kind)) if worn else "Empty " + slot_kind + " slot"
		button.add_theme_stylebox_override("normal", _outline(slot_kind == selected_kind))
	queue_redraw()
