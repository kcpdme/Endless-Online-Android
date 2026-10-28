extends RefCounted
## Touch/mouse gesture owns one pointer; release outside the column cancels.
const IDS: Array[int] = [1, 3, 4, 5, 7]
const NAMES: Array[String] = ["Happy", "Sad", "Angry", "Confused", "Hearts"]
const HOLD_MSEC: int = 220
var game: Node
var button: Button
var popup: Panel
var rows: Array[Control] = []
var pointer: int = -99
var held_at: int = 0
var selected: int = -1
var pending: int = -1
var last_sent: int = -1000

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new()
	button.set("kind", "emote")
	button.position = Vector2(512, 144)
	button.size = Vector2(52, 52)
	button.tooltip_text = "Hold and slide up to an emote; release to use"
	parent.add_child(button)
	popup = Panel.new()
	popup.position = Vector2(500, -150)
	popup.size = Vector2(76, 284)
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.z_index = 40
	popup.add_theme_stylebox_override("panel", game._style(Color(0.03, 0.07, 0.09, 0.72), Color(0.82, 0.75, 0.54, 0.6), 14))
	parent.add_child(popup)
	for index: int in range(IDS.size()):
		var row: Panel = Panel.new()
		row.position = Vector2(6, 6 + index * 54)
		row.size = Vector2(64, 52)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup.add_child(row)
		rows.append(row)
		var icon: TextureRect = TextureRect.new()
		icon.position = Vector2(12, 2)
		icon.size = Vector2(40, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = preload("res://scripts/drink_effects.gd").social_texture(IDS[index])
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		row.add_child(icon)
		var label: Label = game._label(row, NAMES[index], Vector2(0, 33), 11, game.TEXT)
		label.size = Vector2(64, 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.hide()
	game.online.session.message_received.connect(func(message: Dictionary) -> void:
		if int(message.get("id", -1)) != pending or pending < 0: return
		pending = -1
		if not bool(message.get("ok", false)): game._toast(str(message.get("error", "Emote failed")))
	)

func available() -> bool:
	return game.online_mode and game.online.active and game.started and not game._modal_open() and not game.welcome.visible and not game.online.defeated and game.skills_ui.casting.is_empty()

func contains(point: Vector2) -> bool:
	return button.is_visible_in_tree() and (button.get_global_rect().has_point(point) or (popup.visible and popup.get_global_rect().has_point(point)))

func begin(id: int) -> void:
	if pointer != -99 or not available(): return
	game._cancel_controls()
	pointer = id
	held_at = Time.get_ticks_msec()
	selected = -1

func choose(point: Vector2) -> void:
	selected = -1
	for index: int in range(rows.size()):
		if rows[index].get_global_rect().has_point(point): selected = index
	for index: int in range(rows.size()):
		(rows[index] as Panel).add_theme_stylebox_override("panel", game._style(Color(0.26, 0.38, 0.36, 0.9) if index == selected else Color(0, 0, 0, 0), Color("e9bd71") if index == selected else Color(0, 0, 0, 0), 9))

func release(point: Vector2) -> void:
	if popup.visible: choose(point)
	var index: int = selected
	cancel()
	if index >= 0: send_emote(IDS[index])

func cancel() -> void:
	pointer = -99
	selected = -1
	if popup != null: popup.hide()

func send_emote(ident: int) -> void:
	if not available() or pending >= 0 or Time.get_ticks_msec() - last_sent < 800: return
	if not game.online.mobile_action_ready(): return
	last_sent = Time.get_ticks_msec()
	pending = game.online.session.request("feature_action", {"kind":"emotes", "action":"emote", "ident":ident})

func layout() -> void:
	var height: float = clampf((button.get_global_rect().position.y - 28.0) / 5.0, 34.0, 54.0)
	popup.size.y = height * 5 + 12
	popup.position.y = button.position.y - popup.size.y - 8
	for index: int in range(rows.size()):
		rows[index].position.y = 6 + index * height
		rows[index].size.y = height - 2
		(rows[index].get_child(0) as TextureRect).size.y = height - 22
		(rows[index].get_child(1) as Label).position.y = height - 21

func tick() -> void:
	layout()
	button.visible = available()
	if not available(): cancel(); return
	if pointer != -99 and Time.get_ticks_msec() - held_at >= HOLD_MSEC: popup.show()

func input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and available() and not game._editing_text() and not game.chat_ui.typing():
		var keys: Array[int] = [KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
		var digit: int = keys.find(event.keycode)
		if digit >= 0: send_emote(10 if digit == 0 else digit); return true
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return pointer != -99 or (contains(event.position) and available())
	if pointer != -99:
		if event is InputEventScreenTouch and event.index == pointer:
			if not event.pressed:
				release(event.position)
			return true
		if event is InputEventMouseButton and pointer == -2 and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: release(event.position)
			return true
		if (event is InputEventScreenDrag and event.index == pointer) or (event is InputEventMouseMotion and pointer == -2):
			if event.position.y < button.get_global_rect().position.y - 8: popup.show()
			if popup.visible: choose(event.position)
			return true
	if not available(): return false
	if (event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)) and event.pressed and button.get_global_rect().has_point(event.position):
		begin(event.index if event is InputEventScreenTouch else -2)
		return true
	return false
