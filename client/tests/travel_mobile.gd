extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary]=[]
	func request(op: String,fields: Dictionary={}) -> int:
		serial+=1;calls.append({"op":op,"fields":fields.duplicate()});return serial
var checks: int=0
var failed: bool=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func run() -> void:
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.music.stop();game.started=true;game.welcome.hide();game.online.panel.hide();game.online_mode=true
	var c: Node=game.online;c.set_process(false);c.active=true;c.streaming=true;c.session.queue_free();var wire: Capture=Capture.new();c.add_child(wire);wire.set_process(false);c.session=wire
	check(game.load_map(48),"Repaired Estaq map loads")
	for y: int in [40,41,42]:
		game.player_tile=Vector2i(1,y);game.moving=false;c.transition_pending=false;c.pending_inputs.clear();c.recovering=false;c.defeated=false
		check(game._walkable(Vector2i(0,y)),"Repaired exit is walkable in exported phone geometry")
		game._request_path(Vector2i(0,y));check(game.route==[Vector2i(0,y)],"Touch navigation reaches the exit")
		c.request_step(Vector2i.LEFT)
		check(not wire.calls.is_empty() and wire.calls.back().op=="move" and wire.calls.back().fields.x==0 and wire.calls.back().fields.y==y,"Exit submits an authoritative native move")
		check(c.transition_pending,"Exit waits for native map transition")
	check(game.load_map(16),"Port map loads")
	check(game._walkable(Vector2i(49,15)),"Desert boat entrance remains open")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"three_exit_touch_paths":true,"native_warp_requests":true,"port_unchanged":true}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("TRAVEL MOBILE: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
