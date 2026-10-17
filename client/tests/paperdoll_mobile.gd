extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var game: Node
var failed: bool = false
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed=true
		push_error(message)
func tap(control: Control, index: int) -> void:
	var event: InputEventScreenTouch=InputEventScreenTouch.new()
	event.index=index
	event.position=control.get_global_rect().get_center()
	event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	Input.parse_input_event(event)
	await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://../work/v31-"+name+".png")
func _run() -> void:
	root.size=Vector2i(1280,720)
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.started=true
	game.online_mode=true
	var c: Node=game.online
	c.set_process(false)
	c.session.queue_free()
	var wire: Capture=Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session=wire
	c.active=true
	c.streaming=true
	c.player={"name":"devfixture","player_id":100,"character_id":100,"map_id":5,"x":40,"y":40,"level":120,"hp":500,"max_hp":1000,"tp":100,"max_tp":100,"equipment":{"weapon":21,"armor":143,"boots":80},"inventory":[{"id":375,"amount":20}],"spells":[{"id":1,"level":0},{"id":5,"level":0}],"stats":{"stat_points":12,"skill_points":20,"strength":100,"intelligence":100,"wisdom":100,"agility":90,"constitution":30,"charisma":10,"experience":123456,"max_sp":100,"min_damage":30,"max_damage":50,"armor":80,"weight":10,"max_weight":70}}
	c._sync_inventory()
	game._refresh_ui()
	game._toggle_paperdoll()
	var card: Control=game.character_panel.get_child(0)
	for child: Node in card.get_children():
		if child is Button:
			check(not child.text.begins_with("Remove") and child.text!="Item details","Profile must not have old details/remove buttons")
			check(card.get_global_rect().encloses(child.get_global_rect()),"Profile header button must fit inside the card")
	await shot("paperdoll")
	await tap(game.paperdoll.slots.weapon,81)
	await create_timer(.32).timeout
	check(game.stats_ui.item_panel.visible and not game.character_panel.visible,"Single equipment tap opens item details")
	check(game.stats_ui.item_body.text.contains("Damage") and game.stats_ui.item_heading.text.contains("Equipped"),"Equipment details must show the worn item")
	await shot("item")
	game._handle_back()
	check(game.character_panel.visible and not game.stats_ui.item_panel.visible,"Android Back from item details returns to paperdoll")
	await tap(game.paperdoll.slots.weapon,82)
	await tap(game.paperdoll.slots.weapon,83)
	await create_timer(.32).timeout
	var removals: int=0
	for request: Dictionary in wire.calls:
		if request.op=="unequip": removals+=1
	check(removals==1 and game.character_panel.visible and not game.stats_ui.item_panel.visible,"Double tap unequips exactly once without opening a details dialog")
	c.pending_equip.clear()
	game.stats_ui.show_stats()
	for button: Button in game.stats_ui.add_buttons:
		check(not button.disabled and (button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.g>(button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.r,"Available stat increment must be green")
	await shot("stats")
	game._handle_back()
	check(game.character_panel.visible,"Closing stats returns to character")
	game.character_panel.hide()
	# Bind the synthetic profile before overriding slots, as native enter does.
	game.skills_ui.refresh()
	game.skills_ui.slots.assign([1,5])
	c.player.hp=1000
	var before: int=wire.calls.size()
	game.skills_ui.press(0)
	check(wire.calls.size()==before and game.skills_ui.casting.is_empty(),"Full-health Self Heal must not become stuck or send a useless cast")
	check(bool(c.spell_labels[100].get("spell", false)) and str(c.spell_labels[100].text).contains("HP full"),"Full health uses a brief spell-name flash")
	c.player.hp=500
	game.skills_ui.press(1)
	c.npcs.assign([{"id":257,"index":47,"x":41,"y":40,"direction":0}])
	game.skills_ui.target(Vector2i(41,40))
	check(not game.skills_ui.casting.is_empty() and int(game.skills_ui.casting.spell_id)==5,"Small Thunder must target the selected NPC")
	check(not game.skills_ui.cast_hint.visible,"Casting must not show the old rectangle/banner")
	c._process_events([{"kind":"npc_damage","player_id":100,"spell_id":5,"npc_index":47,"npc_id":257,"x":41,"y":40,"damage":2000,"hp_percent":94,"own_cast":true}])
	check(game.skills_ui.casting.is_empty() and not game.skills_ui.effects.is_empty(),"A real Thunder hit clears casting without requiring a separate casting:null snapshot")
	var anchor: Vector2=c.npc_feedback_anchor(c.npcs[0],Vector2i(41,40))
	check(anchor.y<game.tile_position(Vector2i(41,40)).y-150,"Boss damage floats above its visible head")
	check(is_equal_approx(c.npc_health_fraction(47),.94),"Boss health uses native percentage")
	c.spell_labels[100].start=Time.get_ticks_msec()
	game.queue_redraw()
	await shot("bosscombat")
	c._process_events([{"kind":"npc_killed","player_id":100,"npc_index":47,"npc_id":257,"x":41,"y":40,"damage":2000,"exp_gain":6666}])
	var exp_seen: bool=false
	for number: Dictionary in game.damage_numbers:
		if number.value=="+6666 EXP": exp_seen=true
	check(exp_seen,"Kills must show actual earned EXP")
	print("PAPERDOLL MOBILE ","FAIL" if failed else "PASS",": single-tap details/back, double-tap unequip, unclipped profile, green stats, full-health heal, Thunder ACK, boss damage and EXP")
	game.started=false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
