extends RefCounted
## Original drunk emote and confirmed soda timer; original chat slur lives in gateway.
const SOCIAL_SIZE: float = 50.0
const SOCIAL_BOTTOM: float = -80.0
const FRAME_MSEC: int = 240
const ENHANCED_PATH: String = "res://content/gfx/emotes_enhanced.png"
const ORIGINAL_PATH: String = "res://content/gfx/002_00038.png"
const SOCIAL_SETS: Dictionary = {1:0, 2:1, 3:1, 4:4, 5:3, 6:2, 7:6, 8:7, 9:9, 10:5, 14:13}
static var animation_atlas: Texture2D
static var enhanced: bool = false
static var frame_textures: Dictionary = {}

static func frame_index(elapsed: int) -> int:
	return clampi(elapsed / FRAME_MSEC, 0, 3)

static func frame_texture(set_index: int, frame: int) -> Texture2D:
	if set_index < 0 or set_index >= 15: return null
	if animation_atlas == null:
		enhanced = ResourceLoader.exists(ENHANCED_PATH)
		var path: String = ENHANCED_PATH if enhanced else ORIGINAL_PATH
		if not ResourceLoader.exists(path): return null
		var filtered: CanvasTexture = CanvasTexture.new()
		filtered.diffuse_texture = load(path) as Texture2D
		filtered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		animation_atlas = filtered
	var key: int = set_index * 4 + clampi(frame, 0, 3)
	if not frame_textures.has(key):
		var texture: AtlasTexture = AtlasTexture.new()
		texture.atlas = animation_atlas
		if enhanced:
			var cell: float = animation_atlas.get_width() / 4.0
			texture.region = Rect2((key % 4) * cell, set_index * cell, cell, cell)
		else:
			var cell: float = animation_atlas.get_width() / 60.0
			texture.region = Rect2(key * cell, 0, cell, animation_atlas.get_height())
		texture.filter_clip = true
		frame_textures[key] = texture
	return frame_textures[key] as Texture2D

static func social_texture(ident: int, frame: int = 0) -> Texture2D:
	if ident not in SOCIAL_SETS: return null
	return frame_texture(social_set(ident), frame)

static func social_rect(at: Vector2, _elapsed: int = 0, head_shift: float = 0.0) -> Rect2:
	return Rect2(at + Vector2(-SOCIAL_SIZE / 2.0, SOCIAL_BOTTOM + head_shift - SOCIAL_SIZE), Vector2.ONE * SOCIAL_SIZE)

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

static func sitting_head_shift(sitting: int, gender: int, direction: int) -> float:
	if sitting<=0:return 0.0
	var back: bool=direction in [1,2]
	var shift: int=(11+gender if back else 9+gender)*(2 if sitting==2 else 1)
	return float(shift-1 if sitting==2 and back else shift)

func posture_offset(pid: int) -> float:
	var record: Dictionary={}
	if pid==int(game.online.player.get("player_id",-1)):record=game.online.player
	else:
		for peer: Dictionary in game.online.players:
			if int(peer.get("player_id",-1))==pid:record=peer;break
	return sitting_head_shift(int(record.get("sitting",0)),int(record.get("gender",1)),int(record.get("direction",0)))

func draw() -> void:
	for key: Variant in social_emotes.keys():
		var row: Dictionary = social_emotes[key]
		if Time.get_ticks_msec() - int(row.at) >= 960: social_emotes.erase(key); continue
		var at: Vector2 = game.online.player_visual_position(int(key))
		if at.is_finite():
			var texture: Texture2D = social_texture(int(row.id), frame_index(Time.get_ticks_msec() - int(row.at)))
			if texture != null: game.draw_texture_rect(texture, social_rect(at, Time.get_ticks_msec() - int(row.at),posture_offset(int(key))), false)
	_draw_emotes(emotes,int((game.manifest.get("drinks",{}) as Dictionary).get("drunk_set",10)),0.0)
	_draw_emotes(music_emotes,14,24.0)

func _draw_emotes(entries: Dictionary, set_index: int, horizontal: float) -> void:
	var now: int = Time.get_ticks_msec()
	for key: Variant in entries.keys():
		var elapsed: int = now - int(entries[key])
		if elapsed >= 960:
			entries.erase(key)
			continue
		var at: Vector2 = game.online.player_visual_position(int(key))
		if not at.is_finite(): continue
		var texture: Texture2D = frame_texture(set_index, frame_index(elapsed))
		if texture != null: game.draw_texture_rect(texture, social_rect(at + Vector2(horizontal, 0),0,posture_offset(int(key))), false)
