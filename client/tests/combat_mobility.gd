extends SceneTree
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
 checks += 1
 if not ok: failed = true; push_error(why)
func run() -> void:
 var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
 game.set_process(false); game.online.set_process(false); game.online.session.set_process(false)
 var c: Node = game.online
 game.online_mode = true; game.player_tile = Vector2i(35,45); game.facing = "east"
 c.player={"player_id":1,"combat":{"attack_seconds":.3467,"close_attack_seconds":.26,"close_range":2,"move_seconds":.21}}
 c.catalog={"npcs":{"1":{"type":1},"321":{"type":6},"306":{"type":0}}}
 c.npcs.assign([{"index":1,"id":1,"x":38,"y":45}])
 check(is_equal_approx(game._online_attack_seconds(),.3467),"Scav retains its far cadence at three tiles")
 c.npcs[0].x=37
 check(is_equal_approx(game._online_attack_seconds(),.26),"Scav gets close cadence at two tiles")
 game.facing="west"
 check(is_equal_approx(game._online_attack_seconds(),.3467),"Side and rear targets do not grant close firing")
 game.facing="east";c.npcs[0].id=321
 check(is_equal_approx(game._online_attack_seconds(),.3467),"Merchant cannot grant close firing")
 c.npcs[0].id=306
 check(is_equal_approx(game._online_attack_seconds(),.3467),"Untargetable pet cannot grant close firing")
 c.npcs[0].id=1;game.server_blocked[Vector2i(36,45)]=true
 check(is_equal_approx(game._online_attack_seconds(),.3467),"Wall prevents close firing bonus through the intermediate tile")
 game.server_blocked.clear();c.npcs.clear()
 c.players.assign([{"player_id":2,"x":37,"y":45}]);c.world_rules={"pk":true}
 check(is_equal_approx(game._online_attack_seconds(),.26),"PK target directly ahead gets close cadence")
 c.world_rules={"pk":false}
 check(is_equal_approx(game._online_attack_seconds(),.3467),"Peaceful nearby player cannot grant close cadence")
 c._start_step(Vector2i(36,45),"east")
 check(is_equal_approx(game.step_duration,.21),"Rogue prediction uses server movement metadata")
 game.animation_clock=.105
 check(is_equal_approx(float(game.local_render_pose().phase),.21),"Rogue walking animation scales with its faster tile movement")
 c.player.combat.move_seconds=.42;c._start_step(Vector2i(37,45),"east")
 check(is_equal_approx(game.step_duration,.42),"Class change immediately restores ordinary prediction")
 game.moving=false;c.remote_motion.clear()
 var peers: Array[Dictionary]=[{"player_id":2,"x":35,"y":45,"direction":3,"move_seconds":.21}]
 c._track_entities("player",peers,"player_id",0)
 peers[0].x=36
 c._track_entities("player",peers,"player_id",.1)
 var motion: Dictionary=c.remote_motion["player:2"];var step: Dictionary=motion.steps[0]
 check(is_equal_approx(float(step.duration),.21),"Remote Rogue interpolation retains its own duration")
 var sample: Dictionary=c._remote_sample("player:2",Vector2.ZERO,float(step.start)+.105)
 check(is_equal_approx(float(sample.step_progress),.5),"Remote fast walk interpolates halfway at half its duration")
 check(is_equal_approx(float(sample.phase),.21),"Remote Rogue animation scales to its fast duration")
 print(JSON.stringify({"result":"failed" if failed else "passed","checks":checks}))
 game.online.active=false;game.online_mode=false;game.queue_free();await process_frame;await process_frame;quit(1 if failed else 0)
