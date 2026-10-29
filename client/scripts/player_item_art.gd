extends RefCounted
## Optional compact player/item art, independent of NPCs and illustrated outfits.
const ROOT:String="res://content/visual_enhanced/"
const PACK:String=ROOT+"pack.json"
var settings_path:String="user://graphics.cfg"
var enabled:bool=true
var frames:Dictionary={}
var images:Dictionary={}
var poses:Array=[]
var sizes:Dictionary={}
var atlas_textures:Dictionary={}
var atlas_images:Dictionary={}
var frame_cache:Dictionary={}
var image_textures:Dictionary={}

func frame_key(path:String,r:Array)->String:
	return path+"|%d,%d,%d,%d"%[int(r[0]),int(r[1]),int(r[2]),int(r[3])]

func collect(value:Variant,result:Dictionary)->void:
	if value is Dictionary:
		if value.has("path") and value.has("region"):result[frame_key(value.path,value.region)]=value
		else:
			for child:Variant in value.values():collect(child,result)
	elif value is Array:
		for child:Variant in value:collect(child,result)

func integers(raw:Variant,count:int)->bool:
	if not raw is Array or raw.size()!=count:return false
	for value:Variant in raw:
		if not (value is int or value is float) or float(value)!=floorf(float(value)) or float(value)<0:return false
	return true

func region_valid(entry:Variant)->bool:
	if not entry is Dictionary:return false
	var path:String=str(entry.get("path",""));var r:Variant=entry.get("region",[])
	if not sizes.has(path) or not integers(r,4):return false
	var size:Vector2=sizes[path]
	return r[2]>0 and r[3]>0 and r[0]+r[2]<=size.x and r[1]+r[3]<=size.y

func configure(manifest:Dictionary)->void:
	frames.clear();images.clear();poses.clear();sizes.clear();clear_cache()
	var expected:Dictionary={}
	for key:String in manifest.get("characters",{}):
		if key not in ["npcs","monster"]:collect(manifest.characters[key],expected)
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(PACK)) if FileAccess.file_exists(PACK) else null
	if data is Dictionary and int(data.get("schema",0))==2:
		if data.get("atlases",{}) is Dictionary:
			for path:String in data.atlases:
				var raw:Variant=data.atlases[path]
				if path.begins_with(ROOT) and ".." not in path and integers(raw,2) and raw[0]>0 and raw[1]>0 and raw[0]<=2048 and raw[1]<=2048 and ResourceLoader.exists(path):sizes[path]=Vector2(raw[0],raw[1])
		if data.get("poses",[]) is Array:
			for e:Variant in data.poses:
				var valid:bool=region_valid(e) and integers(e.get("visible_bounds",[]),4)
				if valid:
					var v:Array=e.visible_bounds
					valid=v[0]+v[2]<=e.region[2] and v[1]+v[3]<=e.region[3]
				poses.append(e if valid else {})
		if data.get("frames",{}) is Dictionary:
			for key:String in data.frames:
				var e:Variant=data.frames[key]
				if not expected.has(key) or not e is Array or e.size()!=6 or not integers(e.slice(0,5),5) or not e[5] is bool or int(e[0])>=poses.size():continue
				var p:Dictionary=poses[int(e[0])];var r:Array=expected[key].region
				if p.is_empty() or e[3]<=0 or e[4]<=0 or e[1]+e[3]>r[2] or e[2]+e[4]>r[3] or p.region[2]!=e[3]*2 or p.region[3]!=e[4]*2:continue
				frames[key]=e
		var expected_images:Dictionary={}
		for key:String in manifest.get("graphics",{}):
			if key.begins_with("23:"):
				var image:Dictionary=manifest.graphics[key];expected_images[image.path]=[image.width,image.height]
		if data.get("images",{}) is Dictionary:
			for path:String in data.images:
				var e:Variant=data.images[path]
				if not expected_images.has(path) or not e is Array or e.size()!=4 or not integers(e.slice(0,3),3) or not e[3] is bool or int(e[0])>=poses.size():continue
				var p:Dictionary=poses[int(e[0])];var native:Array=expected_images[path]
				if p.is_empty() or e[1]!=native[0] or e[2]!=native[1] or p.region[2]!=e[1]*2 or p.region[3]!=e[2]*2:continue
				images[path]=e
	var config:ConfigFile=ConfigFile.new()
	if config.load(settings_path)==OK:enabled=bool(config.get_value("graphics","players_and_items",true))

func ready()->bool:return not frames.is_empty() and not images.is_empty()

func clear_cache()->void:
	atlas_textures.clear();atlas_images.clear();frame_cache.clear();image_textures.clear()

func select(value:bool,persist:bool=true)->bool:
	enabled=value;clear_cache()
	if not persist:return true
	var config:ConfigFile=ConfigFile.new();config.load(settings_path)
	config.set_value("graphics","players_and_items",enabled);return config.save(settings_path)==OK

func atlas(path:String)->Texture2D:
	if not sizes.has(path):return null
	if not atlas_textures.has(path):
		var source:Texture2D=load(path) as Texture2D
		if source==null or source.get_size()!=sizes[path]:atlas_textures[path]=null;return null
		var smooth:CanvasTexture=CanvasTexture.new();smooth.diffuse_texture=source;smooth.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		atlas_textures[path]=smooth
	return atlas_textures[path] as Texture2D

func frame(original:Dictionary)->Dictionary:
	if not enabled or not original.has("region") or not original.has("path"):return original
	var key:String=frame_key(original.path,original.region)
	if not frames.has(key):return original
	var e:Array=frames[key];var p:Dictionary=poses[int(e[0])]
	if atlas(p.path)==null:return original
	var offset:Array=original.get("offset",[0,0])
	var cache_key:String=key+str(offset)
	if frame_cache.has(cache_key):return frame_cache[cache_key]
	var r:Array=original.region;var result:Dictionary=original.duplicate()
	result.path=p.path;result.region=p.region;result.pixel_scale=2;result.flip_h=e[5];result.visible_bounds=p.visible_bounds.duplicate()
	if result.flip_h:result.visible_bounds[0]=result.region[2]-result.visible_bounds[0]-result.visible_bounds[2]
	result.offset=[float(offset[0])-float(r[2])/2.0+float(e[1])+float(e[3])/2.0,float(offset[1])-float(r[3])+float(e[2])+float(e[4])]
	frame_cache[cache_key]=result;return result

func image(path:String)->Texture2D:
	if not enabled or not images.has(path):return null
	if image_textures.has(path):return image_textures[path]
	var e:Array=images[path];var p:Dictionary=poses[int(e[0])];var sheet:Texture2D=atlas(p.path)
	if sheet==null:return null
	if not atlas_images.has(p.path):atlas_images[p.path]=sheet.get_image()
	var r:Array=p.region;var pixels:Image=atlas_images[p.path].get_region(Rect2i(r[0],r[1],r[2],r[3]))
	if bool(e[3]):pixels.flip_x()
	var texture:ImageTexture=ImageTexture.create_from_image(pixels);texture.set_size_override(Vector2i(e[1],e[2]))
	var smooth:CanvasTexture=CanvasTexture.new();smooth.diffuse_texture=texture;smooth.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	image_textures[path]=smooth;return smooth
