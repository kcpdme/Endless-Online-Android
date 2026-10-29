extends SceneTree
## Extract tight original RGBA poses, deduplicated across all player layers/items.
var frames:Dictionary={}
var images:Dictionary={}
var crops:Dictionary={}
var groups:Dictionary={}
var masked:Dictionary={}
var output:String
var sprite_sources:Dictionary={}

func key(path:String,r:Array)->String:
	return path+"|%d,%d,%d,%d"%[int(r[0]),int(r[1]),int(r[2]),int(r[3])]

func collect(value:Variant)->void:
	if value is Dictionary:
		if value.has("path") and value.has("region"):
			var k:String=key(value.path,value.region)
			if not frames.has(k):
				frames[k]={"source":value.path,"source_region":value.region}
				if not sprite_sources.has(value.path):sprite_sources[value.path]=[]
				sprite_sources[value.path].append(k)
		else:
			for child:Variant in value.values():collect(child)
	elif value is Array:
		for child:Variant in value:collect(child)

func digest(image:Image,preserve:bool)->String:
	var hash:HashingContext=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update((str(image.get_size())+str(preserve)).to_utf8_buffer());hash.update(image.get_data())
	return hash.finish().hex_encode()

func store(image:Image,preserve:bool)->Dictionary:
	image.convert(Image.FORMAT_RGBA8)
	var id:String=digest(image,preserve)
	if crops.has(id):return {"id":id,"flip_h":false}
	image.flip_x();var mirrored:String=digest(image,preserve);image.flip_x()
	if crops.has(mirrored):return {"id":mirrored,"flip_h":true}
	if not crops.has(id):
		var path:String=output.path_join("crops/"+id+".png")
		assert(image.save_png(path)==OK)
		crops[id]={"size":[image.get_width(),image.get_height()],"preserve_black":preserve,"empty":not image.get_used_rect().has_area()}
	return {"id":id,"flip_h":false}

func _initialize()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:push_error("Expected MANIFEST.json OUTPUT_DIRECTORY");quit(1);return
	output=args[1];DirAccess.make_dir_recursive_absolute(output.path_join("crops"))
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var characters:Dictionary=manifest.characters
	for name:String in characters.equipment_layers.layers:
		if name.begins_with("hair:") or name.begins_with("head:"):
			var layer:Dictionary=characters.equipment_layers.layers[name]
			masked[str(layer.idle.south.path)]=true
	for name:String in characters:
		if name not in ["npcs","monster"]:collect(characters[name])
	for path:String in sprite_sources:
		var source:Image=Image.load_from_file(ProjectSettings.globalize_path(path))
		assert(source!=null,"Missing original player atlas: "+path)
		var ids:Dictionary={}
		for k:String in sprite_sources[path]:
			var r:Array=frames[k].source_region
			var pose:Image=source.get_region(Rect2i(r[0],r[1],r[2],r[3]))
			var used:Rect2i=pose.get_used_rect()
			var crop:Rect2i=used.grow(2).intersection(Rect2i(Vector2i.ZERO,pose.get_size())) if used.has_area() else Rect2i(0,0,1,1)
			var stored:Dictionary=store(pose.get_region(crop),masked.has(path));var id:String=stored.id
			frames[k].crop=[crop.position.x,crop.position.y,crop.size.x,crop.size.y]
			frames[k].id=id;frames[k].flip_h=stored.flip_h;ids[id]=true
		groups[path]=ids.keys()
	for k:String in manifest.graphics:
		if not k.begins_with("23:"):continue
		var path:String=manifest.graphics[k].path
		var image:Image=Image.load_from_file(ProjectSettings.globalize_path(path))
		assert(image!=null,"Missing original item: "+k)
		var stored:Dictionary=store(image,false)
		images[path]={"id":stored.id,"flip_h":stored.flip_h,"size":[image.get_width(),image.get_height()]}
	var jobs:Dictionary={"schema":1,"frames":frames,"images":images,"crops":crops,"groups":groups,"player_layers":characters.equipment_layers.layers.size()}
	FileAccess.open(output.path_join("jobs.json"),FileAccess.WRITE).store_string(JSON.stringify(jobs)+"\n")
	print("Prepared ",frames.size()," player poses, ",images.size()," item images, ",crops.size()," unique crops");quit()
