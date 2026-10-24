extends SceneTree
## GPU-baked cutout animation, keeping the generated source sheet untouched.
const CELL: Vector2i = Vector2i(192,320)
const SCALE: int = 4
const ROOT: String = "res://art_packs/painted_v1/draft/pilot/"
const STATES: Dictionary = {"idle":1,"frames":4,"attack":2,"cast":1,"ranged_attack":2,"sit_chair":1,"sit_floor":1}
const DIRECTIONS: Array[String] = ["south","east","north","west"]
class Rig extends Node2D:
	var texture: Texture2D
	var bounds: Rect2
	var source_size: Vector2
	var pose: String = "idle"
	var frame: int = 0
	var direction: String = "south"
	var body_height: float = 248.0
	var mesh: ArrayMesh
	var invalid_mesh: bool = false
	func displace(uv: Vector2) -> Vector2:
		var size: Vector2 = Vector2(bounds.size.x / bounds.size.y * body_height,body_height)
		var p: Vector2 = Vector2(96,288) + (uv - Vector2(.5,1)) * size
		var side: float = clampf((uv.x-.5)*3.0,-1.0,1.0)
		var leg: float = smoothstep(.51,.92,uv.y)
		var arm: float = smoothstep(.22,.33,uv.y) * (1.0-smoothstep(.56,.65,uv.y)) * smoothstep(.13,.28,absf(uv.x-.5))
		var upper: float = 1.0-smoothstep(.40,.78,uv.y)
		var axis: Vector2 = Vector2(-.894,.447) if direction == "south" else Vector2(.894,.447) if direction == "east" else Vector2(.894,-.447) if direction == "north" else Vector2(-.894,-.447)
		if pose == "frames":
			var phase: float = float(frame) * TAU / 4.0 + PI/4.0
			var swing: float = sin(phase) * side
			p += axis * (leg * swing * 11.0 - arm * swing * 7.0)
			p.y -= leg * maxf(0.0,cos(phase)*side) * 6.0
			p.y -= upper * absf(cos(phase)) * 2.0
		elif pose in ["attack","ranged_attack"]:
			var reach: float = -3.0 if frame == 0 else 8.0
			var near_arm: float = arm * (1.0 if (uv.x < .5) == (direction in ["south","west"]) else .18)
			p += axis * (near_arm * reach + upper * (2.0 if frame == 0 else 7.0))
			p.y -= near_arm * (8.0 if frame == 1 else 2.0)
		elif pose == "cast":
			p += Vector2(side * 3.0,-8.0) * arm
			p.y -= upper * 3.0
		return p
	func _draw() -> void:
		if texture == null: return
		var vertices: PackedVector3Array = []
		var uvs: PackedVector2Array = []
		var indices: PackedInt32Array = []
		const X: int = 24
		const Y: int = 64
		for y: int in range(Y+1):
			for x: int in range(X+1):
				var unit: Vector2 = Vector2(float(x)/X,float(y)/Y)
				var p: Vector2 = displace(unit)
				vertices.append(Vector3(p.x,p.y,0))
				uvs.append((bounds.position + unit*bounds.size)/source_size)
		for y: int in range(Y):
			for x: int in range(X):
				var a: int = y*(X+1)+x
				indices.append_array([a,a+1,a+X+1,a+1,a+X+2,a+X+1])
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		invalid_mesh = false
		for i: int in range(0,indices.size(),3):
			var a: Vector3 = vertices[indices[i]]; var b: Vector3 = vertices[indices[i+1]]; var c: Vector3 = vertices[indices[i+2]]
			if (b-a).cross(c-a).z <= .001: invalid_mesh = true
		arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
		mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		draw_mesh(mesh,texture)

func _initialize() -> void: call_deferred("run")
func clean_pixel(c: Color) -> bool:
	# The generated export has a stray saturated red matte; treat it as an import
	# color key. This does not alter the source file or legitimate auburn shading.
	return c.a >= .20 and not (c.r > .70 and c.g < .19 and c.b < .19)
func cell_bounds(image: Image, row: int, col: int) -> Rect2:
	var rect: Rect2i = Rect2i(col*image.get_width()/4,row*image.get_height()/2,image.get_width()/4,image.get_height()/2)
	var low: Vector2i = rect.end; var high: Vector2i = rect.position
	for y: int in range(rect.position.y,rect.end.y):
		for x: int in range(rect.position.x,rect.end.x):
			if clean_pixel(image.get_pixel(x,y)):
				low = low.min(Vector2i(x,y)); high = high.max(Vector2i(x+1,y+1))
	return Rect2(Vector2(low),Vector2(high-low))
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Use a graphical backend for GPU baking"); quit(1); return
	var sources: Dictionary = {"standing":Image.load_from_file(ROOT+"source.png"),"sit_chair":Image.load_from_file(ROOT+"source_chair.png"),"sit_floor":Image.load_from_file(ROOT+"source_floor.png")}
	var textures: Dictionary = {}
	for key: String in sources: textures[key] = ImageTexture.create_from_image(sources[key])
	var view: SubViewport = SubViewport.new(); view.size = CELL; view.transparent_bg = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var rig: Rig = Rig.new(); rig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shader: Shader = Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ vec4 c=texture(TEXTURE,UV); if(c.a<0.20 || (c.r>0.70 && c.g<0.19 && c.b<0.19)) discard; COLOR=c; }"
	var material: ShaderMaterial = ShaderMaterial.new(); material.shader = shader; rig.material = material; view.add_child(rig)
	var appearances: Dictionary = {}
	for gender: int in [1,0]:
		var atlas: Image = Image.create(CELL.x*8,CELL.y*6,false,Image.FORMAT_RGBA8)
		var character: Dictionary = {"name":"Painted peasant","animation_method":"cutout_mesh_v1","ranged":false}
		var frames: int = 0
		for state: String in STATES:
			var source_key: String = state if state in ["sit_chair","sit_floor"] else "standing"
			var source: Image = sources[source_key]
			rig.texture = textures[source_key]; rig.source_size = source.get_size()
			rig.body_height = 200.0 if state == "sit_chair" else 160.0 if state == "sit_floor" else 248.0
			character[state] = {}
			for index: int in range(4):
				var direction: String = DIRECTIONS[index]
				var group: Array = []
				rig.bounds = cell_bounds(source,0 if gender == 1 else 1,index); rig.direction = direction; rig.pose = state
				for pose_frame: int in range(STATES[state]):
					rig.frame = pose_frame; rig.queue_redraw()
					await process_frame; await RenderingServer.frame_post_draw
					var image: Image = view.get_texture().get_image()
					var used: Rect2i = image.get_used_rect()
					if rig.invalid_mesh or not used.has_area() or used.position.x <= 1 or used.end.x >= CELL.x-1 or used.position.y <= 1 or used.end.y >= CELL.y-1:
						push_error("Empty or clipped painted pose: %s %s %d" % [state,direction,pose_frame]); quit(1); return
					var dest: Vector2i = Vector2i(frames%8*CELL.x,frames/8*CELL.y)
					atlas.blit_rect(image,Rect2i(Vector2i.ZERO,CELL),dest)
					group.append({"path":ROOT+"peasant_%d.png"%gender,"region":[dest.x,dest.y,CELL.x,CELL.y],"pixel_scale":4,"logical_canvas":[192,192],"trim_offset":[72,112],"offset":[0,8]})
					frames += 1
				character[state][direction] = group[0] if state == "idle" else group
		if frames != 48: push_error("Incomplete painted animation set"); quit(1); return
		atlas.save_png(ROOT+"peasant_%d.png"%gender)
		var record: Dictionary = {"gender":gender,"race":0,"hairstyle":1,"haircolor":0,"boots":4,"armor":16 if gender == 1 else 14,"hat":0,"shield":0,"weapon":0}
		appearances["peasant_male" if gender == 1 else "peasant_female"] = {"match":record,"character":character}
	var file: FileAccess = FileAccess.open(ROOT+"appearances.json",FileAccess.WRITE); file.store_string(JSON.stringify(appearances,"  ")+"\n")
	print("PAINTED PILOT BAKE: 2 appearances, 96 directional animation frames")
	view.queue_free(); await create_timer(.2).timeout; quit()
