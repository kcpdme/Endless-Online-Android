extends SceneTree
## Reproduce the handset overflow with every real class description and viewport.
var checks: int = 0
var failed: bool = false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game); await process_frame
	game.online_mode = true
	game.online.player = {"name":"Layout fixture","level":45,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"stats":{"class_id":7}}
	var ui: RefCounted = game.stats_ui
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1544,720)]:
		root.size = dimensions; await process_frame
		for clas: int in range(2,8):
			game.online.player.stats.class_id = clas
			game.online.refresh_game_ui()
			ui.show_stats(); await process_frame; await process_frame
			var card: Control = ui.panel.get_child(0)
			var scroll: ScrollContainer = ui.details.get_parent()
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(card.get_global_rect()),"Stats card fits phone viewport")
			check(card.get_global_rect().encloses(scroll.get_global_rect()) and scroll.clip_contents,"Class guidance stays clipped inside its card")
			check(not ui.details.text.is_empty() and ui.details.text.contains(str(game.online.catalog.classes[str(clas)].signature.description)),"Full class description remains available")
			scroll.scroll_vertical = 100000
			await process_frame; await process_frame
			check(ui.details.get_global_rect().end.y <= scroll.get_global_rect().end.y + 2,"Scrolling reaches the final class guidance line")
			check(game.paperdoll.information_labels[2].text == str(game.online.catalog.classes[str(clas)].name),"Equipment screen displays the current class")
			ui.close_stats()
	print("CLASS GUIDANCE LAYOUT: ",JSON.stringify({"result":"failed" if failed else "passed","checks":checks,"classes":6,"viewports":2}))
	game.queue_free(); await process_frame; quit(1 if failed else 0)
