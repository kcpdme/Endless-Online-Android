extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()});return calls.size()
var failed: bool = false
var checks: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1544,720)
	var game: Node = load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.music.stop();game.welcome.hide();game.online_mode = true;game.started = true;game.set_process(false)
	var c: Node = game.online;c.set_process(false);c.session.queue_free()
	var wire: Capture = Capture.new();c.add_child(wire);wire.set_process(false);c.session = wire;c.active = true;c.streaming = true
	c.player = {"name":"fixture","player_id":100,"character_id":100,"map_id":5,"x":40,"y":40,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"equipment":{},"spells":[{"id":5,"level":0}],"stats":{"admin":4}}
	game.player_tile = Vector2i(40,40);game.player_world = game.tile_position(game.player_tile);game.facing = "east"
	for id: int in [15,16,57,166]:
		var npc: Dictionary = {"id":id,"index":1,"x":41,"y":40,"direction":0};c.npcs.assign([npc]);c.npc_health.clear()
		check(not c.is_combat_npc(npc),"Original service/quest/guard must be noncombat")
		wire.calls.clear();c.request_attack()
		check(not c.npc_health.has(1),"Weapon swing cannot display a combat bar on a service NPC")
		wire.calls.clear();game.skills_ui.armed = 5;game.skills_ui.target(Vector2i(41,40))
		check(wire.calls.is_empty() and game.skills_ui.casting.is_empty(),"Clicking a service NPC cannot send a damaging spell")
		game.skills_ui.cast(5,"npc",1)
		check(wire.calls.is_empty() and game.skills_ui.casting.is_empty(),"Direct cast path must also reject service NPCs")
	check(int(c.catalog.npcs["123"].hp) == 13000 and c.is_combat_npc({"id":123}),"Original throne-room King is a13000HP passive combatant")
	check(int(c.catalog.npcs["227"].type) == 1,"Original Vitaman is passive, not aggressive")
	var king: Dictionary = {"id":123,"index":3,"x":41,"y":40,"direction":0};c.npcs.assign([king]);wire.calls.clear()
	game.skills_ui.armed = 5;game.skills_ui.target(Vector2i(41,40))
	check(wire.calls.any(func(call: Dictionary) -> bool: return call.op == "spell_cast"),"King must accept a damaging skill target instead of opening missing quest52")
	game.skills_ui.cancel_cast()
	var rat: Dictionary = {"id":2,"index":2,"x":41,"y":40,"direction":0};c.npcs.assign([rat]);wire.calls.clear()
	check(c.is_combat_npc(rat),"Passive rats remain valid monsters")
	game.skills_ui.armed = 5;game.skills_ui.target(Vector2i(41,40))
	check(wire.calls.any(func(call: Dictionary) -> bool: return call.op == "spell_cast"),"Monster spells must still send normally")
	game.skills_ui.cancel_cast()
	var old: int = game.chat_ui.messages.size()
	var heard: Array[int] = [];game.sfx.sound_played.connect(func(id: int,_context: String) -> void: heard.append(id))
	c._process_events([{"kind":"arena_start","players":2,"message":"2 players entered the arena."},{"kind":"arena_kill","message":"Other was eliminated by Hero."},{"kind":"arena_win","message":"Hero wins the arena!"}])
	check(game.chat_ui.messages.size() == old+3,"Original arena start/elimination/winner messages must appear in chat")
	check(heard.has(52),"Arena winner uses original victory sound52")
	check(c.is_combat_npc({"id":151}),"Original Princess151 remains the supplied passive combatant")
	check(game.load_map(281),"Castle throne room must load")
	c.npcs.clear()
	for spawn: Dictionary in game.world.npcs:
		c.npcs.append({"id":int(spawn.id),"index":c.npcs.size()+1,"x":int(spawn.x),"y":int(spawn.y),"direction":0})
	check(c.npcs.any(func(n: Dictionary) -> bool: return int(n.id) == 151),"Restored castle metadata must include Princess")
	var graphic: Dictionary = ((game.manifest.characters as Dictionary).npcs as Dictionary).get("115",{}) as Dictionary
	check(not graphic.is_empty() and graphic.source_member == "gfx/gfx021.egf","Princess must use ORIGINAL sprites, not a missing-art dot")
	for direction: String in ["south","east","north","west"]:
		var frame: Dictionary = game._frame(graphic,direction,"idle")
		check(not frame.is_empty() and game._texture(str(frame.get("path", ""))) != null,"Every Princess facing must load a real imported texture")
	game.player_tile = Vector2i(8,10);game.player_world = game.tile_position(game.player_tile);game.camera.position = game.tile_position(Vector2i(8,6));game.queue_redraw()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://../work/v39-princess-castle.png")
	game.started = false;game.queue_free();await process_frame
	if not failed: print("CASTLE V39 PASS: ",checks," checks")
	quit(1 if failed else 0)
