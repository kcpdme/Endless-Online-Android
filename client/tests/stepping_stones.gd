extends SceneTree
class PlayerProbe extends "res://scripts/main.gd":
	var drawn: Dictionary={}
	func _draw() -> void:
		if online!=null and started:_draw_player()
	func _draw_character_frame(character: Dictionary, at: Vector2, direction: String, state: String, tint: Color=Color.WHITE, phase: float=-1.0) -> bool:
		drawn={"position":at,"state":state,"phase":phase,"frame":_frame(character,direction,state,phase)}
		return super._draw_character_frame(character,at,direction,state,tint,phase)
class SessionCapture extends "res://scripts/online_session.gd":
	var accepted: bool=true
	func request(_operation: String, _fields: Dictionary={}) -> int:return 1 if accepted else -1
var failed: bool=false
var checks: int=0
var played: Array[int]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(why)
func capture(view: SubViewport, game: Node) -> Image:
	game.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	var view: SubViewport=SubViewport.new();view.size=Vector2i(400,300);view.transparent_bg=true;view.world_2d=World2D.new();view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game: PlayerProbe=PlayerProbe.new();view.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop();game.menu.hide();game.welcome.hide();game.online.panel.hide();game.hud_root.hide()
	game.started=true;game.online_mode=true;game.online.active=true;game.online.streaming=true;game.camera.zoom=Vector2.ONE
	game.online.player={"player_id":100,"name":"Self","gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,44,10,73]}
	var helper: RefCounted=game.stepping_stones
	var origin: Vector2i=Vector2i(12,15);var target: Vector2i=Vector2i(13,15)
	game.tile_specs={target:29};game.step_origin_tile=origin;game.player_tile=target;game.player_world=game.tile_position(origin).lerp(game.tile_position(target),.5);game.camera.position=game.player_world-Vector2(0,28)
	for pair: Vector2 in [Vector2(0,0),Vector2(.2,-8),Vector2(.4,-16),Vector2(.6,-16),Vector2(.8,-8),Vector2(1,0)]:check(is_equal_approx(helper.lift(pair.x),pair.y),"Reference hop key height "+str(pair))
	check(helper.crosses(game.tile_specs,origin,target) and helper.crosses(game.tile_specs,target,origin),"Hop both onto and off a stepping stone")
	check(not helper.crosses(game.tile_specs,origin,target+Vector2i(20,0)),"Warp or missed multi-tile update is not a hop")
	check(not helper.crosses({origin:30,target:30},origin,target),"Water is not a stepping stone")
	var frames: Array[Dictionary]=[]
	for direction: String in ["south","west","north","east"]:
		game.facing=direction;game.moving=true;game.step_progress=0;game.animation_clock=0
		var baseline: Image=await capture(view,game)
		var first: Dictionary=game.drawn.frame
		game.animation_clock=.31
		for progress: float in [.2,.4,.5,.6,.8]:
			game.step_progress=progress
			var image: Image=await capture(view,game)
			check(game.drawn.frame==first,"All clothes/hair/weapon layers hold first walk frame: "+direction)
			check(is_equal_approx(game.drawn.position.y-game.player_world.y,helper.lift(progress)),"Actual local draw uses the hop offset")
			check(absi(image.get_used_rect().position.y-baseline.get_used_rect().position.y-roundi(helper.lift(progress)))<=1,"Rendered character rises by the reference height")
			check(game.local_render_pose().ground_position==game.player_world,"Hop never moves the ground/camera/network position")
			if direction=="south" and progress==.5:image.save_png("res://../work/stepping-stones-peak.png")
		game.tile_specs.clear();game.step_progress=.5
		await capture(view,game)
		check(game.drawn.frame!=first,"Ordinary walking still advances equipment frames")
		game.tile_specs[target]=29;game.moving=false;await capture(view,game)
		check(not game.local_render_pose().hopping and game.drawn.position==game.player_world,"Standing/landing on a rock is not suspended in air")
		frames.append({"direction":direction,"peak_lift":16,"equipment_layers_move_together":true})
	# Remote pose must use the displayed segment, not the latest queued destination.
	var c: Node=game.online;var now: float=Time.get_ticks_msec()/1000.0
	var a: Vector2i=Vector2i(10,10);var b: Vector2i=Vector2i(11,10);var d: Vector2i=Vector2i(12,10)
	game.tile_specs={d:29};var peer: Dictionary={"player_id":101,"x":d.x,"y":d.y,"direction":3}
	c.remote_motion["player:101"]={"to":game.tile_position(d),"tile":d,"walk_start":now-.21,"steps":[{"from":game.tile_position(a),"to":game.tile_position(b),"start":now-.21,"direction":"east"},{"from":game.tile_position(b),"to":game.tile_position(d),"start":now+.21,"direction":"east"}]}
	c.render_pose_cache.clear();var pose: Dictionary=c.entity_render_pose("online_player",peer)
	check(not pose.hopping and pose.from_tile==a and pose.to_tile==b,"Future rock destination cannot trigger the current normal segment")
	c.remote_motion["player:101"].steps[0].start=now-.63;c.remote_motion["player:101"].steps[1].start=now-.21;c.render_pose_cache.clear();pose=c.entity_render_pose("online_player",peer)
	check(pose.hopping and pose.from_tile==b and pose.to_tile==d and pose.phase==0,"Queued observer step hops when that segment is displayed")
	check(is_equal_approx(pose.position.y-pose.ground_position.y,helper.lift(pose.step_progress)),"Observer shares one sample for movement, lift and frame")
	check(c.entity_render_pose("online_player",peer)==pose,"Repeated draws reuse the same peer pose")
	c.remote_motion["npc:1"]=c.remote_motion["player:101"].duplicate(true);c.render_pose_cache.clear()
	var npc: Dictionary=c.entity_render_pose("online_npc",{"index":1,"id":1,"x":d.x,"y":d.y,"direction":3})
	check(not npc.has("hopping"),"NPC animation is unchanged on Jump tiles")
	# Sound occurs on a new accepted walk, never while drawing or replaying ACKs.
	c.session.queue_free();var session: SessionCapture=SessionCapture.new();c.add_child(session);session.set_process(false);c.session=session
	game.world={"id":7,"width":50,"height":50,"warps":[]};game.server_blocked.clear();c.npcs.clear();c.players.clear();c.pending_inputs.clear();c.remote_motion.clear();c.render_pose_cache.clear()
	game.tile_specs={target:29};game.player_tile=origin;game.player_world=game.tile_position(origin);game.moving=false
	game.sfx.settings_path="";game.sfx.set_enabled(true);game.sfx.sound_played.connect(func(id: int, _context: String) -> void:played.append(id))
	c.request_step(Vector2i.RIGHT)
	check(game.moving and played==[41],"Accepted local rock step plays original JumpStone SFX 41 once")
	for i: int in range(12):game.local_render_pose()
	check(played==[41],"Rendering cannot repeat the jump sound")
	game._advance_walk(c.MOVE_SECONDS);c.pending_inputs.clear();played.clear()
	game.player_tile=origin;game.player_world=game.tile_position(origin);session.accepted=false;c.request_step(Vector2i.RIGHT)
	check(not game.moving and played.is_empty(),"Unsent walk has no false hop or sound")
	session.accepted=true;game.server_blocked[target]=true;c.request_step(Vector2i.RIGHT)
	check(not game.moving and played.is_empty(),"Blocked stepping-stone move stays grounded and silent")
	game.server_blocked.clear();c._track_entities("player",c._dict_array([{"player_id":101,"x":12,"y":15,"direction":3}]),"player_id")
	check(played.is_empty(),"New nearby actor does not fabricate a jump sound")
	for i: int in range(3):c._track_entities("player",c._dict_array([{"player_id":101,"x":13,"y":15,"direction":3}]),"player_id")
	check(played==[41],"A nearby player's accepted step sounds once despite duplicate snapshots")
	c._track_entities("player",c._dict_array([{"player_id":101,"x":33,"y":15,"direction":3}]),"player_id")
	check(played==[41],"Peer warp is silent rather than inventing a rock hop")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"pixel_render_test":DisplayServer.get_name()!="headless","four_directions":frames,"queued_peer_segments":true,"native_sound_id":41,"ground_position_preserved":true}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("STEPPING STONES: ",JSON.stringify(report));game.started=false;view.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
