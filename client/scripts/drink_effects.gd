extends RefCounted
## Original drunk emote and confirmed soda timer; original chat slur lives in gateway.
var game: Node
var until: int = 0
var emotes: Dictionary = {}

func drunk() -> bool:
	return Time.get_ticks_msec() < until

func receive(player: Dictionary) -> void:
	if player.has("drunk_seconds"):
		until = Time.get_ticks_msec() + int(float(player.drunk_seconds) * 1000)

func clear() -> void:
	until = 0
	emotes.clear()

func event(data: Dictionary) -> void:
	var kind: String = str(data.get("kind", ""))
	if kind == "item_used" and int(data.get("item_type", 0)) == 22 and int(data.get("consumed", 0)) > 0:
		until = Time.get_ticks_msec() + int(float(data.get("drunk_seconds", 0)) * 1000)
		game._toast("Fairy Soda · feeling dizzy")
	elif kind == "drunk_ended": until = 0
	elif kind == "player_emote" and int(data.get("emote", 0)) == 11:
		emotes[int(data.player_id)] = Time.get_ticks_msec()

func draw() -> void:
	var now: int = Time.get_ticks_msec()
	var meta: Dictionary = game.manifest.get("drinks", {}) as Dictionary
	var texture: Texture2D = game._graphic(2, 38)
	if texture == null: return
	var frame_width: float = float(texture.get_width()) / 60.0
	for key: Variant in emotes.keys():
		var elapsed: int = now - int(emotes[key])
		if elapsed >= 960:
			emotes.erase(key)
			continue
		var at: Vector2 = game.online.chat_bubble_position(int(key))
		if not at.is_finite(): continue
		var frame: int = mini(3, elapsed / 240)
		var region: Rect2 = Rect2((int(meta.get("drunk_set", 10)) * 4 + frame) * frame_width, 0, frame_width, texture.get_height())
		game.draw_texture_rect_region(texture, Rect2(at + Vector2(-frame_width / 2.0, -86), region.size), region)
