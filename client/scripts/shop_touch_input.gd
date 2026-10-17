extends Node
## Explicit mobile scroll/tap arbitration; physical mouse and scrollbars stay native.
var panel: Control
var catalog: ItemList
var details: ScrollContainer
var pointer: int = -1
var start: Vector2 = Vector2.ZERO
var initial_scroll: float = 0.0
var pressed_row: int = -1
var dragging: bool = false
var in_catalog: bool = false

func _ready() -> void:
	panel.visibility_changed.connect(func() -> void:
		if not panel.visible: pointer = -1
	)

func _bar() -> VScrollBar:
	return catalog.get_v_scroll_bar() if in_catalog else details.get_v_scroll_bar()

func _inside(point: Vector2) -> bool:
	return catalog.get_global_rect().has_point(point) or details.get_global_rect().has_point(point)

func _input(event: InputEvent) -> void:
	if not panel.visible: return
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		# Touch handles selection on release, after distinguishing a swipe. The
		# emulated mouse must not select another row at the beginning of a drag.
		if pointer != -1 or _inside(event.position): get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if pointer != -1 or not _inside(event.position): return
			pointer = event.index
			start = event.position
			in_catalog = catalog.get_global_rect().has_point(start)
			initial_scroll = _bar().value
			dragging = false
			pressed_row = catalog.get_item_at_position(catalog.get_global_transform_with_canvas().affine_inverse() * start, true) if in_catalog else -1
			get_viewport().set_input_as_handled()
		elif event.index == pointer:
			if not dragging and not event.canceled and in_catalog and catalog.get_global_rect().has_point(event.position):
				var row: int = catalog.get_item_at_position(catalog.get_global_transform_with_canvas().affine_inverse() * event.position, true)
				if row >= 0 and row == pressed_row:
					catalog.select(row)
					catalog.item_selected.emit(row)
			pointer = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == pointer:
		if event.position.distance_to(start) > 12.0: dragging = true
		if dragging: _bar().value = initial_scroll + start.y - event.position.y
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]: pointer = -1
