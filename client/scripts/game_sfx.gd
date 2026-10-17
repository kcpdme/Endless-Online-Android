extends Node
## Original EO sound IDs/weapon/effect mappings; bounded overlapping PCM voices.
signal sound_played(id: int, context: String)
const MAX_VOICES: int = 24
var game: Node
var bank: Dictionary = {}
var mapping: Dictionary = {}
var cache: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var ambient: AudioStreamPlayer
var ambient_id: int = 0
var enabled: bool = true
var volume: float = .75
var paused: bool = false
var pending: Array[Dictionary] = []
var settings_path: String = "user://sound_settings.cfg"
var next_voice: int = 0
func configure(owner_game: Node, data: Dictionary, path: String = "user://sound_settings.cfg") -> void:
	game = owner_game;bank = data.get("sfx", {}) as Dictionary;mapping = data.get("sfx_config", {}) as Dictionary
	settings_path = path
	var settings: ConfigFile = ConfigFile.new()
	if not path.is_empty() and settings.load(path) == OK:
		enabled = bool(settings.get_value("sound", "enabled", true))
		volume = clampf(float(settings.get_value("sound", "volume", .75)),0,1)
	for i: int in range(MAX_VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player);voices.append(player)
	ambient = AudioStreamPlayer.new();add_child(ambient)
func _save() -> void:
	if settings_path.is_empty(): return
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("sound","enabled",enabled);settings.set_value("sound","volume",volume);settings.save(settings_path)
func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled: stop(false)
	elif ambient_id > 0: _ambient(ambient_id)
	_save()
func set_volume(value: float) -> void:
	volume = clampf(value,0,1)
	for player: AudioStreamPlayer in voices: player.volume_linear = volume
	if ambient != null: ambient.volume_linear = volume * .5
	_save()
func stream(ident: int) -> AudioStream:
	if cache.has(ident): return cache[ident] as AudioStream
	var path: String = str((bank.get(str(ident),{}) as Dictionary).get("path",""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var audio: AudioStream = load(path) as AudioStream
	if audio != null: cache[ident] = audio
	return audio
func play_named(key: String, context: String = "action") -> void:
	play_id(int((mapping.get("names",{}) as Dictionary).get(key,0)),context)
func play_id(ident: int, context: String = "action") -> void:
	if not enabled or paused or ident <= 0 or voices.is_empty(): return
	var audio: AudioStream = stream(ident)
	if audio == null: return
	var voice: AudioStreamPlayer = null
	for candidate: AudioStreamPlayer in voices:
		if not candidate.playing: voice = candidate;break
	if voice == null:
		voice = voices[next_voice];next_voice = (next_voice + 1) % voices.size()
	voice.stop();voice.stream = audio;voice.volume_linear = volume;voice.play()
	sound_played.emit(ident,context)
func weapon(graphic: int) -> void:
	if not enabled or paused: return
	var values: Array = (mapping.get("weapons",{}) as Dictionary).get(str(graphic),[]) as Array
	if values.is_empty(): values = [int((mapping.get("names",{}) as Dictionary).get("PunchAttack",10))]
	# Original CharacterAnimator sounds ActualAttackFrame2, two120ms frames in.
	pending.append({"id":int(values.pick_random()),"at":Time.get_ticks_msec()+240,"context":"weapon"})
func effect(graphic: int) -> void:
	play_id(int((mapping.get("effects",{}) as Dictionary).get(str(graphic),0)),"effect:%d" % graphic)
func enter_map(world: Dictionary) -> void:
	var ident: int = int(world.get("ambient_sound",0))
	if ident != ambient_id:
		ambient.stop();ambient_id = ident
		if enabled and ident > 0: _ambient(ident)
func _ambient(ident: int) -> void:
	var audio: AudioStreamWAV = stream(ident) as AudioStreamWAV
	if audio == null: return
	var loop: AudioStreamWAV = audio.duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0;loop.loop_end = int(loop.get_length()*loop.mix_rate)
	ambient.stream = loop;ambient.volume_linear = volume*.5;ambient.play()
func stop(clear_ambient: bool = true) -> void:
	pending.clear()
	for player: AudioStreamPlayer in voices: player.stop()
	if ambient != null: ambient.stop()
	if clear_ambient: ambient_id = 0
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for index: int in range(pending.size()-1,-1,-1):
		if now >= int(pending[index].at):
			var sound: Dictionary = pending[index];pending.remove_at(index)
			play_id(int(sound.id),str(sound.context))
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		paused = true;pending.clear()
		for player: AudioStreamPlayer in voices: player.stop()
		if ambient != null: ambient.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		paused = false
		if ambient != null: ambient.stream_paused = false
func _exit_tree() -> void:
	stop()
	for player: AudioStreamPlayer in voices: player.stream = null
	if ambient != null: ambient.stream = null
