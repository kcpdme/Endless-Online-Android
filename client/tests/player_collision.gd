extends SceneTree
class Wire extends "res://scripts/online_session.gd":
	var calls:Array[Dictionary]=[]
	func request(op:String,fields:Dictionary={})->int:
		calls.append({"op":op,"fields":fields.duplicate(true)});return calls.size()
var game:Node
var wire:Wire
var checks:int=0
var failed:bool=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func moves()->Array:
	return wire.calls.filter(func(c:Dictionary)->bool:return c.op=="move")
func reset()->void:
	game._cancel_movement(true)
	game.online.pending_inputs.clear();game.online.players.clear();game.online.npcs.clear();game.online.remote_motion.clear();game.online.reset_player_block();game.movement_keys.clear();wire.calls.clear()
	game.moving=false;game.attack_clock=0;game.route.clear();game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.facing="east"
	game.online.player.x=40;game.online.player.y=40;game.online.player.direction=3
func ack(x:int,y:int,correction:bool,seq:int=-1)->void:
	var p:Dictionary=game.online.player.duplicate(true);p.x=x;p.y=y
	game.online._apply_snapshot({"player":p,"position_update":true,"position_seq":game.online.next_input_seq if seq<0 else seq,"correction":correction})
func run()->void:
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop()
	for card:Control in game.modal_cards:card.get_parent().hide()
	game.online.session.queue_free();wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	game.started=true;game.online_mode=true;game.online.active=true;game.online.streaming=true
	game.online.player={"player_id":100,"name":"Fixture","map_id":int(game.world.id),"x":40,"y":40,"direction":3,"sitting":0,"inventory":[],"equipment":{},"spells":[],"stats":{"class_id":1},"hp":10,"max_hp":10,"tp":10,"max_tp":10}
	game.server_blocked.clear();game.online.npcs.clear()
	reset();game.online.players.assign([{"player_id":101,"name":"Peer","x":41,"y":40}]);game.movement_keys.append(KEY_D)
	game.online.request_step(Vector2i.RIGHT)
	check(moves().is_empty() and not game.moving and game.player_tile==Vector2i(40,40),"Stationary player blocks before animation or a native refresh")
	check(not game._walkable(Vector2i(41,40)),"Pathfinding treats occupied player tiles as blocked")
	game.online.blocked_since=Time.get_ticks_msec()-4999;game.online.request_step(Vector2i.RIGHT)
	check(moves().is_empty(),"A hold shorter than five seconds cannot ghost")
	var up:InputEventKey=InputEventKey.new();up.keycode=KEY_D;up.physical_keycode=KEY_D;up.pressed=false;game._input(up)
	check(game.online.blocked_player==0,"Releasing a held key resets the entire ghost delay")
	game.movement_keys.append(KEY_D);game.online.request_step(Vector2i.RIGHT);game.online.blocked_since=Time.get_ticks_msec()-5000;game.online.request_step(Vector2i.RIGHT)
	check(moves().size()==1 and moves()[0].fields.ghost,"Continuous five-second hold sends explicit ghost walk")
	check(not game.moving and not game.online.can_issue_walk(),"Ghost animation waits for native acceptance; no duplicate queued steps")
	ack(41,40,false);check(game.moving and game.player_tile==Vector2i(41,40),"Only the native acknowledgement starts a ghost step")
	reset();game.online.players.assign([{"player_id":101,"name":"Peer","x":42,"y":40}])
	var now:float=Time.get_ticks_msec()/1000.0
	game.online.remote_motion["player:101"]={"steps":[{"from":game.tile_position(Vector2i(41,40)),"to":game.tile_position(Vector2i(42,40)),"start":now,"duration":.42}]}
	game.online.request_step(Vector2i.RIGHT)
	check(moves().is_empty() and game.online.player_blocker(Vector2i(41,40))==101,"Walking player's origin and destination stay reserved until the sprite clears")
	reset();game.online.players.assign([{"player_id":101,"name":"Peer","x":42,"y":40}]);game.movement_keys.append(KEY_D);game.online.request_step(Vector2i.RIGHT)
	check(moves().size()==1 and not game.moving and not moves()[0].fields.get("ghost",false),"Potential head-on shared tile waits for server without premature overlap")
	ack(40,40,true);check(not game.moving and game.player_tile==Vector2i(40,40) and game.movement_keys==[KEY_D] and not game.online.recovering,"Rejected contested step stays still and retains held direction")
	game.online.request_step(Vector2i.RIGHT);ack(41,40,false)
	check(game.moving and game.player_tile==Vector2i(41,40),"An accepted contested step begins normally")
	reset();game.online.request_step(Vector2i.RIGHT)
	check(game.moving and moves().size()==1,"Empty-area walking retains immediate prediction")
	reset();game.online.players.assign([{"player_id":101,"name":"Peer","x":41,"y":40}]);game.movement_keys.append(KEY_D);game.online.request_step(Vector2i.RIGHT);game.online.blocked_since=Time.get_ticks_msec()-6000
	game.server_blocked[Vector2i(41,40)]=true;game.online.request_step(Vector2i.RIGHT)
	check(moves().is_empty() and game.online.blocked_player==0,"Ghost never bypasses solid terrain")
	game.server_blocked.clear();game.online.request_step(Vector2i.RIGHT);game.online.blocked_since=Time.get_ticks_msec()-6000;game.movement_keys.clear();game.online.request_step(Vector2i.RIGHT)
	check(moves().is_empty() and game.online.blocked_player==0,"Automatic routes cannot accumulate a held-input ghost")
	reset();game.online.npcs.assign([{"index":8,"id":101,"x":42,"y":40,"direction":3}])
	game.online.remote_motion["npc:8"]={"steps":[{"from":game.tile_position(Vector2i(41,40)),"to":game.tile_position(Vector2i(42,40)),"start":now,"duration":20.0}]}
	game.online.request_step(Vector2i.RIGHT)
	check(moves().size()==1 and not game.moving and game.online.npc_occupies(Vector2i(41,40)),"Departing NPC origin permits a deferred request without animating through its sprite")
	reset();game.online.npcs.assign([{"index":8,"id":101,"x":42,"y":40,"direction":3}]);game.online.request_step(Vector2i.RIGHT)
	check(moves().size()==1 and game.moving,"A nearby NPC outside the destination does not pause clear-road prediction")
	game.movement_keys.append(KEY_D)
	ack(40,40,true);check(not game.moving and game.player_tile==Vector2i(40,40) and game.movement_keys==[KEY_D],"NPC race correction restores position while preserving held movement")
	reset();game.online.request_step(Vector2i.RIGHT)
	var first_seq:int=game.online.next_input_seq
	game._advance_walk(game.step_duration)
	game.online.npcs.assign([{"index":8,"id":101,"x":43,"y":40,"direction":3}])
	var origin:Vector2=game.tile_position(Vector2i(42,40))
	var destination:Vector2=game.tile_position(Vector2i(43,40))
	var departure:Dictionary={"from":origin,"to":destination,"start":Time.get_ticks_msec()/1000.0,"duration":20.0,"direction":"east"}
	game.online.remote_motion["npc:8"]={"to":destination,"tile":Vector2i(43,40),"steps":[departure],"walk_start":departure.start}
	game.movement_keys.append(KEY_D);game.online.request_step(Vector2i.RIGHT)
	check(moves().size()==2 and not game.moving,"A departing NPC can queue one contested step behind an earlier prediction")
	ack(41,40,false,first_seq)
	check(not game.moving and game.player_tile==Vector2i(41,40) and game.online.pending_inputs.size()==1,"Delayed earlier ACK cannot start the unaccepted contested step")
	ack(42,40,false)
	game._advance_walk(.1)
	check(game.moving and game.online.waiting_for_npc_clear and game.step_progress==0.0,"The contested step's own ACK still waits for the departing NPC sprite")
	departure.start=Time.get_ticks_msec()/1000.0-21.0;game._advance_walk(.01)
	check(game.step_progress>0.0 and not game.online.waiting_for_npc_clear,"Contested step starts as soon as its native ACK and visual clearance both exist")
	reset();game.online.npcs.assign([{"index":8,"id":101,"x":42,"y":40,"direction":3}]);game.movement_keys.append(KEY_D)
	var late:Dictionary={"from":game.tile_position(Vector2i(41,40)),"to":game.tile_position(Vector2i(42,40)),"start":Time.get_ticks_msec()/1000.0,"duration":.42,"direction":"east"}
	game.online.remote_motion["npc:8"]={"to":late.to,"tile":Vector2i(42,40),"steps":[late],"walk_start":late.start}
	game.online.request_step(Vector2i.RIGHT)
	check(not game.moving,"A late native ACK keeps a clear road stationary until accepted")
	late.start=Time.get_ticks_msec()/1000.0-1.0
	ack(41,40,false);game._advance_walk(.01)
	check(game.step_progress>0.0 and not game.online.waiting_for_npc_clear,"Late native acceptance begins immediately when the road is already clear")
	reset();game.online.npcs.assign([{"index":8,"id":319,"x":40,"y":40,"direction":2}])
	game.online._process_events([{"kind":"companion_attack","npc_index":8,"target_index":9,"direction":2,"damage":0}])
	var animation:Dictionary=game.online.entity_animation("online_npc",game.online.npcs[0])
	check(animation.state=="attack" and animation.direction=="north","Banshi attack animation uses the server's target facing")
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"five_second_continuous_hold":true,"moving_origins_reserved":true,"contested_steps_acknowledged_before_animation":true,"offline":true}
	var path:String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("PLAYER COLLISION: ",JSON.stringify(report));game.queue_free();await process_frame;quit(1 if failed else 0)
