extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	var now: float = 0.0
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate(),"at":now})
		return calls.size()
var game: Node
var failed: bool = false
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed=true
		push_error(message)
func _run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide();game.online.panel.hide()
	var c: Node=game.online
	c.set_process(false)
	c.session.queue_free()
	var wire: Capture=Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session=wire
	c.active=true
	c.streaming=true
	game.online_mode=true
	game.started=true
	game.world={"id":40,"width":250,"height":250,"warps":[]}
	game.server_blocked.clear()
	game.player_tile=Vector2i(40,40)
	game.player_world=game.tile_position(game.player_tile)
	c.player={"player_id":100,"character_id":100,"map_id":40,"x":40,"y":40,"hp":500,"max_hp":1000,"tp":100,"max_tp":100,"stats":{"class_id":2,"level":1},"inventory":[{"id":375,"amount":5}],"spells":[{"id":1,"level":1}]}
	c._sync_inventory()
	game.quick_items.slots.assign([375,0])
	game.stick=Vector2.RIGHT
	game.touch_move_id=41
	c._start_step(Vector2i(41,40),"east")
	c.pending_inputs.append({"seq":1,"direction":Vector2i.RIGHT,"sent_at":Time.get_ticks_msec()})
	game.quick_items.press(0)
	check(wire.calls.back().op=="potion_use" and game.moving and game.stick==Vector2.RIGHT and game.touch_move_id==41,"Quick potion must send while preserving the movement finger")
	check(c.bag_amount(375)==5,"Potion cannot be consumed optimistically")
	var count: int=wire.calls.size()
	for i: int in range(4): game.quick_items.press(0)
	check(wire.calls.size()==count+3 and c.pending_potion_requests.size()==4,"Rapid potion taps must pipeline at most four real native uses")
	wire.pending[99]={"op":"potion_use"}
	check(not wire.has_blocking_requests(),"An in-flight potion must not stop walking or skill casting")
	wire.pending.clear()
	for i: int in range(4): c._process_events([{"kind":"item_used","item_id":375,"remaining":4,"hp_gain":100}])
	check(not c.pending_item_use,"Native potion ACK must release the shortcut")
	game.skills_ui.refresh()
	game.skills_ui.slots.assign([1,0])
	game.skills_ui.press(0)
	check(wire.calls.back().op=="spell_cast" and not game.skills_ui.casting.is_empty(),"Self skill must cast while walking with an outstanding walk ACK")
	check(game.moving and game.stick==Vector2.RIGHT and game.touch_move_id==41,"Skill shortcut must preserve the movement finger")
	var skill_deadline: int=game.skills_ui.ready_at
	var local_release: int=int(game.skills_ui.casting.until)
	check(skill_deadline-local_release==480,"Self Heal recovery must be the original four120ms cast poses")
	# Confirmation may arrive late; it must never start a new600ms button lock.
	game.skills_ui.receive({"casting":null})
	check(game.skills_ui.ready_at==skill_deadline and game.skills_ui.casting.is_empty(),"Heal acknowledgement must preserve the local recovery deadline")
	# When the local pose deadline has passed, a late native ACK allows another tap.
	game.skills_ui.casting={"spell_id":1,"until":Time.get_ticks_msec()-1000,"seconds":.48}
	game.skills_ui.ready_at=Time.get_ticks_msec()-1
	game.skills_ui.receive({"casting":null})
	game.skills_ui.press(0)
	check(not game.skills_ui.casting.is_empty() and wire.calls.back().op=="spell_cast","Late confirmation must allow the next Self Heal immediately, without600ms extra")
	game.skills_ui.cancel_cast()
	check(game.skills_ui.ready_at==0,"Rejected or cancelled skill must release its local recovery lock")
	game.skills_ui.chants.clear()
	game._cancel_controls(true)
	c.pending_inputs.clear()
	wire.calls.clear()
	game.attack_touch_id=22
	game.attack_clock=0
	game._attack()
	check(is_equal_approx(game.swing_clock,.48),"An actual local attack must start the full480ms online swing")
	game.attack_clock=0
	wire.calls.clear()
	for frame: int in range(360):
		wire.now=frame/60.0
		game._process(1.0/60.0)
	var attacks: Array[float]=[]
	for request: Dictionary in wire.calls:
		if request.op=="strike": attacks.append(float(request.at))
	var mean: float=(attacks.back()-attacks[0])/(attacks.size()-1)
	check(attacks.size()==12 and absf(mean-.52)<.005,"Held attack timer must match native520ms pace instead of accumulating frame gaps: "+str(mean))
	var art: Dictionary={"attack":{"south":[{"pose":0},{"pose":1},{"pose":2},{"pose":3}]}}
	check(game._frame(art,"south","attack",.12).pose==1 and game._frame(art,"south","attack",.40).pose==3,"Online swing must follow original120ms attack poses through480ms")
	game._release_attack()
	var chat: RefCounted=game.chat_ui
	chat.messages.clear()
	for i: int in range(80): chat.messages.append({"channel":"global","name":"devfixture","message":"History row %d has enough text to read" % i,"time":"12:00"})
	chat.open()
	chat.channel.select(1)
	chat._refresh()
	chat._render_feed()
	await process_frame
	await process_frame
	var bar: VScrollBar=chat.history.get_v_scroll_bar()
	bar.value=bar.max_value-bar.page
	var bottom: float=bar.value
	var touch: InputEventScreenTouch=InputEventScreenTouch.new()
	touch.index=91
	touch.pressed=true
	chat._scroll_input(chat.history,touch)
	var drag: InputEventScreenDrag=InputEventScreenDrag.new()
	drag.index=91
	drag.relative=Vector2(0,100)
	chat._scroll_input(chat.history,drag)
	var reading: float=bar.value
	check(reading<bottom and not chat.history.scroll_following,"Finger drag must scroll chat history upwards")
	chat.messages.append({"channel":"global","name":"devfixture","message":"New message while reading older chat","time":"12:01"})
	chat._refresh()
	await process_frame
	await process_frame
	check(absf(bar.value-reading)<2,"Incoming chat must preserve the older message being read")
	check(chat.feed.scroll_active and chat.feed.get_parsed_text().contains("History row 0"),"HUD feed must retain scrollable history beyond four messages")
	chat.close()
	# Removing dead boss children clears collision and interpolation together.
	c.npcs.assign([{"id":256,"index":1,"x":42,"y":40}])
	c._track_entities("npc",c.npcs,"index")
	c._apply_snapshot({"npcs_remove":[1],"events":[{"kind":"npc_despawn","npc_id":256,"indexes":[1]}]})
	check(c.npcs.is_empty() and not c.remote_motion.has("npc:1") and not c.npc_occupies(Vector2i(42,40)),"Boss child despawn must remove frozen sprite tracks and collision")
	print("MOBILE COMBAT ","FAIL" if failed else "PASS",": potion/skill during walking, native ACK only, despawn cleanup, held attack mean=",mean,"s, touch chat history and preserved scroll")
	game.started=false
	game.queue_free()
	await create_timer(.2).timeout
	quit(1 if failed else 0)
