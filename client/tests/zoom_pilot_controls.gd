extends RefCounted
## Experimental controls only. Normal main.tscn does not instantiate this.
signal changed(value:float)
signal tapped(point:Vector2)
const BASE:float=1.65
const MINIMUM:float=.9
const MAXIMUM:float=1.5
var scale:float=1.0
var points:Dictionary={}
var origin:Vector2
var pinched:bool=false
var suppress_tap:bool=false
var initial_gap:float=0
var initial_scale:float=1
var eligible:Callable
var available:Callable

func set_scale(value:float)->void:
	if not is_finite(value):return
	scale=clampf(value,MINIMUM,MAXIMUM);changed.emit(scale)

func cancel()->void:
	# Keep ownership until release so a cancelled gesture cannot turn into a tap.
	suppress_tap=true;pinched=false;initial_gap=0

func reset()->void:
	points.clear();pinched=false;suppress_tap=false;initial_gap=0

func input(event:InputEvent)->bool:
	if event is InputEventMagnifyGesture:
		# Raw indexed touches own Android pinch; never apply its OS duplicate too.
		if not points.is_empty():return true
		if available.call() and eligible.call(event.position):set_scale(scale*event.factor);return true
		return false
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		# Godot may synthesize the mouse press before the native touch arrives.
		if event.device==InputEvent.DEVICE_ID_EMULATION and (not points.is_empty() or (available.call() and eligible.call(event.position))):return true
	if event is InputEventScreenTouch:
		if event.pressed:
			if not available.call() or not eligible.call(event.position):
				if not points.is_empty():cancel()
				return false
			if points.is_empty():origin=event.position;suppress_tap=false
			points[event.index]=event.position
			if points.size()==2:
				pinched=true;suppress_tap=true;initial_scale=scale
				var ids:Array=points.keys();initial_gap=points[ids[0]].distance_to(points[ids[1]])
			elif points.size()>2:cancel()
			return true
		if not points.has(event.index):return false
		var tap:bool=not suppress_tap and not pinched and points.size()==1 and not event.canceled and origin.distance_to(event.position)<14 and available.call()
		points.erase(event.index)
		if tap:tapped.emit(event.position)
		if points.is_empty():reset()
		return true
	if event is InputEventScreenDrag and points.has(event.index):
		points[event.index]=event.position
		if not available.call():cancel();return true
		if pinched and points.size()==2:
			var ids:Array=points.keys();var gap:float=points[ids[0]].distance_to(points[ids[1]])
			if initial_gap>=24:set_scale(initial_scale*gap/initial_gap)
			elif gap>=24:initial_gap=gap;initial_scale=scale
		elif points.size()==1 and origin.distance_to(event.position)>=14:suppress_tap=true
		return true
	return false
