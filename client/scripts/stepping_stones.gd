extends RefCounted
## EO Jump tiles (29): first walking pose and the reference 8/16/16/8 lift.
const JUMP_SPEC: int = 29
const HEIGHTS: Array[float] = [0.0, -8.0, -16.0, -16.0, -8.0, 0.0]

func crosses(specs: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	return absi(to.x-from.x)+absi(to.y-from.y)==1 and (int(specs.get(from,-1))==JUMP_SPEC or int(specs.get(to,-1))==JUMP_SPEC)

func lift(progress: float) -> float:
	if progress<=0.0 or progress>=1.0: return 0.0
	# Interpolate the reference key heights to avoid vertical snaps on phones.
	var frame: float = progress*5.0
	var index: int = mini(int(frame),4)
	return lerpf(HEIGHTS[index],HEIGHTS[index+1],frame-index)

func pose(base: Dictionary, specs: Dictionary, from: Vector2i, to: Vector2i, progress: float) -> Dictionary:
	var visual: Dictionary = base.duplicate()
	visual.ground_position = base.position
	visual.hopping = str(base.state)=="frames" and progress>=0.0 and progress<1.0 and crosses(specs,from,to)
	if visual.hopping:
		visual.position = (base.position as Vector2)+Vector2(0,lift(progress))
		visual.phase = 0.0 # All paperdoll layers hold the first walk frame.
	return visual
