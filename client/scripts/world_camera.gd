extends Camera2D
## Keep world artwork on one display sampling phase while the camera pans.
# A third-pixel phase avoids exact nearest-texel boundary ties at common zooms.
# Quantizing around this phase still moves the camera by at most half a display pixel.
const PIXEL_PHASE: Vector2 = Vector2(1.0/3.0,1.0/3.0)

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
