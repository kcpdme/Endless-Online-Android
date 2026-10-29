extends SceneTree
## Extract approved painted canonical poses without filtering or resampling.
func _initialize()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=3:push_error("Expected SOURCES.json PILOT_DIRECTORY OUTPUT_POSES");quit(1);return
	var sources:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var pack:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("pack.json")))
	DirAccess.make_dir_recursive_absolute(args[2])
	for gid:String in ["134","154"]:
		var atlas:Image=Image.load_from_file(args[1].path_join("npc"+gid+"_2x.png"))
		for item:Dictionary in sources[gid].frames:
			var raw:Variant=pack.graphics[gid][item.state][item.direction]
			var frame:Dictionary=raw[int(item.index)] if raw is Array else raw
			var r:Array=frame.region
			var image:Image=atlas.get_region(Rect2i(r[0],r[1],r[2],r[3]))
			if image.save_png(args[2].path_join(str(item.frame.path).get_file()))!=OK:quit(1);return
	print("Preserved approved painted NPC poses");quit()
