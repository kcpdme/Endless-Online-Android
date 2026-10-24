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
	if not ok: failed=true;push_error(message)
func touch(at: Vector2,pressed: bool,canceled: bool=false) -> void:
	var event: InputEventScreenTouch=InputEventScreenTouch.new();event.index=63;event.position=root.get_final_transform()*at;event.pressed=pressed;event.canceled=canceled
	Input.parse_input_event(event);await process_frame;await process_frame
func drag(from: Vector2,to: Vector2) -> void:
	await touch(from,true)
	for step: int in range(1,7):
		var event: InputEventScreenDrag=InputEventScreenDrag.new();event.index=63;event.position=root.get_final_transform()*from.lerp(to,step/6.0);event.relative=root.get_final_transform().basis_xform((to-from)/6.0)
		Input.parse_input_event(event);await process_frame
	await touch(to,false)
func run() -> void:
	root.size=Vector2i(1600,720)
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.music.stop();game.set_process(false);game.started=true;game.online_mode=true;game.welcome.hide();game.online.panel.hide()
	var c: Node=game.online;c.set_process(false);c.active=true;c.session.queue_free();var wire: Capture=Capture.new();c.add_child(wire);wire.set_process(false);c.session=wire
	var journal: RefCounted=game.quest_journal;var entries: Array=[]
	for i: int in range(24):entries.append({"name":"Quest %d"%i,"description":"A long objective to read and scroll using one finger over the card.","progress":i,"target":30})
	journal.receive({"quest_journal":{"page":"progress","entries":entries}});journal.panel.show()
	for _i: int in range(5): await process_frame
	var bar: VScrollBar=journal.scroll.get_v_scroll_bar()
	check(bar.visible and bar.size.x>=36,"Quest scrollbar has a wide touch target")
	var at: Vector2=journal.scroll.get_global_rect().position+Vector2(160,220)
	await drag(at,at-Vector2(0,180));check(bar.value>=150,"Dragging quest card text scrolls directly")
	check(not game.joystick.active and c.interaction.is_empty(),"Quest swipe does not move or target the world")
	var before: float=bar.value;await drag(at,at+Vector2(0,120));check(bar.value<before,"Reverse drag returns toward the top")
	await drag(at,at-Vector2(0,500));check(bar.value>before,"Drag stays captured outside the dialog")
	journal.dismiss();var feature: RefCounted=game.feature_ui;feature.kind="emotes";feature.state={};feature.render();feature.panel.get_parent().move_child(feature.panel,-1);feature.panel.show();feature.layout()
	for _i: int in range(5): await process_frame
	var button: Button=feature.content.get_child(2) as Button;at=button.get_global_rect().get_center()
	var calls: int=wire.calls.size();await drag(at,at-Vector2(0,150))
	check(feature.scroll.scroll_vertical>80,"Dragging over buttons scrolls the service dialog")
	check(wire.calls.size()==calls,"A swipe never activates the button under the finger")
	feature.scroll.scroll_vertical=0;await process_frame;await process_frame
	feature.layout();await process_frame;await process_frame
	button=feature.content.get_child(0) as Button;at=button.get_global_rect().get_center()
	await touch(at,true)
	check(wire.calls.size()==calls,"Touch waits for tap versus drag decision")
	await touch(at,false);check(wire.calls.size()==calls+1 and wire.calls.back().op=="feature_action","A stationary tap activates exactly once")
	feature.busy=false;await touch(at,true);await touch(at,false,true);check(wire.calls.size()==calls+1,"Canceled touch never activates a button")
	feature.close();game.skills_ui.panel.show()
	var list: ItemList=game.skills_ui.list;list.clear()
	for i: int in range(80):list.add_item("Skill list entry %d"%i)
	for _i: int in range(5): await process_frame
	at=list.get_global_rect().position+Vector2(90,180);await drag(at,at-Vector2(0,140))
	check(list.get_v_scroll_bar().value>90,"Skill ItemList supports finger scrolling")
	check(list.get_v_scroll_bar().size.x>=36,"ItemList scrollbar is also wide")
	game.skills_ui.panel.hide();feature.kind="password";feature.render();feature.panel.get_parent().move_child(feature.panel,-1);feature.panel.show();feature.layout()
	for _i: int in range(3): await process_frame
	var editor: LineEdit=feature.fields.old_password;at=editor.get_global_rect().get_center();await touch(at,true);await touch(at,false)
	check(editor.has_focus(),"Text fields retain native tap and keyboard focus")
	feature.close()
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"quest_card_drag":true,"button_swipes_do_not_activate":true,"wide_scrollbars":true,"item_list_drag":true,"text_fields_preserved":true}
	var out: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not out.is_empty():var file: FileAccess=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("MOBILE SCROLL: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
