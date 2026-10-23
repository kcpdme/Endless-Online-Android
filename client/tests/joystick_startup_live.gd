extends "res://tests/movement_controls_live.gd"
## Exercise off-centre landings in the previously failing fixed/isometric combination.
func press_pad(direction: Vector2i, pressed: bool) -> void:
	game.joystick.fixed_base = true
	game.joystick.isometric = true
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 59
	event.position = game._joystick_zone().position + Vector2(240,190)
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed:
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 59
		drag.position = event.position + Vector2(direction) * 48
		Input.parse_input_event(drag)
