extends SceneTree
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func opaque_point(labels: Node, key: String) -> Vector2:
	for actor: Dictionary in labels._actors():
		if actor.key!=key:continue
		for part: Dictionary in labels._frame_parts(actor):
			var image: Image=labels._image(str(part.path));var r: Array=part.region
			if image==null:continue
			for y: int in range(int(r[3])/3,int(r[3])*2/3):
				for x: int in range(int(r[2])/3,int(r[2])*2/3):
					if image.get_pixel(int(r[0])+x,int(r[1])+y).a>.9:return labels._part_rect(part,actor.pose.position).position+Vector2(x+.5,y+.5)/maxf(1,float(part.get("pixel_scale",1)))
	return Vector2.INF
func run() -> void:
	root.size=Vector2i(1280,720)
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop()
	game.started=true;game.online_mode=true;game.menu.hide();game.welcome.hide();game.online.panel.hide()
	for child: Node in game.hud_root.get_children():
		if child is Control and child!=game.nameplates:child.hide();child.set_process(false)
	var online: Node=game.online;online.active=true;online.player={"player_id":100,"name":"Self","gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,0,0,0]}
	var labels: Node=game.nameplates;labels.set_process(false);labels.set_process_input(false);labels.hovering=false
	game.player_world=game.tile_position(Vector2i(20,20))
	var crow: Dictionary={"id":1,"index":1,"x":40,"y":40,"direction":0}
	online.npcs.assign([crow]);game.camera.position=game.tile_position(Vector2i(40,40));game.camera.force_update_scroll()
	labels.sync();check(labels.entries.is_empty(),"Classic idle world has no permanent NPC/player names")
	var point: Vector2=opaque_point(labels,"npc:1")
	check(point.is_finite(),"Crow has a real opaque inspection point")
	labels.inspect_world(point);labels.sync()
	check(labels.entries.size()==1 and labels.entries[0].text=="Crow","Tap reveals only the inspected crow")
	var before: Array=game.route.duplicate();var armed: int=game.skills_ui.armed
	labels.inspect_world(point)
	check(game.route==before and game.skills_ui.armed==armed,"Inspecting a name does not change movement or armed spells")
	var actor: Dictionary=labels._actors()[0];var part: Dictionary=labels._frame_parts(actor)[0]
	labels.inspect_world(labels._part_rect(part,actor.pose.position).position+Vector2(.1,.1));labels.sync()
	check(labels.entries.is_empty(),"Transparent sprite padding does not reveal a name")
	labels.inspect_world(point);labels.inspected_until=Time.get_ticks_msec()-1;labels.sync()
	check(labels.entries.is_empty(),"Mobile inspection expires without a permanently stuck name")
	var motion: InputEventMouseMotion=InputEventMouseMotion.new();motion.position=game.get_global_transform_with_canvas()*point
	labels._input(motion);labels.sync()
	check(labels.entries.size()==1 and labels.entries[0].key=="npc:1","Desktop hover reveals the pointed-to name")
	var synthetic: InputEventMouseMotion=InputEventMouseMotion.new();synthetic.device=InputEvent.DEVICE_ID_EMULATION;synthetic.position=Vector2.ZERO
	labels._input(synthetic);labels.sync();check(labels.entries.size()==1,"Synthetic motion does not move the desktop hover target")
	motion.position=Vector2(1200,600);labels._input(motion);labels.sync();check(labels.entries.is_empty(),"Moving pointer off actor removes hover name")
	labels.inspect_world(point);online.chat_bubbles[-1]={"text":"Hello","until":Time.get_ticks_msec()+10000};labels.sync()
	check(labels.entries.is_empty(),"NPC speech suppresses its normal inspection name")
	online.chat_bubbles.clear();online.spell_labels[-1]={"text":"Spell","until":Time.get_ticks_msec()+10000};labels.sync()
	check(labels.entries.is_empty(),"Spell shouts suppress the normal name")
	online.spell_labels.clear();online.npc_health[1]={"percent":50,"until":Time.get_ticks_msec()+10000};labels.sync()
	check(labels.entries.size()==1 and labels.entries[0].text.is_empty() and labels.entries[0].health==.5,"Combat HP replaces the normal name")
	online.npc_health.clear();labels.inspect_world(point);game.world["id"]=int(game.world.get("id",0))+1;labels.sync()
	check(labels.entries.is_empty(),"Map transition cannot transfer inspection to a reused NPC index")
	for graphic: Dictionary in game.manifest.characters.npcs.values():
		var height: float=float(graphic.render_metadata.name_label_offset)
		if graphic.has("transparent_poses"):continue
		for direction: String in ["south","west","north","east"]:
			check(game.online.npc_name_layout(graphic,direction,false).classic_top==Vector2(0,-32-height),"Classic NPC name metadata is stable in every direction")
	# Self inspection uses the same flow, and speech takes precedence.
	online.npcs.clear();game.camera.position=game.player_world;game.camera.force_update_scroll()
	labels.inspect_world(opaque_point(labels,"player:100"));labels.sync()
	check(labels.entries.size()==1 and labels.entries[0].text=="Self","Own character can be inspected as in the reference client")
	online.chat_bubbles[100]={"text":"Hello","until":Time.get_ticks_msec()+10000};labels.sync()
	check(labels.entries.is_empty(),"Player speech suppresses its normal name")
	online.chat_bubbles.clear();game.menu.show();labels.sync()
	check(labels.entries.is_empty() and labels.inspected_key.is_empty(),"Modal dialogs clear phone inspection")
	game.menu.hide();online.active=false;labels.sync();check(labels.entries.is_empty(),"Disconnect clears all labels")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"classic_hover_and_metadata":true,"mobile_tap_inspection":true,"combat_and_speech_priority":true,"transparent_pixel_hit_test":true}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("CLASSIC NAME INSPECTION: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
