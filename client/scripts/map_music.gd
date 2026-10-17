extends Node
## Original EMF track/control rules; original MIDI rendered to portable Ogg.
var player: AudioStreamPlayer
var tracks: Dictionary = {}
var active_id: int = 0
var current_map: int = -1
var selected_id: int = 0
var selected_control: int = 6
var repeating: bool = false
var pending_id: int = 0
var pending_repeat: bool = false
var enabled: bool = true
var volume: float = 0.45
var settings_path: String = "user://audio_settings.cfg"

func configure(data: Dictionary, path: String = "user://audio_settings.cfg") -> void:
	tracks = data.get("tracks", {}) as Dictionary
	settings_path = path
	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_finished)
	var settings: ConfigFile = ConfigFile.new()
	if not path.is_empty() and settings.load(path) == OK:
		enabled = bool(settings.get_value("music", "enabled", true))
		volume = clampf(float(settings.get_value("music", "volume", 0.45)), 0.0, 1.0)
	player.volume_db = linear_to_db(maxf(volume, 0.001))
	player.volume_linear = volume

func _save() -> void:
	if settings_path.is_empty(): return
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("music", "enabled", enabled)
	settings.set_value("music", "volume", volume)
	settings.save(settings_path)

func set_enabled(value: bool) -> void:
	enabled = value
	if enabled: _apply(selected_id, selected_control)
	else: stop()
	_save()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	player.volume_linear = volume
	_save()

func title_music() -> void:
	current_map = -1
	selected_id = 1
	selected_control = 4
	_apply(1, 4)

func enter_map(world: Dictionary) -> void:
	var map_id: int = int(world.get("id", -1))
	if map_id == current_map: return
	current_map = map_id
	selected_id = int(world.get("music_id", 0))
	selected_control = int(world.get("music_control", 0))
	_apply(selected_id, selected_control)

func leave_world() -> void:
	current_map = -1
	selected_id = 0
	selected_control = 6
	stop()

func stop() -> void:
	if player != null: player.stop()
	active_id = 0
	pending_id = 0
	repeating = false

func _apply(ident: int, control: int) -> void:
	if not enabled or ident <= 0 or control == 6:
		stop()
		return
	var repeat_track: bool = control in [3, 4, 5]
	if control in [2, 5] and player.playing:
		pending_id = ident
		pending_repeat = repeat_track
		# Finish the current iteration even when the old map was looping.
		repeating = false
		return
	pending_id = 0
	repeating = repeat_track
	if player.playing and active_id == ident and control in [0, 3]: return
	_start(ident)

func _start(ident: int) -> void:
	var path: String = str((tracks.get(str(ident), {}) as Dictionary).get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		stop()
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		stop()
		return
	player.stream = stream
	active_id = ident
	player.play()

func _finished() -> void:
	if pending_id > 0:
		var next: int = pending_id
		pending_id = 0
		repeating = pending_repeat
		_start(next)
	elif repeating and enabled: _start(active_id)

func _notification(what: int) -> void:
	if player == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED: player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED: player.stream_paused = false
