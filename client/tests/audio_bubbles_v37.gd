extends SceneTree
var game: Node
var played: Array[Dictionary] = []
var checks: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1544,720)
	game = load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.music.stop();game.sfx.stop();game.sfx.settings_path = ""
	game.sfx.set_enabled(true);game.welcome.hide();game.online_mode = true;game.started = true
	var c: Node = game.online;c.active = true;c.streaming = true
	c.player = {"player_id":100,"name":"fixture","x":40,"y":40,"map_id":5,"hp":100,"maxhp":100,"tp":100,"maxtp":100,"equipment_graphics":[0,0,0,0,0,0,0,0,4]}
	game.player_tile = Vector2i(40,40);game.player_world = game.tile_position(game.player_tile);game.camera.position = game.player_world
	# Both new and reused bubbles must have their final rectangle BEFORE first draw.
	for message: String in ["Hi!", "A longer nearby message that wraps over more than one line to see this bubble jumping", "LongWordWithoutSpacesABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ", "First line\nSecond line\nThird line"]:
		c.show_speech({"channel":"local","outgoing":true,"message":message})
		var p: Panel = game.speech_layer.bubbles[100] as Panel
		var initial: Rect2 = p.get_rect()
		check(p.size.y < 200, "First-frame bubble must not explode to thousands of pixels")
		for frame: int in range(3):
			await process_frame
			if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
			check(p.get_rect().is_equal_approx(initial), "Bubble must never jump while deferred text layout settles")
			check(p.size.y >= (p.get_node("Message") as Label).size.y + 14, "All wrapped lines must fit inside padding")
	c.players.assign([{"player_id":101,"x":41,"y":40,"direction":0,"equipment_graphics":[0,0,0,0,0,0,0,0,73]}])
	c.show_speech({"channel":"local","player_id":101,"message":"Observer bubble"})
	var peer: Panel = game.speech_layer.bubbles[101] as Panel
	var before: Vector2 = peer.position
	game.camera.position += Vector2(20,0);game.speech_layer.sync()
	check(peer.position.x < before.x, "Speech must follow updated camera immediately")
	await process_frame
	check(peer.position.is_finite(), "Peer bubble must remain attached while camera updates")
	game.sfx.sound_played.connect(func(id: int, context: String) -> void: played.append({"id":id,"context":context,"at":Time.get_ticks_msec()}))
	# Exercise the real audio players, not just a metadata lookup.
	for graphic: int in [0,4,39,42,49,50,58,73]:
		played.clear();var start: int = Time.get_ticks_msec()
		game.sfx.weapon(graphic)
		check(played.is_empty(), "Weapon sound must wait for original impact frame")
		await create_timer(.15).timeout
		check(played.is_empty(), "No early weapon sound before frame2")
		await create_timer(.16).timeout
		check(played.size() == 1 and int(played[0].at)-start >= 240, "Exactly one real voice must start on original attack frame")
		check(((game.manifest.sfx_config.weapons as Dictionary)[str(graphic)] as Array).any(func(id: Variant) -> bool: return int(id) == int(played[0].id)), "Each weapon uses its original sound")
		check(game.sfx.voices.any(func(v: AudioStreamPlayer) -> bool: return v.playing and v.stream != null), "PCM must actually start playing")
	played.clear();game._play_sound("attack");await create_timer(.3).timeout
	check(played.size() == 1 and int(played[0].id) == 15,"Local equipped sword uses melee sound")
	played.clear();c._process_events([{"kind":"peer_attack","player_id":101,"direction":1}]);await create_timer(.3).timeout
	check(played.size() == 1 and int(played[0].id) == 38,"Observer hears nearby Scav Bow once")
	for pair: Vector2i in [Vector2i(1,43),Vector2i(4,31),Vector2i(5,50)]:
		played.clear()
		game.skills_ui.event({"kind":"spell_chant","spell_id":pair.x,"player_id":100,"seconds":.48})
		check(played.is_empty(), "No premature spell effect during chant")
		game.skills_ui.event({"kind":"spell_heal" if pair.x == 1 else "npc_damage","spell_id":pair.x,"player_id":100,"target_id":100,"npc_index":7,"x":40,"y":41,"hp_gain":5})
		check(played.size() == 1 and int(played[0].id) == pair.y,"Native Heal Self / Small Fire / Small Thunder must each play exact original cue once")
		game.skills_ui.tick();game.skills_ui.tick()
		check(played.size() == 1,"Effect animation ticks must not replay sound")
	played.clear();game.skills_ui.event({"kind":"spell_failed","message":"Target moved"});game.skills_ui.event({"kind":"spell_cancelled"})
	check(played.is_empty(),"Rejected casts have no false impact sound")
	for event: Dictionary in [{"kind":"pickup","item_id":21,"amount":1},{"kind":"equip"},{"kind":"shop_transaction","operation":"buy"},{"kind":"shop_transaction","operation":"craft"},{"kind":"sound","sound_id":50},{"kind":"potion_effect","player_id":101,"effect_id":9},{"kind":"item_used","item_type":23,"effect_id":0},{"kind":"npc_attack","npc_index":7},{"kind":"seating","player_id":100,"sitting":1},{"kind":"door_open"},{"family":33,"action":13},{"family":33.0,"action":13.0},{"family":36.0,"action":3.0}]:
		played.clear()
		if str(event.get("kind","")) == "pickup": game._play_sound("pickup")
		else: c._action_sound(event,str(event.get("kind","")))
		check(played.size() == 1,"Acknowledged action must play exactly one cue: " + str(event))
	played.clear();game.sfx.effect(12)
	check(played.is_empty(),"Original snow effect is intentionally silent")
	game.sfx.set_volume(.3);game.sfx.enter_map({"ambient_sound":64})
	check(game.sfx.ambient.playing and is_equal_approx(game.sfx.ambient.volume_linear,.15),"Ambient loop uses original map ID and half SFX volume")
	check((game.sfx.ambient.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,"Ambience must actually loop")
	game.sfx.weapon(4);game.sfx.set_enabled(false);await create_timer(.3).timeout
	check(played.is_empty() and not game.sfx.ambient.playing and game.sfx.pending.is_empty(),"Mute must cancel pending/playing voices")
	game.sfx.set_enabled(true);check(game.sfx.ambient.playing,"Unmute resumes map ambience")
	game.sfx._notification(Node.NOTIFICATION_APPLICATION_PAUSED);game.sfx.play_id(15)
	check(played.is_empty() and game.sfx.ambient.stream_paused,"Backgrounding pauses audio")
	game.sfx._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	for i: int in range(100):game.sfx.play_id(15)
	check(game.sfx.voices.size() == 24,"Audio voices stay bounded under many simultaneous actions")
	game.sfx.stop();game.started = false;game.queue_free();await process_frame
	print("AUDIO BUBBLES V37 PASS: ", checks, " checks")
	quit()
