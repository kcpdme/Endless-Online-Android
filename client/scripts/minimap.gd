extends Control
## Original map atlas with a closer local view and clear self/enemy markers.
const PLOT: Rect2 = Rect2(8, 42, 272, 162)
const CELL: Vector2 = Vector2(20, 10)
const SELF_COLOR: Color = Color("55e888")
const ENEMY_COLOR: Color = Color("ff5364")
var game: Node
var expanded: bool = true
var map_id: int = -1
var specs: Dictionary = {}
var warps: Dictionary = {}
var atlas: Texture2D
var clock: float = 0.0

func _ready() -> void:
	position = Vector2(28, 140)
	size = Vector2(288, 212)
	mouse_filter = Control.MOUSE_FILTER_STOP
	atlas = game._graphic(2, 45)
	var settings: ConfigFile = ConfigFile.new()
	if settings.load("user://minimap_settings.cfg") == OK:
		expanded = bool(settings.get_value("minimap", "expanded", true))
	_resize()
	hide()

func _process(delta: float) -> void:
	visible = game.started and not game._modal_open()
	if not visible: return
	if map_id != int(game.world.get("id", -1)): configure_map(game.world)
	clock += delta
	if clock >= 0.1:
		clock = 0.0
		queue_redraw()

func configure_map(world: Dictionary) -> void:
	map_id = int(world.get("id", -1))
	specs.clear(); warps.clear()
	for spec: Dictionary in world.get("tile_specs", []):
		specs[Vector2i(int(spec.x), int(spec.y))] = int(spec.spec)
	for warp: Dictionary in world.get("warps", []):
		warps[Vector2i(int(warp.x), int(warp.y))] = int(warp.get("door", 0))
	queue_redraw()

func contains(point: Vector2) -> bool:
	return visible and get_global_rect().has_point(point)

func press(point: Vector2) -> void:
	if not contains(point): return
	# The plot consumes input; only its header changes visibility.
	if point.y - global_position.y > 42.0: return
	expanded = not expanded
	_resize()
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("minimap", "expanded", expanded)
	settings.save("user://minimap_settings.cfg")
	if game.sfx != null: game.sfx.play_named("ButtonClick", "ui")

func _resize() -> void:
	size = Vector2(288, 212) if expanded else Vector2(100, 42)
	queue_redraw()

func tile_kind(tile: Vector2i) -> int:
	var spec: int = int(specs.get(tile, -1))
	if spec == 18: return -1 # Original MapEdge is invisible.
	if spec in [0, 19]: return 3 # Solid wall and original fake wall marker.
	if spec >= 1 and spec <= 16: return 7 # Interactable tile: blue.
	if warps.has(tile): return 7 if int(warps[tile]) > 0 else 0
	if tile.x == 0 or int(specs.get(tile + Vector2i.LEFT, -1)) == 18: return 0
	if tile.y == 0 or int(specs.get(tile + Vector2i.UP, -1)) == 18: return 1
	return 2

func npc_kind(npc: Dictionary) -> int:
	var info: Dictionary = (game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(npc.get("id", 0))), {}) as Dictionary
	return 5 if int(info.get("type", -1)) in [1, 2] else 8

func marker_position(tile: Vector2i) -> Vector2:
	var delta: Vector2i = tile - game.player_tile
	return PLOT.get_center() + Vector2(float(delta.x - delta.y) * CELL.x / 2.0, float(delta.x + delta.y) * CELL.y / 2.0)

func _cell(tile: Vector2i, kind: int, opacity: float = 0.65) -> void:
	if kind < 0 or atlas == null: return
	var target: Rect2 = Rect2(marker_position(tile) - CELL / 2.0, CELL)
	if not PLOT.encloses(target): return
	var width: float = float(atlas.get_width()) / 9.0
	draw_texture_rect_region(atlas, target, Rect2(float(kind) * width, 0, width, atlas.get_height()), Color(1,1,1,opacity))

func _marker(tile: Vector2i, color: Color, self_marker: bool = false) -> void:
	var center: Vector2 = marker_position(tile)
	# Small outlined pictograms stay legible against both walls and passages.
	if not PLOT.encloses(Rect2(center - Vector2(8, 8), Vector2(16, 16))): return
	draw_set_transform(center)
	var outline: Color = Color("10231b") if self_marker else Color("2c1016")
	if self_marker:
		var house: PackedVector2Array = PackedVector2Array([Vector2(-7, -1), Vector2(0, -7), Vector2(7, -1), Vector2(5, -1), Vector2(5, 6), Vector2(-5, 6), Vector2(-5, -1)])
		draw_colored_polygon(house, color)
		house.append(house[0])
		draw_polyline(house, Color("efffea"), 1.25, true)
		draw_rect(Rect2(-1.5, 1, 3, 5), outline)
	else:
		draw_circle(Vector2(0, -2), 6.5, outline)
		draw_circle(Vector2(0, -2), 5.5, color)
		draw_rect(Rect2(-4, 0, 8, 6), outline)
		draw_rect(Rect2(-3, 0, 6, 5), color)
		for x: float in [-2.5, 2.5]: draw_circle(Vector2(x, -2.5), 1.6, outline)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -0.5), Vector2(-1, 1.5), Vector2(1, 1.5)]), outline)
		for x: int in [-1, 1]: draw_line(Vector2(x, 3), Vector2(x, 5), outline, 1.0)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if game == null or not game.started: return
	draw_style_box(game._style(Color(0.035,0.075,0.085,0.85), Color("52665d"), 10), Rect2(Vector2.ZERO,size))
	var font: Font = ThemeDB.fallback_font
	var title: String = (str(game.world.get("name", "Map")) if expanded else "Map") + ("  −" if expanded else "  +")
	while font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > size.x - 24:
		title = title.substr(0, title.length()-4) + "… −"
	draw_string(font, Vector2(12,27), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, game.TEXT)
	if not expanded: return
	draw_rect(PLOT, Color(0.025,0.05,0.06,0.48))
	for dy: int in range(-26,27):
		for dx: int in range(-26,27):
			var tile: Vector2i = game.player_tile + Vector2i(dx,dy)
			if tile.x < 0 or tile.y < 0 or tile.x >= int(game.world.get("width",0)) or tile.y >= int(game.world.get("height",0)): continue
			_cell(tile, tile_kind(tile))
	if game.online_mode:
		for peer: Dictionary in game.online.players:
			if int(peer.get("player_id",-1)) == int(game.online.player.get("player_id",-2)): continue
			_cell(Vector2i(int(peer.x),int(peer.y)), 4, 1.0)
		for npc: Dictionary in game.online.npcs:
			var tile: Vector2i = Vector2i(int(npc.x),int(npc.y))
			if npc_kind(npc) == 5: _marker(tile, ENEMY_COLOR)
			else: _cell(tile, 8, 1.0)
	elif game.enemy_health > 0:
		_marker(game.enemy_tile, ENEMY_COLOR)
	_marker(game.player_tile, SELF_COLOR, true)
