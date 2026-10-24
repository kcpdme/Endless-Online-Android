extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.online.panel.hide()
	game.music.stop()
	game.online_mode = true
	game.started = true
	game.load_map(6)
	var c: Node = game.online
	c.set_process(false)
	c.session.queue_free()
	var wire: Capture = Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session = wire
	c.active = true
	c.streaming = true
	c.player = {"name":"fixture","player_id":100,"character_id":100,"map_id":6,"x":9,"y":3,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"inventory":[]}
	game.player_tile = Vector2i(9,3)
	game.player_world = game.tile_position(game.player_tile)
	game.camera.position = game.player_world
	c.npcs.assign([{"id":166,"index":7,"x":9,"y":1,"direction":0}])
	c.map_click(Vector2i(9,1),"npc")
	c._process_interaction()
	check(wire.calls.back().op == "quest_open" and wire.calls.back().fields.npc_index == 7,"Wise Man tap must use native Quest request without walking behind the counter")
	var state: Dictionary = {"npc_index":7,"npc_id":166,"map_id":6,"x":9,"y":1,"vendor_id":4,"quest_id":4,"session_id":0,"dialog_id":0,"quests":[{"id":4,"name":"Karma Quest (rep)"}],"pages":["Hellow stranger, what can i do for you"],"links":[{"id":1,"text":"Karma menu"},{"id":2,"text":"Class menu"}]}
	c._on_message({"op":"quest_open","ok":true,"data":{"quest_dialog":state}})
	var ui: RefCounted = game.quest_ui
	check(ui.panel.visible and game._modal_open() and ui.title.text == "Wise Man","Native Wise Man dialogue must be visible and protect touch input")
	check(ui.body.get_child_count() == 3,"Native root links must both be available")
	(ui.body.get_child(2) as Button).pressed.emit()
	check(wire.calls.back().op == "quest_reply" and wire.calls.back().fields.action == 2 and not ui.panel.visible,"Class menu chooses only native link2 and closes the old page")
	state.pages = ["This is a temporary menu to set your class thru the quest-engine, will be better later on."]
	state.links = [{"id":1,"text":"Make me Priest"},{"id":2,"text":"Make me Magician"},{"id":3,"text":"Make me Rogue"},{"id":4,"text":"Make me Archer"},{"id":5,"text":"Make me Warrior"}]
	c._apply_snapshot({"quest_dialog":state})
	check(ui.body.get_child_count() == 6,"All five original class options must exist in the scrollable list")
	if DisplayServer.get_name() != "headless":
		await process_frame
		ui.scroll.scroll_vertical = int(ui.scroll.get_v_scroll_bar().max_value)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../work/v35-wiseman-class.png")
	(ui.body.get_child(5) as Button).pressed.emit()
	check(wire.calls.back().fields.action == 5,"Warrior uses offered link5 without a client class mutation")
	check(int((c.player.get("stats",{}) as Dictionary).get("class_id",0)) == 0,"Class must not change before a native acknowledgement")
	c._apply_snapshot({"quest_dialog":state})
	var old_count: int = wire.calls.size()
	game._handle_back()
	check(wire.calls.size() == old_count + 1 and wire.calls.back().op == "quest_close" and not ui.panel.visible,"Back must cancel a dialogue without selecting a reward or option")
	# Music runs from original map headers; exercise every control through real playback.
	var music: Node = preload("res://scripts/map_music.gd").new()
	root.add_child(music)
	var tracks: Dictionary = {"1":{"path":"res://content/audio/music/mfx001.ogg"},"2":{"path":"res://content/audio/music/mfx002.ogg"}}
	music.configure({"tracks":tracks}, "")
	music.enter_map({"id":1,"music_id":1,"music_control":0})
	check(music.player.playing and music.active_id == 1 and not music.repeating,"Music control0 must start the original track once")
	await process_frame
	music.player.seek(1.0)
	await process_frame
	music.enter_map({"id":2,"music_id":1,"music_control":3})
	check(music.player.get_playback_position() >= .8 and music.repeating,"Same-track repeat preserves playback when moving between maps")
	music.enter_map({"id":3,"music_id":2,"music_control":4})
	await process_frame
	check(music.active_id == 2 and music.player.playing and music.repeating and music.player.get_playback_position() < .5,"Control4 interrupts and repeats the new track")
	music.enter_map({"id":4,"music_id":1,"music_control":2})
	check(music.active_id == 2 and music.pending_id == 1 and not music.repeating,"Control2 finishes the current iteration before the next track")
	music.player.stop()
	music._finished()
	check(music.active_id == 1 and not music.repeating,"Deferred play-once starts after current completion")
	music.enter_map({"id":5,"music_id":2,"music_control":5})
	music.player.stop()
	music._finished()
	check(music.active_id == 2 and music.repeating,"Deferred repeat starts after current completion")
	music.enter_map({"id":6,"music_id":1,"music_control":1})
	check(music.active_id == 1 and not music.repeating,"Control1 interrupts once")
	music.enter_map({"id":7,"music_id":1,"music_control":6})
	check(not music.player.playing and music.active_id == 0,"Control6 silences the map")
	music.enter_map({"id":8,"music_id":0,"music_control":0})
	check(not music.player.playing,"Original silent maps must stay silent")
	music.enter_map({"id":9,"music_id":1,"music_control":3})
	music.set_enabled(false)
	check(not music.player.playing,"Music switch must stop playback")
	music.set_enabled(true)
	music.set_volume(.3)
	check(music.player.playing and is_equal_approx(music.player.volume_linear,.3),"Music switch and volume resume the selected map")
	music._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(music.player.stream_paused,"Backgrounding Android pauses music")
	music._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not music.player.stream_paused,"Returning to Android resumes music")
	music.queue_free()
	print("MUSIC QUESTS ","FAIL" if failed else "PASS",": original Wise Man pages, five class options, safe links/cancel; all seven music controls, silent maps, volume and pause")
	game.started = false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
