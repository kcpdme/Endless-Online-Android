extends RefCounted
## Original drunk emote and confirmed soda timer; original chat slur lives in gateway.
const SOCIAL_SIZE: float = 40.0
const SOCIAL_BOTTOM: float = -96.0
const SOCIAL_SETS: Dictionary = {1:0, 2:1, 3:1, 4:4, 5:3, 6:2, 7:6, 8:7, 9:9, 10:5, 14:13}
static func social_texture(ident: int) -> Texture2D:
	if ident not in SOCIAL_SETS: return null
	return load("res://assets/emotes/%d.svg" % ident) as Texture2D

static func social_rect(at: Vector2, elapsed: int) -> Rect2:
	var pop: float = sin(clampf(float(elapsed) / 960.0, 0.0, 1.0) * PI) * 3.0
	return Rect2(at + Vector2(-SOCIAL_SIZE / 2.0, SOCIAL_BOTTOM - SOCIAL_SIZE - pop), Vector2.ONE * SOCIAL_SIZE)

static func social_set(ident: int) -> int:
	return int(SOCIAL_SETS.get(ident, ident - 1))

var game: Node
var until: int = 0
var emotes: Dictionary = {}
var music_emotes: Dictionary = {}
var social_emotes: Dictionary = {}

func drunk() -> bool:
	return Time.get_ticks_msec() < until

func receive(player: Dictionary) -> void:
	if player.has("drunk_seconds"):
		until = Time.get_ticks_msec() + int(float(player.drunk_seconds) * 1000)

func clear() -> void:
	until = 0
	emotes.clear()
	music_emotes.clear()
	social_emotes.clear()

func event(data: Dictionary) -> void:
	var kind: String = str(data.get("kind", ""))
	if kind == "item_used" and int(data.get("item_type", 0)) == 22 and int(data.get("consumed", 0)) > 0:
		until = Time.get_ticks_msec() + int(float(data.get("drunk_seconds", 0)) * 1000)
		game._toast("Fairy Soda · feeling dizzy")
	elif kind == "drunk_ended": until = 0
	elif kind == "player_emote" and int(data.get("emote", 0)) == 11:
		emotes[int(data.player_id)] = Time.get_ticks_msec()
	elif kind == "player_emote" and int(data.get("emote",0)) == 15:
		music_emotes[int(data.player_id)] = Time.get_ticks_msec()

	elif kind == "player_emote" and (int(data.get("emote", 0)) in range(1, 11) or int(data.get("emote", 0)) == 14):
		social_emotes[int(data.player_id)] = {"id":int(data.emote), "at":Time.get_ticks_msec()}

func draw() -> void:
	for key: Variant in social_emotes.keys():
		var row: Dictionary = social_emotes[key]
		if Time.get_ticks_msec() - int(row.at) >= 960: social_emotes.erase(key); continue
		var at: Vector2 = game.online.player_visual_position(int(key))
		if at.is_finite():
			var texture: Texture2D = social_texture(int(row.id))
			if texture != null: game.draw_texture_rect(texture, social_rect(at, Time.get_ticks_msec() - int(row.at)), false)
	_draw_emotes(emotes,int((game.manifest.get("drinks",{}) as Dictionary).get("drunk_set",10)),0.0)
	_draw_emotes(music_emotes,14,24.0)

func _draw_emotes(entries: Dictionary, set_index: int, horizontal: float) -> void:
	var now: int = Time.get_ticks_msec()
	var texture: Texture2D = game._graphic(2,38)
	if texture == null: return
	var frame_width: float = float(texture.get_width())/60.0
	for key: Variant in entries.keys():
		var elapsed: int = now-int(entries[key])
		if elapsed >= 960:
			entries.erase(key)
			continue
		var at: Vector2 = game.online.player_visual_position(int(key))
		if not at.is_finite(): continue
		var frame: int = mini(3,elapsed/240)
		var region: Rect2 = Rect2((set_index*4+frame)*frame_width,0,frame_width,texture.get_height())
		game.draw_texture_rect_region(texture,Rect2(at+Vector2(horizontal-frame_width/2.0,-124),region.size),region)
