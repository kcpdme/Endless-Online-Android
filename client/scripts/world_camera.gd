extends Camera2D
## Keep world artwork on one display sampling phase while the camera pans.
# A third-pixel phase avoids exact nearest-texel boundary ties at common zooms.
# Quantizing around this phase still moves the camera by at most half a display pixel.
const PIXEL_PHASE: Vector2 = Vector2(1.0/3.0,1.0/3.0)
const NORMAL_ZOOM:float=1.65
const CLOSE_ZOOM:float=NORMAL_ZOOM*1.25
var settings_path:String="user://graphics.cfg"
var zoomed:bool=false

func load_view()->void:
	var config:ConfigFile=ConfigFile.new()
	if config.load(settings_path)==OK:zoomed=bool(config.get_value("graphics","zoom_125",false))
	zoom=Vector2.ONE*(CLOSE_ZOOM if zoomed else NORMAL_ZOOM)

func select_view(close_view:bool,persist:bool=true)->bool:
	zoomed=close_view;zoom=Vector2.ONE*(CLOSE_ZOOM if zoomed else NORMAL_ZOOM)
	if not persist:return true
	var config:ConfigFile=ConfigFile.new();config.load(settings_path)
	config.set_value("graphics","zoom_125",zoomed)
	return config.save(settings_path)==OK

func _ready() -> void:
	# Follow movement and quake offsets before the screen-space inspection labels.
	process_priority = 90

func _process(_delta: float) -> void:
	align_to_display_pixels()

func align_to_display_pixels() -> void:
	force_update_scroll()
	var to_pixels: Transform2D = get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var correction: Vector2 = (to_pixels.origin - PIXEL_PHASE).round() + PIXEL_PHASE - to_pixels.origin
	# Only the rendered camera changes; authoritative and interpolated actor positions stay exact.
	global_position -= to_pixels.affine_inverse().basis_xform(correction)
	force_update_scroll()
