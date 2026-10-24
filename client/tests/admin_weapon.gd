extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.music.stop()
	var item: Dictionary = game.online.item_info("item:491")
	assert(item.get("name","") == "Skylar's Admin Blade")
	assert(int(item.get("type",0)) == 10 and int(item.get("special",0)) == 4)
	assert(int(item.get("min_damage",0)) == 1000 and int(item.get("max_damage",0)) == 1000)
	assert(game.online._catalog_texture(str(item.icon)) != null)
	assert(game.art_profile.mode == "classic" and not game.art_profile.ready())
	for gender: int in [0,1]:
		var character: Dictionary = game.online.character_graphic({"gender":gender,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[0,0,0,0,0,0,0,0,int(item.doll_graphic)]})
		for direction: String in ["south","east","north","west"]:
			for state: String in ["idle","frames","attack"]:
				var frame: Dictionary = game._frame(character,direction,state,0.0)
				assert(not frame.is_empty())
				for layer: Dictionary in frame.get("layers",[frame]): assert(game._texture(str(layer.path)) != null)
	print("ADMIN WEAPON: original icon, male/female world poses, Lore metadata, 1000 damage and Classic mode passed")
	game.queue_free(); await process_frame; quit()
