extends Node
## Shared touch gestures for modal lists. A swipe never becomes a button tap.
const WIDTH: float = 36.0
const DEADZONE: float = 9.0
const REPLAY_DEVICE: int = 7319
var game: Node
var regions: Array[Control] = []
var editors: Array[Control] = []
var finger: int = -1
var region: Control
var initial: Vector2
var initial_value: float
var dragging: bool = false

func _ready() -> void:
	get_tree().node_added.connect(_added)
	for node: Node in game.hud_root.find_children("*","Control",true,false): _configure(node)

func _added(node: Node) -> void:
	if node is Control: _configure.call_deferred(node)

func _configure(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not game.hud_root.is_ancestor_of(node): return
	if node is VScrollBar or node is HScrollBar:
		var vertical: bool = node is VScrollBar
		if vertical: node.custom_minimum_size.x = WIDTH
		else: node.custom_minimum_size.y = WIDTH
		for key: String in ["scroll","scroll_focus","grabber","grabber_highlight","grabber_pressed"]:
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color("352b21") if key.begins_with("scroll") else Color("d2ab68") if key=="grabber" else Color("f4d598")
			style.border_color = Color("927249"); style.set_border_width_all(2); style.set_corner_radius_all(7)
			style.content_margin_left=15 if vertical else 28;style.content_margin_right=15 if vertical else 28
			style.content_margin_top=28 if vertical else 15;style.content_margin_bottom=28 if vertical else 15
			node.add_theme_stylebox_override(key,style)
	if node is ScrollContainer or node is ItemList or node is RichTextLabel:
		if not regions.has(node): regions.append(node)
		if node is ScrollContainer: node.scroll_deadzone = 8
		_configure(node.get_v_scroll_bar())
		if node.has_method("get_h_scroll_bar"): _configure(node.call("get_h_scroll_bar"))
	if node is LineEdit or node is TextEdit or node is OptionButton:
		if not editors.has(node): editors.append(node)
		if node is TextEdit:
			_configure(node.get_v_scroll_bar());_configure(node.get_h_scroll_bar())

func _bar(control: Control) -> VScrollBar:
	return control.get_v_scroll_bar()

func _modal(control: Node) -> Control:
	var node: Node = control
	while node != null and node != game.hud_root:
		if node.has_meta("game_modal"): return node as Control
		node=node.get_parent()
	return null

func _inside(control: Control, point: Vector2) -> bool:
	if not control.is_visible_in_tree() or not control.get_global_rect().has_point(point): return false
	var parent: Node=control.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().has_point(point): return false
		parent=parent.get_parent()
	return true

func _top_modal() -> Control:
	var top: Control
	for node: Node in game.hud_root.get_children():
		if node is Control and node.has_meta("game_modal") and node.is_visible_in_tree(): top=node
	return top

func _pick(point: Vector2) -> Control:
	var top: Control=_top_modal()
	if top==null: return null # The compact chat feed retains its own gesture control.
	for editor: Control in editors:
		if is_instance_valid(editor) and _modal(editor)==top and _inside(editor,point): return null
	var chosen: Control
	for candidate: Control in regions:
		if not is_instance_valid(candidate) or _modal(candidate)!=top or not _inside(candidate,point): continue
		var bar: VScrollBar=_bar(candidate)
		if bar.max_value<=bar.page or _inside(bar,point): continue
		if chosen==null or candidate.is_greater_than(chosen): chosen=candidate
	return chosen

func _input(event: InputEvent) -> void:
	if event.device==REPLAY_DEVICE: return
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device==InputEvent.DEVICE_ID_EMULATION:
		if finger!=-1 or _pick(event.position)!=null: get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger!=-1: return
			region=_pick(event.position)
			if region==null: return
			finger=event.index;initial=event.position;initial_value=_bar(region).value;dragging=false
			get_viewport().set_input_as_handled()
		elif event.index==finger:
			var tap: bool=not dragging and not event.canceled and is_instance_valid(region) and _inside(region,event.position)
			finger=-1
			if tap: _tap.call_deferred(initial,event.position,event.double_tap,_modal(region))
			region=null;get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index==finger:
		if not is_instance_valid(region) or not region.is_visible_in_tree(): finger=-1;region=null;return
		if event.position.distance_to(initial)>DEADZONE: dragging=true
		if dragging:
			if region is RichTextLabel: region.scroll_following=false
			_bar(region).value=initial_value+initial.y-event.position.y
		get_viewport().set_input_as_handled()

func _tap(from: Vector2, to: Vector2, double: bool, scope: Control) -> void:
	if not is_instance_valid(scope) or not scope.is_visible_in_tree() or scope!=_top_modal(): return
	# Replay a GUI click only after the gesture has proven to be a tap. Native
	# buttons, list selection and links keep their normal handlers and focus.
	for pressed: bool in [true,false]:
		var mouse: InputEventMouseButton=InputEventMouseButton.new()
		mouse.device=REPLAY_DEVICE;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=pressed
		mouse.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;mouse.position=get_viewport().get_final_transform()*(from if pressed else to);mouse.global_position=mouse.position;mouse.double_click=double
		Input.parse_input_event(mouse)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]: finger=-1;region=null
